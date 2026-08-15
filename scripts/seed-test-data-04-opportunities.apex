/**
 * ============================================================================
 * seed-test-data-04-opportunities.apex — SCRIPT 4 OF 7
 * ============================================================================
 *
 * DEPENDS ON: scripts 01, 02 and 03 having been COMMITTED (DRY_RUN = false).
 *   Re-queried at the top of this file:
 *     Project__c — by Project_Code__c IN ('ZSA','ZSB')
 *     Unit__c    — all 48 seed units, mapped by Name
 *     Account    — CP + Buyer/Corporate, by their 'SEED ...' Names
 *     Lead       — leadGaurav / leadKavya, by their fixed Email values
 *                  (needed by the Site Visit block at the end)
 *
 * PRODUCES (re-queryable by later scripts):
 *   Opportunity x9 — identified downstream by Primary_Unit__r.Name. Opportunity
 *                    Name is NOT a usable key (the naming automation makes them
 *                    uniform), so every Opportunity a later script needs carries
 *                    a distinct Primary Unit.
 *   Booking__c x3  — created by BookingService via the Closed Won transition,
 *                    NEVER inserted directly. Identified downstream by
 *                    Unit__r.Name (Booking Name is an AutoNumber sequence):
 *                      bkg1 ZSA-T01-F02-U002  residential, CP Horizon (Platinum)
 *                      bkg2 ZSB-B01-F01-S001  commercial,  CP Beacon (no GSTIN)
 *                      bkg3 ZSA-T01-F03-U004  residential, direct sale
 *   Site_Visit__c x4
 *
 * HOW TO RUN
 *   sf apex run --file scripts/seed-test-data-04-opportunities.apex --target-org re-crm-sdo
 *   Dry-run first (DRY_RUN = true), then commit, THEN run script 05.
 *
 * AUTOMATION THIS SCRIPT DELIBERATELY DRIVES
 *   - Opportunity -> Closed Won (Booked) fires OpportunityTrigger ->
 *     BookingService.onOpportunityClosedWon, which creates the Booking__c records,
 *     names them BKG-{PROJ}-{YY}-{nnnn}, flips Unit Blocked->Booked and round-trips
 *     Opportunity.Booking__c. Bookings are NEVER inserted directly here.
 *   - Booking AFTER_INSERT fires CommissionService.accrueOnBooking.
 *
 * SEQUENCING CONSTRAINTS HONOURED IN THIS FILE
 *   (a) RecursionGuard is TRANSACTION-scoped and starts CLEAN in this script's own
 *       transaction (script 03's conversion-time Opportunity update happened in a
 *       different transaction). But this file issues TWO Opportunity update
 *       statements, and each needs OpportunityTrigger's after-update handler to
 *       fire, so RecursionGuard.reset('Opportunity_afterUpdate') is called before
 *       EACH. The first is belt-and-braces (nothing has consumed the key yet);
 *       the SECOND is load-bearing — remove it and the third Booking silently
 *       never gets created.
 *   (b) Booking__c.Unit_Must_Be_Blocked_At_Booking requires Unit_Status__c =
 *       'Blocked' at Booking insert. Units are blocked via UnitBlockingService
 *       BEFORE the Opportunity stage update that creates the Bookings — and,
 *       critically, in the SAME transaction, so a stale block from an earlier
 *       aborted run can't leave them in the wrong state.
 *   (c) Booking__c.Source_CP_Must_Be_Active requires the Source CP Account to be
 *       CP_Status__c = 'Active' at insert. Script 02 activated Horizon and Beacon;
 *       re-verified in the pre-flight below.
 *   (d) The four Opportunity validation rules are all ISCHANGED(StageName)-scoped,
 *       so they do NOT fire on insert. To genuinely exercise them, every
 *       Opportunity is inserted at 'New' and then moved to its target stage by a
 *       bulk UPDATE. That update is also what lets BookingService see an old->new
 *       stage transition.
 * ============================================================================
 */

// ===========================================================================
// CONFIG — must match the other scripts in the series
// ===========================================================================
Boolean DRY_RUN = false;   // true = roll everything back at the end

final String TAG    = 'SEED';
final String PROJ_A = 'ZSA';
final String PROJ_B = 'ZSB';

