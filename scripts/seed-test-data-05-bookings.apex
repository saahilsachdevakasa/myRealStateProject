/**
 * ============================================================================
 * seed-test-data-05-bookings.apex — SCRIPT 5 OF 7
 * ============================================================================
 *
 * DEPENDS ON: scripts 01-04 having been COMMITTED (DRY_RUN = false).
 *   Re-queried at the top of this file:
 *     Booking__c      — the 3 Bookings BookingService created in script 04,
 *                       keyed on Unit__r.Name (Booking Name is an AutoNumber
 *                       sequence, so it is not reproducible across runs):
 *                         bkg1 ZSA-T01-F02-U002  residential, CP Horizon (Platinum)
 *                         bkg2 ZSB-B01-F01-S001  commercial,  CP Beacon (no GSTIN)
 *                         bkg3 ZSA-T01-F03-U004  residential, direct sale
 *     Payment_Plan__c — by Plan_Code__c = 'ZSCLP'
 *     Contact         — by '<first>.<last>.seed@recrm-demo.invalid' Emails
 *
 * PRODUCES:
 *   Booking__c enrichment (RT, Payment Plan, GST/stamp duty/fees)
 *   Booking_Customer__c x5
 *   Pricing_Component__c x18
 *   Booking_Payment_Schedule__c (instantiated by PaymentScheduleService)
 *   Demand__c (via DemandService), Receipt__c, Receipt_Allocation__c
 *     (via ReceiptAllocationService)
 *
 * HOW TO RUN
 *   sf apex run --file scripts/seed-test-data-05-bookings.apex --target-org re-crm-sdo
 *   Dry-run first (DRY_RUN = true), then commit, THEN run script 06.
 *
 * AUTOMATION THIS SCRIPT DELIBERATELY DRIVES
 *   - Setting Booking.Payment_Plan__c fires PaymentScheduleService, which
 *     instantiates Booking_Payment_Schedule__c rows from the plan milestones.
 *   - DemandService and ReceiptAllocationService are called as their real
 *     @InvocableMethods, bulkified, one invocation each.
 *
 * SEQUENCING CONSTRAINTS HONOURED IN THIS FILE
 *   (a) RecursionGuard is TRANSACTION-scoped. This script is its own transaction,
 *       so 'Booking_afterUpdate' starts CLEAN here — the after-save Flow
 *       Transfer_Booking_To_Post_Sales_Queue that consumed it in the original
 *       single-file script ran back in script 04's transaction. The
 *       RecursionGuard.reset('Booking_afterUpdate') below is therefore a no-op in
 *       normal sequence; it is retained deliberately as a cheap guarantee that
 *       PaymentScheduleService runs even if this block is ever re-ordered, merged
 *       into another script, or preceded by an added Booking update. There is
 *       exactly ONE Booking update statement in this file, so no further reset is
 *       needed. If you add a second Booking update that needs its handler to fire,
 *       reset the key again before it.
 *   (e) Gotcha #40: script 02 attempted to activate the seed Payment Plan in the
 *       same transaction as its milestone inserts and most likely failed. This
 *       script runs in a LATER transaction, which is exactly the cross-transaction
 *       retry gotcha #40 prescribes, so it makes one more opportunistic attempt
 *       below. Nothing downstream depends on it — PaymentScheduleService filters
 *       on Payment_Plan_Milestone__c.Active__c, not on the plan's Active__c.
 * ============================================================================
 */

// ===========================================================================
// CONFIG — must match the other scripts in the series
// ===========================================================================
Boolean DRY_RUN = false;   // true = roll everything back at the end

final String TAG       = 'SEED';
final String PROJ_A    = 'ZSA';
final String PROJ_B    = 'ZSB';
final String PLAN_CODE = 'ZSCLP';

final Date RUN_DATE = Date.today();

final String UNIT_BKG1 = PROJ_A + '-T01-F02-U002';   // residential, CP Horizon
final String UNIT_BKG2 = PROJ_B + '-B01-F01-S001';   // commercial,  CP Beacon
final String UNIT_BKG3 = PROJ_A + '-T01-F03-U004';   // residential, direct sale

