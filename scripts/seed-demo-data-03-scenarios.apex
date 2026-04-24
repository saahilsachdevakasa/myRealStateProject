/**
 * Demo Data Seed — Part 3: Five Scenarios
 *
 * Depends on Parts 1 (inventory) and 2 (customers) having run.
 *
 * Exercises every service via the real trigger chain:
 *   - UnitBlockingService (E07)
 *   - BookingService via OpportunityTrigger close-won (E08)
 *   - PaymentScheduleService via BookingTrigger (E09)
 *   - DemandService invocable (E10)
 *   - ReceiptAllocationService invocable (E11)
 *   - AgreementService create + after-update sync (E12)
 *   - PossessionService create + after-update sync (E13)
 *
 * Five scenarios:
 *   S1 — Happy Path: Rajesh → U001 → fully Possessed
 *   S2 — Mid-lifecycle: Priya → U002 → partial receipt, still Agreement Pending
 *   S3 — Lost Opp: anonymous buyer → Closed Lost
 *   S4 — Blocked Unit: Vikram → U003 → unit Blocked, opp at Negotiation
 *   S5 — Commercial: Vikram → S001 → early-stage commercial Booking
 *
 * Idempotent: wipes existing Opps/Leads/SiteVisits that reference PRK/GAL
 * inventory or the seed accounts. Bookings and their MD children cascade
 * from the inventory wipe; re-runs of this script alone also clean up.
 *
 * Run: sf apex run --file scripts/seed-demo-data-03-scenarios.apex --target-org re-crm-sdo
 */

System.debug('=== STARTING SCENARIOS SEED ===');

// Bypass duplicate rules on seed inserts (demo data is known-synthetic).
Database.DMLOptions dmlOpts = new Database.DMLOptions();
dmlOpts.DuplicateRuleHeader.AllowSave = true;

// ========================================================================
// PRECONDITIONS — verify inventory and customer seeds ran
// ========================================================================

Project__c prk = [SELECT Id, Project_Code__c FROM Project__c WHERE Project_Code__c = 'PRK' LIMIT 1];
Project__c gal = [SELECT Id, Project_Code__c FROM Project__c WHERE Project_Code__c = 'GAL' LIMIT 1];

Map<String, Unit__c> unitByName = new Map<String, Unit__c>();
for (Unit__c u : [
    SELECT Id, Name, Unit_Status__c
    FROM Unit__c
    WHERE Name IN ('PRK-T01-F01-U001', 'PRK-T01-F01-U002', 'PRK-T01-F01-U003', 'PRK-T01-F01-U004', 'GAL-B01-F01-S001')
]) {
    unitByName.put(u.Name, u);
}
if (unitByName.size() != 5) {
    throw new System.IllegalArgumentException('Expected 5 inventory units, found ' + unitByName.size() + '. Run seed-demo-data-01-inventory.apex first.');
}

Account rajesh = [SELECT Id FROM Account WHERE PAN__c = 'ABCPK1234A' LIMIT 1];
Account priya = [SELECT Id FROM Account WHERE PAN__c = 'ABCPS5678B' LIMIT 1];
Account vikram = [SELECT Id FROM Account WHERE PAN__c = 'AABCV9876D' LIMIT 1];

Payment_Plan__c clp;
Payment_Plan__c dlp;
Payment_Plan__c plp;
try {
    clp = [SELECT Id, Active__c FROM Payment_Plan__c WHERE Plan_Code__c = 'CLP' LIMIT 1];
    dlp = [SELECT Id, Active__c FROM Payment_Plan__c WHERE Plan_Code__c = 'DLP' LIMIT 1];
    plp = [SELECT Id, Active__c FROM Payment_Plan__c WHERE Plan_Code__c = 'PLP' LIMIT 1];
} catch (QueryException e) {
    throw new System.IllegalArgumentException('Payment plans CLP/DLP/PLP missing. Run scripts/seed-payment-plans.apex first.');
}
System.debug('Preconditions OK. Plans: CLP=' + clp.Id + ', DLP=' + dlp.Id + ', PLP=' + plp.Id);

// ========================================================================
// CLEANUP — wipe Opps/Leads/Site Visits from prior runs
// ========================================================================

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');