final Id   RUNNING_USER = UserInfo.getUserId();
final Date RUN_DATE     = Date.today();

// ===========================================================================
// PRE-FLIGHT — re-query dependencies; abort loudly if absent
// ===========================================================================
Map<String, Project__c> projByCode = new Map<String, Project__c>();
for (Project__c p : [SELECT Id, Project_Code__c FROM Project__c WHERE Project_Code__c IN (:PROJ_A, :PROJ_B)]) {
    projByCode.put(p.Project_Code__c, p);
}
if (projByCode.size() != 2) {
    throw new IllegalArgumentException('ABORT: seed Projects missing. Commit script 01 first.');
}
Project__c projA = projByCode.get(PROJ_A);
Project__c projB = projByCode.get(PROJ_B);

Map<String, Unit__c> unitByName = new Map<String, Unit__c>();
for (Unit__c u : [
    SELECT Id, Name, Unit_Status__c FROM Unit__c
    WHERE Tower__r.Project__r.Project_Code__c IN (:PROJ_A, :PROJ_B)
]) {
    unitByName.put(u.Name, u);
}
if (unitByName.size() != 48) {
    throw new IllegalArgumentException(
        'ABORT: expected 48 seed Units, found ' + unitByName.size() + '. Commit script 01 first.');
}

Map<String, Account> accByName = new Map<String, Account>();
String seedNamePrefix = TAG + ' %';
for (Account a : [SELECT Id, Name, CP_Status__c FROM Account WHERE Name LIKE :seedNamePrefix]) {
    accByName.put(a.Name, a);
}
Account cpHorizon   = accByName.get(TAG + ' Horizon Realty LLP');
Account cpBeacon    = accByName.get(TAG + ' Beacon Property Advisors');
Account accKulkarni = accByName.get(TAG + ' Rajesh Kulkarni');
Account accShenoy   = accByName.get(TAG + ' Priya Shenoy');
Account accBala     = accByName.get(TAG + ' Sunita Balakrishnan (NRI)');
Account accTrivedi  = accByName.get(TAG + ' Devang Trivedi');
Account accJoshi    = accByName.get(TAG + ' Meera Joshi');
Account accVikram   = accByName.get(TAG + ' Vikram Enterprises Pvt Ltd');
for (Account a : new List<Account>{ cpHorizon, cpBeacon, accKulkarni, accShenoy, accBala,
                                    accTrivedi, accJoshi, accVikram }) {
    if (a == null) {
        throw new IllegalArgumentException('ABORT: seed Accounts missing. Commit script 02 first.');
    }
}
// Constraint (c) — Source_CP_Must_Be_Active is evaluated when BookingService inserts.
if (cpHorizon.CP_Status__c != 'Active' || cpBeacon.CP_Status__c != 'Active') {
    throw new IllegalArgumentException(
        'ABORT: Horizon and/or Beacon are not CP_Status__c = Active. Booking__c.Source_CP_Must_Be_Active '
        + 'would reject the Closed Won transitions below. Re-run script 02 (its CP activation block).');
}

Map<String, Lead> leadByEmail = new Map<String, Lead>();
for (Lead l : [
    SELECT Id, Email FROM Lead
    WHERE Email IN ('gaurav.sethi.seed@recrm-demo.invalid', 'kavya.nair.seed@recrm-demo.invalid')
      AND IsConverted = false
]) {
    leadByEmail.put(l.Email, l);
}
Lead leadGaurav = leadByEmail.get('gaurav.sethi.seed@recrm-demo.invalid');
Lead leadKavya  = leadByEmail.get('kavya.nair.seed@recrm-demo.invalid');
if (leadGaurav == null || leadKavya == null) {
    throw new IllegalArgumentException(
        'ABORT: the unconverted seed Leads (Gaurav Sethi / Kavya Nair) were not found. '
        + 'Commit script 03 (seed-test-data-03-leads.apex) with DRY_RUN = false first.');
}