// ===========================================================================
// PRE-FLIGHT — re-query the dependencies scripts 02/04 created
// ===========================================================================
Map<String, Booking__c> bookingByUnitName = new Map<String, Booking__c>();
for (Booking__c b : [
    SELECT Id, Name, Opportunity__c, Unit__c, Unit__r.Name, Primary_Buyer__c, Source_CP__c,
           Agreement_Value__c, Quoted_Gross_Value__c, Booking_Status__c, Payment_Plan__c
    FROM Booking__c
    WHERE Unit__r.Name IN (:UNIT_BKG1, :UNIT_BKG2, :UNIT_BKG3)
    ORDER BY Name
]) {
    bookingByUnitName.put(b.Unit__r.Name, b);
}
Booking__c bkg1 = bookingByUnitName.get(UNIT_BKG1);
Booking__c bkg2 = bookingByUnitName.get(UNIT_BKG2);
Booking__c bkg3 = bookingByUnitName.get(UNIT_BKG3);
if (bkg1 == null || bkg2 == null || bkg3 == null) {
    throw new IllegalArgumentException(
        'ABORT: expected 3 seed Bookings on units ' + UNIT_BKG1 + ' / ' + UNIT_BKG2 + ' / ' + UNIT_BKG3
        + ' but found ' + bookingByUnitName.size() + '. Commit script 04 '
        + '(seed-test-data-04-opportunities.apex) with DRY_RUN = false first.');
}
// Ordered, deterministic working list — every loop below iterates this.
List<Booking__c> bookings = new List<Booking__c>{ bkg1, bkg2, bkg3 };

List<Payment_Plan__c> planRows = [
    SELECT Id, Name, Active__c FROM Payment_Plan__c WHERE Plan_Code__c = :PLAN_CODE LIMIT 1
];
if (planRows.isEmpty()) {
    throw new IllegalArgumentException(
        'ABORT: Payment Plan ' + PLAN_CODE + ' not found. Commit script 02 first.');
}
Payment_Plan__c seedPlan = planRows[0];

Map<String, Contact> conByEmail = new Map<String, Contact>();
for (Contact c : [
    SELECT Id, Email FROM Contact WHERE Email LIKE '%.seed@recrm-demo.invalid'
]) {
    conByEmail.put(c.Email, c);
}
Contact conRajesh = conByEmail.get('rajesh.kulkarni.seed@recrm-demo.invalid');
Contact conAnjali = conByEmail.get('anjali.kulkarni.seed@recrm-demo.invalid');
Contact conPriya  = conByEmail.get('priya.shenoy.seed@recrm-demo.invalid');
Contact conDevang = conByEmail.get('devang.trivedi.seed@recrm-demo.invalid');
Contact conVikram = conByEmail.get('vikram.shah.seed@recrm-demo.invalid');
for (Contact c : new List<Contact>{ conRajesh, conAnjali, conPriya, conDevang, conVikram }) {
    if (c == null) {
        throw new IllegalArgumentException('ABORT: seed Contacts missing. Commit script 02 first.');
    }
}

if (bkg1.Payment_Plan__c != null) {
    throw new IllegalArgumentException(
        'ABORT: the seed Bookings already carry a Payment Plan — this script has already run. '
        + 'It is one-shot (it would double up Booking_Customer__c / Pricing_Component__c / Receipts). '
        + 'Delete the seed data and start from script 01 if you need to re-seed.');
}

Id rtBkgRes = Schema.SObjectType.Booking__c.getRecordTypeInfosByDeveloperName().get('Residential_Booking').getRecordTypeId();
Id rtBkgCom = Schema.SObjectType.Booking__c.getRecordTypeInfosByDeveloperName().get('Commercial_Booking').getRecordTypeId();

List<String> summaryOrder = new List<String>();
Map<String, Integer> counts = new Map<String, Integer>();
List<String> notes = new List<String>();

Savepoint sp = Database.setSavepoint();

System.debug(LoggingLevel.INFO, '=== SEED 05 BOOKINGS START (DRY_RUN=' + DRY_RUN + ') ===');

// ===========================================================================
// 0. Opportunistic Payment Plan activation retry (constraint (e), gotcha #40)
// ===========================================================================
Boolean planActive = seedPlan.Active__c;
if (!planActive) {
    try {
        update new Payment_Plan__c(Id = seedPlan.Id, Active__c = true);
        planActive = true;
    } catch (Exception e) {
        notes.add('Payment Plan "' + seedPlan.Name + '" still could not be activated (gotcha #40 — the '
            + 'Total_Pct_Check__c roll-up has not settled). Harmless: PaymentScheduleService filters on '
            + 'the milestones\' Active__c, not the plan\'s. Activate it manually in Setup later. '
            + 'Reason: ' + e.getMessage());
    }
}