List<Opportunity> oldOpps = [
    SELECT Id FROM Opportunity
    WHERE Project__c = :prk.Id OR Project__c = :gal.Id
    OR AccountId IN (:rajesh.Id, :priya.Id, :vikram.Id)
];
Set<Id> oldOppIds = new Map<Id, Opportunity>(oldOpps).keySet();
List<Booking__c> oldBookings = oldOppIds.isEmpty()
    ? new List<Booking__c>()
    : [SELECT Id FROM Booking__c WHERE Opportunity__c IN :oldOppIds];

List<Lead> oldLeads = [
    SELECT Id FROM Lead
    WHERE Project_Interest__c = :prk.Id OR Project_Interest__c = :gal.Id
];
List<Account> oldLostAccounts = [SELECT Id FROM Account WHERE Name = 'Lost Prospect (Demo)'];

if (!oldBookings.isEmpty()) {
    System.debug('Wiping ' + oldBookings.size() + ' prior bookings (cascades to demands/receipts/agreements/possessions)');
    delete oldBookings;
}
if (!oldOpps.isEmpty()) { System.debug('Wiping ' + oldOpps.size() + ' prior opps'); delete oldOpps; }
if (!oldLeads.isEmpty()) { System.debug('Wiping ' + oldLeads.size() + ' prior leads'); delete oldLeads; }
if (!oldLostAccounts.isEmpty()) { delete oldLostAccounts; }

// Reset any units we'll use back to Available (in case a prior run left them Blocked/Booked).
// State machine (UnitLifecycleService): Available→Blocked; Blocked→Available/Booked;
// Booked→Cancelled; Cancelled→Available. So Booked needs two hops via Cancelled.
Map<String, List<Unit__c>> unitsByCurrent = new Map<String, List<Unit__c>>();
for (Unit__c u : unitByName.values()) {
    if (u.Unit_Status__c == 'Available') continue;
    if (!unitsByCurrent.containsKey(u.Unit_Status__c)) {
        unitsByCurrent.put(u.Unit_Status__c, new List<Unit__c>());
    }
    unitsByCurrent.get(u.Unit_Status__c).add(u);
}
List<Unit__c> bookedHop1 = new List<Unit__c>();
if (unitsByCurrent.containsKey('Booked')) {
    for (Unit__c u : unitsByCurrent.get('Booked')) {
        bookedHop1.add(new Unit__c(Id = u.Id, Unit_Status__c = 'Cancelled'));
    }
    System.debug('Hop 1: moving ' + bookedHop1.size() + ' Booked units to Cancelled');
    update bookedHop1;
}
List<Unit__c> unitsToAvailable = new List<Unit__c>();
for (Unit__c u : unitByName.values()) {
    if (u.Unit_Status__c != 'Available') {
        unitsToAvailable.add(new Unit__c(Id = u.Id, Unit_Status__c = 'Available', Blocked_By__c = null, Blocked_Until__c = null));
    }
}
if (!unitsToAvailable.isEmpty()) {
    System.debug('Hop 2: moving ' + unitsToAvailable.size() + ' units to Available');
    update unitsToAvailable;
}

// ========================================================================
// RECORD TYPE LOOKUPS
// ========================================================================

Id resOppRt = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Pre_sales_Residential').getRecordTypeId();
Id comOppRt = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Pre_sales_Commercial').getRecordTypeId();
Id buyerRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Buyer').getRecordTypeId();

// ========================================================================
// SCENARIO 1 — HAPPY PATH (Rajesh → U001 → Possessed)
// ========================================================================

System.debug('\n=== SCENARIO 1: Happy Path (Rajesh → PRK-T01-F01-U001 → Possessed) ===');

// --- Lead (parallel artefact, not converted — advances past New to demonstrate assignment) ---
Lead rajeshLead = new Lead(
    FirstName = 'Rajesh',
    LastName = 'Kumar',
    Company = 'Individual',
    Phone = '+91 98200 10001',
    Email = 'rajesh.kumar+demo@example.in',
    Status = 'Qualified',
    Source_Channel__c = 'Digital',
    Project_Interest__c = prk.Id,
    Budget_Min__c = 20000000,
    Budget_Max__c = 35000000,
    Unit_Type_Preference__c = '3BHK',
    Urgency__c = 'Immediate'
);
Database.insert(rajeshLead, dmlOpts);
System.debug('S1 Lead: ' + rajeshLead.Id);