// BookingService.onOpportunityClosedWon assigns every new Booking to the Post-Sales
// queue with a single-row assignment query. If that queue is missing on this SDO the
// failure surfaces as an opaque QueryException from inside OpportunityTrigger, so
// check it up front instead.
if ([SELECT COUNT() FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Post_Sales_Queue'] == 0) {
    throw new IllegalArgumentException(
        'ABORT: the Post_Sales_Queue queue does not exist on this org. BookingService assigns every '
        + 'new Booking to it, so the Closed Won transitions below would fail inside the trigger. '
        + 'Deploy force-app/main/default/queues/ first.');
}

Id rtOppRes = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Pre_sales_Residential').getRecordTypeId();
Id rtOppCom = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Pre_sales_Commercial').getRecordTypeId();

List<String> summaryOrder = new List<String>();
Map<String, Integer> counts = new Map<String, Integer>();
List<String> notes = new List<String>();

Savepoint sp = Database.setSavepoint();

System.debug(LoggingLevel.INFO, '=== SEED 04 OPPORTUNITIES START (DRY_RUN=' + DRY_RUN + ') ===');

// ===========================================================================
// 1. UNIT PICKS + BLOCKING (constraint (b))
//    Residential Opportunities get PROJ_A units, commercial ones get PROJ_B
//    shops: Booking__c.Project__c is a formula over Unit__r.Tower__r.Project__r,
//    so a mismatched Unit would silently produce a Booking on the wrong Project
//    and resolve the wrong Commission Rate Card.
// ===========================================================================
Unit__c unitBook1   = unitByName.get(PROJ_A + '-T01-F02-U002');   // residential, CP Horizon
Unit__c unitBook2   = unitByName.get(PROJ_A + '-T01-F03-U004');   // residential, direct sale
Unit__c unitBook3   = unitByName.get(PROJ_B + '-B01-F01-S001');   // commercial,  CP Beacon
Unit__c unitNego    = unitByName.get(PROJ_A + '-T02-F01-U003');
Unit__c unitEoi     = unitByName.get(PROJ_A + '-T02-F02-U001');
Unit__c unitTokenCm = unitByName.get(PROJ_B + '-B01-F02-S003');   // commercial Opportunity
Unit__c unitLost    = unitByName.get(PROJ_A + '-T02-F03-U002');

for (Unit__c u : new List<Unit__c>{ unitBook1, unitBook2, unitBook3 }) {
    if (u.Unit_Status__c != 'Available') {
        throw new IllegalArgumentException(
            'ABORT: unit ' + u.Name + ' is ' + u.Unit_Status__c + ', not Available. UnitBlockingService '
            + 'expects Available. A previous run of this script probably left it Blocked/Booked — reset '
            + 'it via the UnitLifecycleService state machine before re-running.');
    }
}

List<UnitBlockingService.BlockRequest> blockReqs = new List<UnitBlockingService.BlockRequest>();
for (Unit__c u : new List<Unit__c>{ unitBook1, unitBook2, unitBook3 }) {
    UnitBlockingService.BlockRequest br = new UnitBlockingService.BlockRequest();
    br.unitId = u.Id;
    br.durationHours = 72;
    blockReqs.add(br);
}
UnitBlockingService.blockUnit(blockReqs);   // bulk, single DML inside the service

// ===========================================================================
// 2. OPPORTUNITIES
//    Inserted at 'New' (constraint (d)), then moved to their target stages by a
//    bulk update so that:
//      - the 4 ISCHANGED(StageName) validation rules actually fire, and
//      - OpportunityTrigger/BookingService sees a real stage transition for the
//        three Closed Won records and creates their Bookings.
//    Stage coverage here: Site Visit Scheduled, Site Visit Done, Negotiation,
//    EOI, Token Paid, Closed Lost, Closed Won (Booked) x3. ('Qualified' and a
//    second 'Site Visit Done' are covered by script 03's converted Opportunities.)
// ===========================================================================
List<Opportunity> directOpps = new List<Opportunity>{
    new Opportunity(Name = TAG + ' Opportunity', RecordTypeId = rtOppRes, AccountId = accShenoy.Id, StageName = 'New',
        CloseDate = RUN_DATE.addDays(45), Project__c = projA.Id, Budget_Range__c = 'Rs 65-80L',
        Source_Channel__c = 'Walk-in'),
    new Opportunity(Name = TAG + ' Opportunity', RecordTypeId = rtOppRes, AccountId = accTrivedi.Id, StageName = 'New',
        CloseDate = RUN_DATE.addDays(30), Project__c = projA.Id, Budget_Range__c = 'Rs 80L-1Cr',
        Source_Channel__c = 'Digital'),
    new Opportunity(Name = TAG + ' Opportunity', RecordTypeId = rtOppRes, AccountId = accJoshi.Id, StageName = 'New',
        CloseDate = RUN_DATE.addDays(60), Project__c = projA.Id, Budget_Range__c = 'Rs 1-1.2Cr',
        Source_Channel__c = 'Referral'),
    new Opportunity(Name = TAG + ' Opportunity', RecordTypeId = rtOppRes, AccountId = accBala.Id, StageName = 'New',
        CloseDate = RUN_DATE.addDays(20), Project__c = projA.Id, Budget_Range__c = 'Rs 1.2-1.5Cr',
        Source_Channel__c = 'CP', Source_CP__c = cpBeacon.Id),
    new Opportunity(Name = TAG + ' Opportunity', RecordTypeId = rtOppCom, AccountId = accVikram.Id, StageName = 'New',
        CloseDate = RUN_DATE.addDays(75), Project__c = projB.Id, Budget_Range__c = 'Rs 1.5-2Cr',
        Source_Channel__c = 'Walk-in'),
    new Opportunity(Name = TAG + ' Opportunity', RecordTypeId = rtOppRes, AccountId = accKulkarni.Id, StageName = 'New',
        CloseDate = RUN_DATE.addDays(15), Project__c = projA.Id, Budget_Range__c = 'Rs 90L-1.1Cr',
        Source_Channel__c = 'CP', Source_CP__c = cpHorizon.Id),
    new Opportunity(Name = TAG + ' Opportunity', RecordTypeId = rtOppCom, AccountId = accShenoy.Id, StageName = 'New',
        CloseDate = RUN_DATE.addDays(25), Project__c = projB.Id, Budget_Range__c = 'Rs 1.4-1.7Cr',
        Source_Channel__c = 'CP', Source_CP__c = cpBeacon.Id)
};
insert directOpps;

Opportunity oppSvSched  = directOpps[0];   // -> Site Visit Scheduled
Opportunity oppSvDone   = directOpps[1];   // -> Site Visit Done
Opportunity oppNego     = directOpps[2];   // -> Negotiation
Opportunity oppEoi      = directOpps[3];   // -> EOI
Opportunity oppTokenCom = directOpps[4];   // -> Token Paid (commercial)
Opportunity oppWon1     = directOpps[5];   // -> Closed Won (Booked)  [CP: Horizon/Platinum]
Opportunity oppWon2     = directOpps[6];   // -> Closed Won (Booked)  [CP: Beacon/Preferred, commercial]

// Constraint (a): first of two Opportunity update statements in this transaction.
RecursionGuard.reset('Opportunity_afterUpdate');

List<Opportunity> oppStageUpdates = new List<Opportunity>();
oppStageUpdates.add(new Opportunity(Id = oppSvSched.Id, StageName = 'Site Visit Scheduled'));
oppStageUpdates.add(new Opportunity(Id = oppSvDone.Id,  StageName = 'Site Visit Done'));

// Require_Unit_By_Negotiation kicks in from Negotiation onwards.
oppStageUpdates.add(new Opportunity(Id = oppNego.Id, StageName = 'Negotiation',
    Primary_Unit__c = unitNego.Id, Quoted_Gross_Value__c = 10400000,
    Concession_Requested_Pct__c = 3));
oppStageUpdates.add(new Opportunity(Id = oppEoi.Id, StageName = 'EOI',
    Primary_Unit__c = unitEoi.Id, Quoted_Gross_Value__c = 13200000,
    EOI_Amount__c = 200000, Concession_Requested_Pct__c = 7.5));
oppStageUpdates.add(new Opportunity(Id = oppTokenCom.Id, StageName = 'Token Paid',
    Primary_Unit__c = unitTokenCm.Id, Quoted_Gross_Value__c = 15800000,
    EOI_Amount__c = 250000, Token_Amount__c = 500000));

// Closed Won: Closed_Won_Requires_Financials needs EOI + Token + Primary Unit.
oppStageUpdates.add(new Opportunity(Id = oppWon1.Id, StageName = 'Closed Won (Booked)',
    Primary_Unit__c = unitBook1.Id, Quoted_Gross_Value__c = 9850000,
    EOI_Amount__c = 150000, Token_Amount__c = 400000));
oppStageUpdates.add(new Opportunity(Id = oppWon2.Id, StageName = 'Closed Won (Booked)',
    Primary_Unit__c = unitBook3.Id, Quoted_Gross_Value__c = 16400000,
    EOI_Amount__c = 250000, Token_Amount__c = 600000));

update oppStageUpdates;

// A third Closed Won, plus the Closed Lost record, so the two remaining stages are
// covered. These are the SECOND Opportunity update statement in this transaction,
// so the guard MUST be reset again for BookingService to run (constraint (a)).
Opportunity oppWon3 = new Opportunity(
    Name = TAG + ' Opportunity',
    RecordTypeId = rtOppRes, AccountId = accShenoy.Id, StageName = 'New',
    CloseDate = RUN_DATE.addDays(10), Project__c = projA.Id, Budget_Range__c = 'Rs 1.1-1.3Cr',
    Source_Channel__c = 'Walk-in'                        // direct sale — no Source CP
);
Opportunity oppLost = new Opportunity(
    Name = TAG + ' Opportunity',
    RecordTypeId = rtOppRes, AccountId = accJoshi.Id, StageName = 'New',
    CloseDate = RUN_DATE.addDays(5), Project__c = projA.Id, Budget_Range__c = 'Rs 60-70L',
    Source_Channel__c = 'Aggregator-99acres'
);
List<Opportunity> tailOpps = new List<Opportunity>{ oppWon3, oppLost };
insert tailOpps;

RecursionGuard.reset('Opportunity_afterUpdate');
List<Opportunity> tailOppStageUpdates = new List<Opportunity>{
    new Opportunity(Id = oppWon3.Id, StageName = 'Closed Won (Booked)',
        Primary_Unit__c = unitBook2.Id, Quoted_Gross_Value__c = 11750000,
        EOI_Amount__c = 200000, Token_Amount__c = 500000),
    // Closed_Lost_Requires_Reason
    new Opportunity(Id = oppLost.Id, StageName = 'Closed Lost',
        Primary_Unit__c = unitLost.Id,
        Close_Reason_Lost__c = 'Price')
};
update tailOppStageUpdates;

summaryOrder.add('Opportunity');  counts.put('Opportunity', directOpps.size() + tailOpps.size());

// ===========================================================================
// 3. BOOKINGS — created by BookingService, not by this script. Read back purely
//    to verify the trigger chain fired; script 05 enriches them.
// ===========================================================================
Set<Id> closedWonOppIds = new Set<Id>{ oppWon1.Id, oppWon2.Id, oppWon3.Id };
List<Booking__c> bookings = [
    SELECT Id, Name, Opportunity__c, Unit__r.Name, Booking_Status__c
    FROM Booking__c WHERE Opportunity__c IN :closedWonOppIds ORDER BY Name
];
if (bookings.size() != 3) {
    notes.add('Expected 3 Bookings from the Closed Won transitions but found ' + bookings.size()
        + '. Check that OpportunityTrigger/BookingService is active, that the Post_Sales_Queue queue '
        + 'exists, and that BOTH RecursionGuard.reset(\'Opportunity_afterUpdate\') calls above are intact.');
}
summaryOrder.add('Booking__c (by BookingService)');  counts.put('Booking__c (by BookingService)', bookings.size());
for (Booking__c b : bookings) {
    System.debug(LoggingLevel.INFO, 'BOOKING ' + b.Name + ' | unit=' + b.Unit__r.Name
        + ' | status=' + b.Booking_Status__c);
}

// ===========================================================================
// 4. SITE VISITS
// ===========================================================================
List<Site_Visit__c> siteVisits = new List<Site_Visit__c>{
    new Site_Visit__c(Project__c = projA.Id, Lead__c = leadGaurav.Id,
        Scheduled_DateTime__c = DateTime.now().addDays(3).addHours(2),
        Status__c = 'Scheduled', Conducted_By__c = RUNNING_USER,
        Primary_Unit__c = unitNego.Id,
        Next_Action__c = TAG + ' — confirm attendance on WhatsApp a day prior',
        Next_Action_Date__c = RUN_DATE.addDays(2)),
    new Site_Visit__c(Project__c = projA.Id, Opportunity__c = oppSvDone.Id,
        Scheduled_DateTime__c = DateTime.now().addDays(-6),
        Actual_DateTime__c = DateTime.now().addDays(-6).addMinutes(20),
        Status__c = 'Done', Outcome__c = 'Interested-Hot', Conducted_By__c = RUNNING_USER,
        Primary_Unit__c = unitEoi.Id,
        Units_Shown__c = PROJ_A + '-T02-F02-U001, ' + PROJ_A + '-T02-F03-U002',
        Buyer_Feedback__c = TAG + ' — liked the east-facing 3BHK; wants floor-rise waived.',
        Concessions_Discussed__c = 'Floor rise waiver, 2 covered parkings',
        Next_Action__c = 'Share revised cost sheet', Next_Action_Date__c = RUN_DATE.addDays(1)),
    new Site_Visit__c(Project__c = projB.Id, Opportunity__c = oppTokenCom.Id,
        Scheduled_DateTime__c = DateTime.now().addDays(-11),
        Actual_DateTime__c = DateTime.now().addDays(-11).addMinutes(45),
        Status__c = 'Done', Outcome__c = 'Interested-Warm', Conducted_By__c = RUNNING_USER,
        Primary_Unit__c = unitTokenCm.Id,
        Units_Shown__c = PROJ_B + '-B01-F02-S003, ' + PROJ_B + '-B01-F02-S004',
        Buyer_Feedback__c = TAG + ' — frontage good; wants anchor-tenant commitment first.',
        Next_Action__c = 'Share anchor tenant LOI status', Next_Action_Date__c = RUN_DATE.addDays(4)),
    new Site_Visit__c(Project__c = projA.Id, Lead__c = leadKavya.Id,
        Scheduled_DateTime__c = DateTime.now().addDays(-2),
        Status__c = 'No-Show', Conducted_By__c = RUNNING_USER,
        Next_Action__c = TAG + ' — re-book for next weekend', Next_Action_Date__c = RUN_DATE.addDays(5))
};
insert siteVisits;
summaryOrder.add('Site_Visit__c');  counts.put('Site_Visit__c', siteVisits.size());

// ===========================================================================
// SUMMARY — computed BEFORE any rollback, since a rollback invalidates Ids.
// ===========================================================================
Integer totalRecords = 0;
for (String k : summaryOrder) totalRecords += counts.get(k);

System.debug(LoggingLevel.INFO, '');
System.debug(LoggingLevel.INFO, '======= SEED 04 OPPORTUNITIES SUMMARY =========');
System.debug(LoggingLevel.INFO, 'Mode: ' + (DRY_RUN ? 'DRY RUN (everything rolled back)' : 'COMMITTED'));
for (String k : summaryOrder) {
    System.debug(LoggingLevel.INFO, '  ' + k.rightPad(34, ' ') + ' : ' + counts.get(k));
}
System.debug(LoggingLevel.INFO, '  TOTAL RECORDS'.rightPad(36, ' ') + ' : ' + totalRecords);
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
System.debug(LoggingLevel.INFO, '===============================================');

// ===========================================================================
// ROLLBACK (dry run only)
// ===========================================================================
if (DRY_RUN) {
    Database.rollback(sp);
    System.debug(LoggingLevel.INFO,
        'DRY RUN COMPLETE — unit blocking, all nine Opportunities, the trigger-created Bookings and the '
        + 'site visits executed and passed validation, then were rolled back. Set DRY_RUN = false and '
        + 're-run to commit, THEN move on to scripts/seed-test-data-05-bookings.apex.');
} else {
    System.debug(LoggingLevel.INFO,
        'SEED 04 COMMITTED. Next: scripts/seed-test-data-05-bookings.apex. The three Bookings sit on '
        + 'units ' + PROJ_A + '-T01-F02-U002 / ' + PROJ_B + '-B01-F01-S001 / ' + PROJ_A + '-T01-F03-U004.');
}