// ===========================================================================
// 1. Enrich the Bookings and attach the Payment Plan.
//    Setting Payment_Plan__c is what fires PaymentScheduleService. See
//    constraint (a) in the header for why the reset below is retained.
// ===========================================================================
RecursionGuard.reset('Booking_afterUpdate');

List<Booking__c> bookingEnrichment = new List<Booking__c>();
for (Booking__c b : bookings) {
    Decimal gross = (b.Quoted_Gross_Value__c == null) ? 0 : b.Quoted_Gross_Value__c;
    Boolean isCommercial = (b.Id == bkg2.Id);
    bookingEnrichment.add(new Booking__c(
        Id = b.Id,
        RecordTypeId = isCommercial ? rtBkgCom : rtBkgRes,
        Payment_Plan__c = seedPlan.Id,                        // fires PaymentScheduleService
        GST_Amount__c = (gross * 0.05).setScale(2),           // feeds Total_Consideration formula
        Stamp_Duty__c = (gross * 0.06).setScale(2),
        Registration_Fees__c = 30000,
        Booking_Amount_Paid__c = 400000,
        Booking_Notes__c = TAG + ' booking created end-to-end by the seed-test-data series',
        Last_Action_Date__c = DateTime.now(),
        Escalation_Flag__c = false
    ));
}
update bookingEnrichment;
summaryOrder.add('Booking__c (enriched)');  counts.put('Booking__c (enriched)', bookingEnrichment.size());

// ===========================================================================
// 2. Booking_Customer__c — joint-buyer junction
// ===========================================================================
List<Booking_Customer__c> bookingCustomers = new List<Booking_Customer__c>{
    // Joint booking: Rajesh (60%) + Anjali (40%)
    new Booking_Customer__c(Booking__c = bkg1.Id, Contact__c = conRajesh.Id,
        Is_Primary__c = true,  Relationship__c = 'Self',   Ownership_Pct__c = 60,
        Payment_Share_Pct__c = 60, PAN_Verified__c = true),
    new Booking_Customer__c(Booking__c = bkg1.Id, Contact__c = conAnjali.Id,
        Is_Primary__c = false, Relationship__c = 'Spouse', Ownership_Pct__c = 40,
        Payment_Share_Pct__c = 40, PAN_Verified__c = true),
    new Booking_Customer__c(Booking__c = bkg2.Id, Contact__c = conVikram.Id,
        Is_Primary__c = true, Relationship__c = 'Self', Ownership_Pct__c = 100,
        Payment_Share_Pct__c = 100, PAN_Verified__c = true),
    new Booking_Customer__c(Booking__c = bkg3.Id, Contact__c = conPriya.Id,
        Is_Primary__c = true,  Relationship__c = 'Self',        Ownership_Pct__c = 70,
        Payment_Share_Pct__c = 70, PAN_Verified__c = true),
    new Booking_Customer__c(Booking__c = bkg3.Id, Contact__c = conDevang.Id,
        Is_Primary__c = false, Relationship__c = 'Co-Investor', Ownership_Pct__c = 30,
        Payment_Share_Pct__c = 30, PAN_Verified__c = false)
};
insert bookingCustomers;
summaryOrder.add('Booking_Customer__c');  counts.put('Booking_Customer__c', bookingCustomers.size());