// --- Opportunity at New (no Project required yet) ---
Opportunity rajeshOpp = new Opportunity(
    Name = 'Rajesh Kumar - PRK 3BHK',
    RecordTypeId = resOppRt,
    StageName = 'New',
    CloseDate = Date.today().addMonths(1),
    AccountId = rajesh.Id,
    Source_Channel__c = 'Digital'
);
insert rajeshOpp;
System.debug('S1 Opp (New): ' + rajeshOpp.Id);

// --- Advance to Negotiation with Project + Primary_Unit (VRs fire on stage change) ---
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Opportunity(
    Id = rajeshOpp.Id,
    StageName = 'Negotiation',
    Project__c = prk.Id,
    Primary_Unit__c = unitByName.get('PRK-T01-F01-U001').Id
);

// --- Site Visit (backdated 3 days) ---
Site_Visit__c sv1 = new Site_Visit__c(
    Project__c = prk.Id,
    Opportunity__c = rajeshOpp.Id,
    Scheduled_DateTime__c = Datetime.now().addDays(-3),
    Actual_DateTime__c = Datetime.now().addDays(-3),
    Status__c = 'Done',
    Outcome__c = 'Interested-Hot',
    Conducted_By__c = UserInfo.getUserId(),
    Primary_Unit__c = unitByName.get('PRK-T01-F01-U001').Id,
    Buyer_Feedback__c = 'Very interested in U001. Liked the east-facing view and the proximity to the sea.',
    Next_Action__c = 'Send pricing sheet and token form'
);
insert sv1;
System.debug('S1 Site Visit: ' + sv1.Id);

// --- Block U001 ---
UnitBlockingService.BlockRequest blk1 = new UnitBlockingService.BlockRequest();
blk1.unitId = unitByName.get('PRK-T01-F01-U001').Id;
blk1.durationHours = 168;
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
UnitBlockingService.blockUnit(new List<UnitBlockingService.BlockRequest>{ blk1 });
System.debug('S1 U001 blocked for 7 days');

// --- Close Won: set all financials + stage in one DML → triggers BookingService ---
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Opportunity(
    Id = rajeshOpp.Id,
    StageName = 'Closed Won (Booked)',
    EOI_Amount__c = 500000,
    Token_Amount__c = 2000000,
    Quoted_Gross_Value__c = 27000000   // 1800 SBA × 15000 BSP = 2.7 Cr
);

Opportunity refreshedOpp1 = [SELECT Booking__c FROM Opportunity WHERE Id = :rajeshOpp.Id];
Id rajeshBookingId = refreshedOpp1.Booking__c;
Booking__c rajeshBooking = [SELECT Id, Name, Booking_Status__c FROM Booking__c WHERE Id = :rajeshBookingId];
System.debug('S1 Booking created: ' + rajeshBooking.Name + ' (status=' + rajeshBooking.Booking_Status__c + ')');

// --- Assign Payment Plan (CLP) → triggers PaymentScheduleService → 10 schedule rows ---
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Booking__c(Id = rajeshBookingId, Payment_Plan__c = clp.Id);

List<Booking_Payment_Schedule__c> rajeshSchedules = [
    SELECT Id, Sequence__c, Scheduled_Amount__c
    FROM Booking_Payment_Schedule__c
    WHERE Booking__c = :rajeshBookingId
    ORDER BY Sequence__c
];
System.debug('S1 Payment Plan attached: ' + rajeshSchedules.size() + ' schedule rows');

// --- Raise Demands for Schedule 1 + 2 ---
List<DemandService.DemandRequest> demandReqs = new List<DemandService.DemandRequest>();
for (Integer i = 0; i < 2 && i < rajeshSchedules.size(); i++) {
    DemandService.DemandRequest dr = new DemandService.DemandRequest();
    dr.paymentScheduleId = rajeshSchedules[i].Id;
    demandReqs.add(dr);
}
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
List<Id> rajeshDemandIds = DemandService.raiseDemands(demandReqs);
System.debug('S1 Raised ' + rajeshDemandIds.size() + ' demands');

Demand__c demand1 = [
    SELECT Id, Name, Principal_Amount__c, GST_Amount__c, TDS_Amount__c, Net_Payable__c
    FROM Demand__c WHERE Id = :rajeshDemandIds[0]
];

// --- Receipt for full Demand 1 (NEFT) ---
Receipt__c r1 = new Receipt__c(
    Booking__c = rajeshBookingId,
    Receipt_Date__c = Date.today(),
    Amount__c = demand1.Net_Payable__c,
    Payment_Mode__c = 'NEFT',
    Instrument_Reference__c = 'UTR20260401001234',
    Bank__c = 'HDFC Bank',
    Payer_Name__c = 'Rajesh Kumar',
    Payer_PAN__c = 'ABCPK1234A',
    Status__c = 'Received'
);
insert r1;