// ===========================================================================
// 3. Pricing_Component__c — snapshotted per-Booking price build-up.
//    Line_Amount__c is a formula over Calculation_Basis__c / Rate__c /
//    Area_Basis__c / Base_Ref_Amount__c, so those four drive the maths.
// ===========================================================================
List<Pricing_Component__c> pricingComponents = new List<Pricing_Component__c>();
for (Booking__c b : bookings) {
    Decimal gross = (b.Quoted_Gross_Value__c == null) ? 0 : b.Quoted_Gross_Value__c;
    Integer sba = 1400;   // representative super-built-up area for the snapshot
    Decimal bspRate = (gross / sba).setScale(2);

    pricingComponents.add(new Pricing_Component__c(Booking__c = b.Id, Component_Code__c = 'BSP',
        Component_Name__c = 'Basic Sale Price', Calculation_Basis__c = 'Per sq ft',
        Rate__c = bspRate, Area_Basis__c = sba, GST_Applicable__c = true, GST_Rate__c = 5));
    pricingComponents.add(new Pricing_Component__c(Booking__c = b.Id, Component_Code__c = 'PLC_FLOOR',
        Component_Name__c = 'Floor Rise Charge', Calculation_Basis__c = 'Percentage of BSP+PLC',
        Rate__c = 3, Base_Ref_Amount__c = gross, GST_Applicable__c = true, GST_Rate__c = 5));
    pricingComponents.add(new Pricing_Component__c(Booking__c = b.Id, Component_Code__c = 'PLC_CORNER',
        Component_Name__c = 'Corner Unit Premium', Calculation_Basis__c = 'Percentage of BSP+PLC',
        Rate__c = 3, Base_Ref_Amount__c = gross, GST_Applicable__c = true, GST_Rate__c = 5));
    pricingComponents.add(new Pricing_Component__c(Booking__c = b.Id, Component_Code__c = 'EDC',
        Component_Name__c = 'External Development Charges', Calculation_Basis__c = 'Fixed',
        Rate__c = 185000, GST_Applicable__c = true, GST_Rate__c = 18));
    pricingComponents.add(new Pricing_Component__c(Booking__c = b.Id, Component_Code__c = 'IFMS',
        Component_Name__c = 'Interest Free Maintenance Security', Calculation_Basis__c = 'Fixed',
        Rate__c = 95000, GST_Applicable__c = false));
    pricingComponents.add(new Pricing_Component__c(Booking__c = b.Id, Component_Code__c = 'CLUB',
        Component_Name__c = 'Club Membership', Calculation_Basis__c = 'Fixed',
        Rate__c = 250000, GST_Applicable__c = true, GST_Rate__c = 18));
}
insert pricingComponents;
summaryOrder.add('Pricing_Component__c');  counts.put('Pricing_Component__c', pricingComponents.size());

// ===========================================================================
// 4. Booking_Payment_Schedule__c — created by PaymentScheduleService in block 1.
// ===========================================================================
List<Booking_Payment_Schedule__c> schedules = [
    SELECT Id, Booking__c, Sequence__c, Milestone_Trigger__c, Scheduled_Amount__c, Status__c
    FROM Booking_Payment_Schedule__c
    WHERE Booking__c IN :bookings
    ORDER BY Booking__c, Sequence__c
];
summaryOrder.add('Booking_Payment_Schedule__c');  counts.put('Booking_Payment_Schedule__c', schedules.size());
if (schedules.isEmpty()) {
    notes.add('No Booking_Payment_Schedule__c rows were instantiated. This is the classic symptom of the '
        + 'RecursionGuard "Booking_afterUpdate" key having been consumed before the Payment Plan update — '
        + 'see sequencing constraint (a) in this script header.');
}

// ===========================================================================
// 5. Demand__c — raised through DemandService (the real @InvocableMethod),
//    two milestones per Booking, in one bulk invocation.
// ===========================================================================
List<DemandService.DemandRequest> demandReqs = new List<DemandService.DemandRequest>();
for (Booking_Payment_Schedule__c s : schedules) {
    if (s.Status__c == 'Pending' && s.Sequence__c != null && s.Sequence__c <= 2) {
        DemandService.DemandRequest dr = new DemandService.DemandRequest();
        dr.paymentScheduleId = s.Id;
        demandReqs.add(dr);
    }
}
List<Id> demandIds = new List<Id>();
if (!demandReqs.isEmpty()) {
    demandIds = DemandService.raiseDemands(demandReqs);
}
summaryOrder.add('Demand__c');  counts.put('Demand__c', demandIds.size());

// ===========================================================================
// 6. Receipt__c + Receipt_Allocation__c — real payments against real Demands.
//    Amounts come from the Demand's Net_Payable__c formula so
//    ReceiptAllocationService's over-allocation guards are satisfied exactly.
// ===========================================================================
List<Demand__c> raisedDemands = demandIds.isEmpty()
    ? new List<Demand__c>()
    : [SELECT Id, Booking__c, Demand_Seq__c, Net_Payable__c
       FROM Demand__c WHERE Id IN :demandIds ORDER BY Booking__c, Demand_Seq__c];

// First demand per Booking gets paid in full; second gets a 40% part-payment.
Map<Id, Demand__c> firstDemandByBooking  = new Map<Id, Demand__c>();
Map<Id, Demand__c> secondDemandByBooking = new Map<Id, Demand__c>();
for (Demand__c d : raisedDemands) {
    if (!firstDemandByBooking.containsKey(d.Booking__c)) {
        firstDemandByBooking.put(d.Booking__c, d);
    } else if (!secondDemandByBooking.containsKey(d.Booking__c)) {
        secondDemandByBooking.put(d.Booking__c, d);
    }
}

List<Receipt__c> receipts = new List<Receipt__c>();
Map<Integer, Id> receiptIndexToDemand = new Map<Integer, Id>();
Map<Integer, Decimal> receiptIndexToAmount = new Map<Integer, Decimal>();
Map<Integer, String> receiptIndexToType = new Map<Integer, String>();
Map<Id, Decimal> paidSoFarByBooking = new Map<Id, Decimal>();
List<String> payModes = new List<String>{ 'NEFT', 'RTGS', 'IMPS' };
Integer idx = 0;

for (Booking__c b : bookings) {
    paidSoFarByBooking.put(b.Id, 0);
    Demand__c d1 = firstDemandByBooking.get(b.Id);
    if (d1 != null && d1.Net_Payable__c != null && d1.Net_Payable__c > 0) {
        Decimal amt = d1.Net_Payable__c.setScale(2);
        receipts.add(new Receipt__c(Booking__c = b.Id, Receipt_Date__c = RUN_DATE.addDays(-3),
            Amount__c = amt, Payment_Mode__c = payModes[Math.mod(idx, payModes.size())],
            Status__c = 'Received', Payer_Name__c = TAG + ' Primary Buyer',
            Payer_PAN__c = 'ABCPK1101A', Bank__c = 'HDFC Bank',
            Instrument_Reference__c = 'UTR' + TAG + String.valueOf(100001 + idx),
            Notes__c = TAG + ' — full settlement of milestone 1'));
        receiptIndexToDemand.put(idx, d1.Id);
        receiptIndexToAmount.put(idx, amt);
        receiptIndexToType.put(idx, 'Towards Demand');
        paidSoFarByBooking.put(b.Id, paidSoFarByBooking.get(b.Id) + amt);
        idx++;
    }
    Demand__c d2 = secondDemandByBooking.get(b.Id);
    if (d2 != null && d2.Net_Payable__c != null && d2.Net_Payable__c > 0) {
        Decimal amt = (d2.Net_Payable__c * 0.40).setScale(2);
        if (amt > 0) {
            receipts.add(new Receipt__c(Booking__c = b.Id, Receipt_Date__c = RUN_DATE.addDays(-1),
                Amount__c = amt, Payment_Mode__c = 'Cheque', Status__c = 'Received',
                Payer_Name__c = TAG + ' Primary Buyer', Payer_PAN__c = 'ABCPK1101A',
                Bank__c = 'ICICI Bank',
                Instrument_Reference__c = 'CHQ' + TAG + String.valueOf(500001 + idx),
                Notes__c = TAG + ' — part payment against milestone 2'));
            receiptIndexToDemand.put(idx, d2.Id);
            receiptIndexToAmount.put(idx, amt);
            receiptIndexToType.put(idx, 'Towards Demand');
            paidSoFarByBooking.put(b.Id, paidSoFarByBooking.get(b.Id) + amt);
            idx++;
        }
    }

    // Booking 1 is the one carried through to Possession in script 06.
    // Possession__c.All_Dues_Cleared__c is a formula over Booking__r.Total_Outstanding__c,
    // so settle the balance with an ADVANCE receipt (Demand Id = null) — which also
    // exercises ReceiptAllocationService's advance-payment branch, the only path where
    // Receipt_Allocation__c.Demand__c is blank.
    if (b.Id == bkg1.Id) {
        Decimal gross = (b.Quoted_Gross_Value__c == null) ? 0 : b.Quoted_Gross_Value__c;
        Decimal totalConsideration = gross + (gross * 0.05).setScale(2);   // matches block 1
        Decimal balance = (totalConsideration - paidSoFarByBooking.get(b.Id)).setScale(2);
        if (balance > 0) {
            receipts.add(new Receipt__c(Booking__c = b.Id, Receipt_Date__c = RUN_DATE,
                Amount__c = balance, Payment_Mode__c = 'RTGS', Status__c = 'Received',
                Payer_Name__c = TAG + ' Primary Buyer', Payer_PAN__c = 'ABCPK1101A',
                Bank__c = 'HDFC Bank',
                Instrument_Reference__c = 'UTR' + TAG + String.valueOf(900001 + idx),
                Notes__c = TAG + ' — balance settlement ahead of possession (booked as advance)'));
            receiptIndexToDemand.put(idx, null);
            receiptIndexToAmount.put(idx, balance);
            receiptIndexToType.put(idx, 'Advance');
            paidSoFarByBooking.put(b.Id, paidSoFarByBooking.get(b.Id) + balance);
            idx++;
        }
    }
}
if (!receipts.isEmpty()) insert receipts;
summaryOrder.add('Receipt__c');  counts.put('Receipt__c', receipts.size());