ReceiptAllocationService.AllocationRequest ar1 = new ReceiptAllocationService.AllocationRequest();
ar1.receiptId = r1.Id;
ar1.demandId = demand1.Id;
ar1.amount = demand1.Net_Payable__c;
ar1.allocationType = 'Towards Demand';
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
ReceiptAllocationService.allocateReceipts(new List<ReceiptAllocationService.AllocationRequest>{ ar1 });
System.debug('S1 Receipt ' + r1.Id + ' fully allocated → Demand 1 Paid');

// --- Agreement: create, advance to Signed, then Executed ---
AgreementService.AgreementRequest agrReq = new AgreementService.AgreementRequest();
agrReq.bookingId = rajeshBookingId;
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
List<Id> agrIds = AgreementService.createAgreements(new List<AgreementService.AgreementRequest>{ agrReq });
Id rajeshAgreementId = agrIds[0];
System.debug('S1 Agreement created: ' + rajeshAgreementId + ' (Booking → Agreement Pending)');

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Agreement__c(
    Id = rajeshAgreementId,
    Status__c = 'Signed',
    Signed_Date__c = Date.today().addDays(-5)
);
System.debug('S1 Agreement Signed (Booking → Agreement Signed)');

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Agreement__c(
    Id = rajeshAgreementId,
    Status__c = 'Executed',
    Registration_Date__c = Date.today().addDays(-2),
    Registration_Number__c = 'BOM/2026/00456',
    Sub_Registrar__c = 'Worli - Mumbai'
);
System.debug('S1 Agreement Executed (Booking → Registered)');

// --- Possession: create, move through statuses, Hand Over ---
PossessionService.PossessionRequest posReq = new PossessionService.PossessionRequest();
posReq.bookingId = rajeshBookingId;
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
List<Id> posIds = PossessionService.createPossessions(new List<PossessionService.PossessionRequest>{ posReq });
Id rajeshPossessionId = posIds[0];
System.debug('S1 Possession created: ' + rajeshPossessionId + ' (Booking → Possession Ready)');

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Possession__c(
    Id = rajeshPossessionId,
    Status__c = 'Offered',
    Offered_Date__c = Date.today().addDays(-1)
);

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Possession__c(
    Id = rajeshPossessionId,
    Status__c = 'Snag Phase',
    Snag_Inspection_Date__c = Date.today()
);

// --- Snag items (direct insert — no service, native rollups handle counts) ---
insert new List<Snag_Item__c>{
    new Snag_Item__c(
        Possession__c = rajeshPossessionId,
        Description__c = 'Bathroom tap leaking in master bedroom',
        Category__c = 'Plumbing',
        Severity__c = 'Minor',
        Status__c = 'Resolved',
        Reported_Date__c = Date.today(),
        Resolved_Date__c = Date.today()
    ),
    new Snag_Item__c(
        Possession__c = rajeshPossessionId,
        Description__c = 'Wall paint chipping near the window in second bedroom',
        Category__c = 'Paint',
        Severity__c = 'Minor',
        Status__c = 'Open',
        Reported_Date__c = Date.today()
    )
};
System.debug('S1 2 snag items recorded');

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Possession__c(
    Id = rajeshPossessionId,
    Status__c = 'Handed Over',
    Keys_Handed_Date__c = Date.today(),
    Handed_Over_By__c = UserInfo.getUserId(),
    NOC_Issued__c = true,
    NOC_Date__c = Date.today()
);
System.debug('S1 Possession Handed Over (Booking → Possessed) ✓');

// ========================================================================
// SCENARIO 2 — MID-LIFECYCLE (Priya → U002 → Partial Receipt)
// ========================================================================

System.debug('\n=== SCENARIO 2: Mid-Lifecycle (Priya → PRK-T01-F01-U002 → Partial) ===');

Opportunity priyaOpp = new Opportunity(
    Name = 'Priya Sharma - PRK 2BHK',
    RecordTypeId = resOppRt,
    StageName = 'New',
    CloseDate = Date.today().addMonths(1),
    AccountId = priya.Id,
    Source_Channel__c = 'Referral'
);
insert priyaOpp;

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Opportunity(
    Id = priyaOpp.Id,
    StageName = 'Negotiation',
    Project__c = prk.Id,
    Primary_Unit__c = unitByName.get('PRK-T01-F01-U002').Id
);