List<ReceiptAllocationService.AllocationRequest> allocReqs =
    new List<ReceiptAllocationService.AllocationRequest>();
for (Integer i = 0; i < receipts.size(); i++) {
    ReceiptAllocationService.AllocationRequest ar = new ReceiptAllocationService.AllocationRequest();
    ar.receiptId = receipts[i].Id;
    ar.demandId = receiptIndexToDemand.get(i);
    ar.amount = receiptIndexToAmount.get(i);
    ar.allocationType = receiptIndexToType.get(i);
    allocReqs.add(ar);
}
List<Id> allocationIds = new List<Id>();
if (!allocReqs.isEmpty()) {
    allocationIds = ReceiptAllocationService.allocateReceipts(allocReqs);
}
summaryOrder.add('Receipt_Allocation__c');  counts.put('Receipt_Allocation__c', allocationIds.size());

// ===========================================================================
// SUMMARY — computed BEFORE any rollback, since a rollback invalidates Ids.
// ===========================================================================
Integer totalRecords = 0;
for (String k : summaryOrder) {
    if (k != 'Booking__c (enriched)') totalRecords += counts.get(k);
}

System.debug(LoggingLevel.INFO, '');
System.debug(LoggingLevel.INFO, '========== SEED 05 BOOKINGS SUMMARY ===========');
System.debug(LoggingLevel.INFO, 'Mode: ' + (DRY_RUN ? 'DRY RUN (everything rolled back)' : 'COMMITTED'));
for (String k : summaryOrder) {
    System.debug(LoggingLevel.INFO, '  ' + k.rightPad(34, ' ') + ' : ' + counts.get(k));
}
System.debug(LoggingLevel.INFO, '  TOTAL NEW RECORDS'.rightPad(36, ' ') + ' : ' + totalRecords);
System.debug(LoggingLevel.INFO, '  Payment Plan active                  : ' + planActive);
System.debug(LoggingLevel.INFO, 'Governor usage: SOQL ' + Limits.getQueries() + '/' + Limits.getLimitQueries()
    + '  |  DML statements ' + Limits.getDmlStatements() + '/' + Limits.getLimitDmlStatements()
    + '  |  DML rows ' + Limits.getDmlRows() + '/' + Limits.getLimitDmlRows()
    + '  |  CPU ' + Limits.getCpuTime() + 'ms/' + Limits.getLimitCpuTime() + 'ms');
if (notes.isEmpty()) {
    System.debug(LoggingLevel.INFO, 'No warnings.');
} else {
    System.debug(LoggingLevel.WARN, notes.size() + ' warning(s):');
    for (String n : notes) System.debug(LoggingLevel.WARN, '  ! ' + n);
}
System.debug(LoggingLevel.INFO, '-----------------------------------------------');
for (Booking__c b : [
    SELECT Name, Booking_Status__c, Agreement_Value__c, Total_Paid__c, Total_Outstanding__c,
           Source_CP__r.Name, Unit__r.Name, Unit__r.Unit_Status__c
    FROM Booking__c WHERE Id IN :bookings ORDER BY Name
]) {
    System.debug(LoggingLevel.INFO, 'BOOKING ' + b.Name
        + ' | status=' + b.Booking_Status__c
        + ' | unit=' + b.Unit__r.Name + ' (' + b.Unit__r.Unit_Status__c + ')'
        + ' | CP=' + (b.Source_CP__c == null ? 'direct' : b.Source_CP__r.Name)
        + ' | agreementValue=' + b.Agreement_Value__c
        + ' | paid=' + b.Total_Paid__c
        + ' | outstanding=' + b.Total_Outstanding__c);
}
System.debug(LoggingLevel.INFO, '===============================================');

// ===========================================================================
// ROLLBACK (dry run only)
// ===========================================================================
if (DRY_RUN) {
    Database.rollback(sp);
    System.debug(LoggingLevel.INFO,
        'DRY RUN COMPLETE — enrichment, schedules, demands, receipts and allocations all executed and '
        + 'passed validation, then were rolled back. Set DRY_RUN = false and re-run to commit, THEN '
        + 'move on to scripts/seed-test-data-06-agreements-possession.apex.');
} else {
    System.debug(LoggingLevel.INFO,
        'SEED 05 COMMITTED. Next: scripts/seed-test-data-06-agreements-possession.apex.');
}