UnitBlockingService.BlockRequest blk2 = new UnitBlockingService.BlockRequest();
blk2.unitId = unitByName.get('PRK-T01-F01-U002').Id;
blk2.durationHours = 168;
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
UnitBlockingService.blockUnit(new List<UnitBlockingService.BlockRequest>{ blk2 });

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Opportunity(
    Id = priyaOpp.Id,
    StageName = 'Closed Won (Booked)',
    EOI_Amount__c = 300000,
    Token_Amount__c = 1500000,
    Quoted_Gross_Value__c = 17850000   // 1275 SBA × 14000 BSP = 1.785 Cr
);

Opportunity refreshedOpp2 = [SELECT Booking__c FROM Opportunity WHERE Id = :priyaOpp.Id];
Id priyaBookingId = refreshedOpp2.Booking__c;
Booking__c priyaBooking = [SELECT Id, Name FROM Booking__c WHERE Id = :priyaBookingId];
System.debug('S2 Booking: ' + priyaBooking.Name);

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Booking__c(Id = priyaBookingId, Payment_Plan__c = dlp.Id);

List<Booking_Payment_Schedule__c> priyaSchedules = [
    SELECT Id FROM Booking_Payment_Schedule__c
    WHERE Booking__c = :priyaBookingId ORDER BY Sequence__c LIMIT 1
];

DemandService.DemandRequest dr2 = new DemandService.DemandRequest();
dr2.paymentScheduleId = priyaSchedules[0].Id;
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
List<Id> priyaDemandIds = DemandService.raiseDemands(new List<DemandService.DemandRequest>{ dr2 });

Demand__c priyaDemand = [
    SELECT Id, Net_Payable__c FROM Demand__c WHERE Id = :priyaDemandIds[0]
];
Decimal halfAmount = (priyaDemand.Net_Payable__c / 2).setScale(2);

Receipt__c r2 = new Receipt__c(
    Booking__c = priyaBookingId,
    Receipt_Date__c = Date.today(),
    Amount__c = halfAmount,
    Payment_Mode__c = 'RTGS',
    Instrument_Reference__c = 'UTR20260415005678',
    Bank__c = 'ICICI Bank',
    Payer_Name__c = 'Priya Sharma',
    Payer_PAN__c = 'ABCPS5678B',
    Status__c = 'Received'
);
insert r2;

ReceiptAllocationService.AllocationRequest ar2 = new ReceiptAllocationService.AllocationRequest();
ar2.receiptId = r2.Id;
ar2.demandId = priyaDemand.Id;
ar2.amount = halfAmount;
ar2.allocationType = 'Towards Demand';
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
ReceiptAllocationService.allocateReceipts(new List<ReceiptAllocationService.AllocationRequest>{ ar2 });
System.debug('S2 Partial receipt ' + halfAmount + ' allocated → Demand Partial ✓');

// ========================================================================
// SCENARIO 3 — LOST OPPORTUNITY
// ========================================================================

System.debug('\n=== SCENARIO 3: Lost Opportunity ===');

Account lostAcc = new Account(
    Name = 'Lost Prospect (Demo)',
    RecordTypeId = buyerRt,
    Phone = '+91 98200 10099',
    Buyer_Type__c = 'Self-Use',
    KYC_Status__c = 'Pending'
);
insert lostAcc;

Opportunity lostOpp = new Opportunity(
    Name = 'Lost Prospect - PRK',
    RecordTypeId = resOppRt,
    StageName = 'New',
    CloseDate = Date.today().addMonths(1),
    AccountId = lostAcc.Id,
    Source_Channel__c = 'Aggregator-99acres'
);
insert lostOpp;

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Opportunity(
    Id = lostOpp.Id,
    StageName = 'Negotiation',
    Project__c = prk.Id,
    Primary_Unit__c = unitByName.get('PRK-T01-F01-U004').Id
);

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Opportunity(
    Id = lostOpp.Id,
    StageName = 'Closed Lost',
    Close_Reason_Lost__c = 'Price',
    Description = 'Buyer found our pricing ~8% higher than a comparable unit at a competing project; went with competitor.'
);
System.debug('S3 Opp closed lost (Price) ✓');

// ========================================================================
// SCENARIO 4 — BLOCKED UNIT (in-flight negotiation, Vikram → U003)
// ========================================================================

System.debug('\n=== SCENARIO 4: Blocked Unit (Vikram → PRK-T01-F01-U003) ===');

Opportunity vikramResOpp = new Opportunity(
    Name = 'Vikram Enterprises - PRK 3BHK',
    RecordTypeId = resOppRt,
    StageName = 'New',
    CloseDate = Date.today().addMonths(2),
    AccountId = vikram.Id,
    Source_Channel__c = 'CP'
);
insert vikramResOpp;

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Opportunity(
    Id = vikramResOpp.Id,
    StageName = 'Negotiation',
    Project__c = prk.Id,
    Primary_Unit__c = unitByName.get('PRK-T01-F01-U003').Id,
    EOI_Amount__c = 500000
);

UnitBlockingService.BlockRequest blk4 = new UnitBlockingService.BlockRequest();
blk4.unitId = unitByName.get('PRK-T01-F01-U003').Id;
blk4.durationHours = 72;
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
UnitBlockingService.blockUnit(new List<UnitBlockingService.BlockRequest>{ blk4 });
System.debug('S4 U003 Blocked for 72h, Opp at Negotiation ✓');

// ========================================================================
// SCENARIO 5 — COMMERCIAL BOOKING (Vikram → S001 → Early Booking)
// ========================================================================

System.debug('\n=== SCENARIO 5: Commercial Booking (Vikram → GAL-B01-F01-S001) ===');

Opportunity galOpp = new Opportunity(
    Name = 'Vikram Enterprises - GAL Shop',
    RecordTypeId = comOppRt,
    StageName = 'New',
    CloseDate = Date.today().addMonths(1),
    AccountId = vikram.Id,
    Source_Channel__c = 'Walk-in'
);
insert galOpp;

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Opportunity(
    Id = galOpp.Id,
    StageName = 'Negotiation',
    Project__c = gal.Id,
    Primary_Unit__c = unitByName.get('GAL-B01-F01-S001').Id
);

UnitBlockingService.BlockRequest blk5 = new UnitBlockingService.BlockRequest();
blk5.unitId = unitByName.get('GAL-B01-F01-S001').Id;
blk5.durationHours = 168;
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
UnitBlockingService.blockUnit(new List<UnitBlockingService.BlockRequest>{ blk5 });

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Opportunity(
    Id = galOpp.Id,
    StageName = 'Closed Won (Booked)',
    EOI_Amount__c = 750000,
    Token_Amount__c = 3000000,
    Quoted_Gross_Value__c = 22500000   // 750 SBA × 30000 BSP = 2.25 Cr
);

Opportunity refreshedOpp5 = [SELECT Booking__c FROM Opportunity WHERE Id = :galOpp.Id];
Id galBookingId = refreshedOpp5.Booking__c;
Booking__c galBooking = [SELECT Id, Name FROM Booking__c WHERE Id = :galBookingId];
System.debug('S5 Commercial Booking: ' + galBooking.Name);

RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
update new Booking__c(Id = galBookingId, Payment_Plan__c = plp.Id);

List<Booking_Payment_Schedule__c> galSchedules = [
    SELECT Id FROM Booking_Payment_Schedule__c
    WHERE Booking__c = :galBookingId ORDER BY Sequence__c LIMIT 1
];

DemandService.DemandRequest dr5 = new DemandService.DemandRequest();
dr5.paymentScheduleId = galSchedules[0].Id;
RecursionGuard.reset('Opportunity_afterUpdate'); RecursionGuard.reset('Booking_afterUpdate'); RecursionGuard.reset('Agreement_afterUpdate'); RecursionGuard.reset('Possession_afterUpdate');
DemandService.raiseDemands(new List<DemandService.DemandRequest>{ dr5 });
System.debug('S5 First demand raised on commercial booking ✓');

// ========================================================================
// SUMMARY
// ========================================================================

System.debug('\n=== ALL SCENARIOS SEEDED ===');
System.debug('S1 Happy Path:  Booking=' + rajeshBooking.Name + ' → Possessed');
System.debug('S2 Partial:     Booking=' + priyaBooking.Name + ' → Agreement Pending / Demand Partial');
System.debug('S3 Lost:        Opp closed lost (Price)');
System.debug('S4 Blocked:     Vikram → U003 Blocked, Opp at Negotiation');
System.debug('S5 Commercial:  Booking=' + galBooking.Name + ' → Confirmed with 1 Demand');
