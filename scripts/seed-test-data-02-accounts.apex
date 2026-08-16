/**
 * ============================================================================
 * seed-test-data-02-accounts.apex — SCRIPT 2 OF 7
 * ============================================================================
 *
 * DEPENDS ON: scripts/seed-test-data-01-inventory.apex having been COMMITTED
 *   (DRY_RUN = false). This script re-queries, since no in-memory state carries
 *   across executeAnonymous transactions:
 *     Project__c  — by Project_Code__c IN ('ZSA','ZSB')   [needed for Rate Cards]
 *
 * PRODUCES (re-queryable by later scripts):
 *   Account   x4  CP        — Name 'SEED Horizon Realty LLP' / 'SEED Beacon Property
 *                             Advisors' / 'SEED Sunridge Associates' / 'SEED Kaveri
 *                             Homes Network'
 *   Account   x7  Buyer/Corp— Name 'SEED <person>' (see block 2)
 *   Contact   x12           — Email '<first>.<last>.seed@recrm-demo.invalid',
 *                             LastName '<Surname>-SEED'
 *   Commission_Rate_Card__c x5 — keyed on (Project__c, CP_Tier__c)
 *   Payment_Plan__c x1      — Plan_Code__c = 'ZSCLP'
 *   Payment_Plan_Milestone__c x4
 *
 * HOW TO RUN
 *   sf apex run --file scripts/seed-test-data-02-accounts.apex --target-org re-crm-sdo
 *   Dry-run first (DRY_RUN = true), then commit, THEN run script 03.
 *   See script 01's header for why the series cannot be dry-run end-to-end first.
 *
 * SAFETY / SYSTEM MODE / TAGGING
 *   Identical to script 01 — see that file's header. Runs in system mode
 *   deliberately (gotcha #27). DRY_RUN wraps everything in a Savepoint.
 *
 * SEQUENCING CONSTRAINTS HONOURED IN THIS FILE
 *   (c) Booking__c.Source_CP_Must_Be_Active requires the Source CP Account to be
 *       CP_Status__c = 'Active' at Booking insert (which happens in script 04).
 *       CP accounts are inserted at 'Pending Approval' and the two we actually
 *       trade with are then UPDATED to 'Active' here — which also fires the
 *       CP_Status_Change_Handler before-save Flow (stamps Empanelment_Date /
 *       Approval_Date / Approved_By / Portal_Access). The two CPs left at
 *       'Pending Approval' are never referenced by a Booking; script 07 submits
 *       them into CP_Registration_Approval.
 *   (e) Gotcha #40: Payment_Plan__c.Active_Plan_Total_Pct_Must_Be_100 re-evaluates
 *       mid-batch as milestone rollups settle. The plan is seeded Active__c=false,
 *       milestones are inserted, then activation is ATTEMPTED in a try/catch. If it
 *       fails the script continues — PaymentScheduleService filters on
 *       Payment_Plan_Milestone__c.Active__c, not on the plan's Active__c, so the
 *       schedule still instantiates correctly in script 04. Script 05 makes one
 *       more opportunistic activation attempt in ITS (later) transaction, by which
 *       point the rollup has usually settled — that cross-transaction retry is the
 *       exact pattern gotcha #40 prescribes and is a genuine benefit of the split.
 * ============================================================================
 */

// ===========================================================================
// CONFIG — must match scripts 01 and 03-07
// ===========================================================================
Boolean DRY_RUN = false;   // true = roll everything back at the end

final String TAG       = 'SEED';
final String PROJ_A    = 'ZSA';
final String PROJ_B    = 'ZSB';
final String PLAN_CODE = 'ZSCLP';   // Payment_Plan__c.Plan_Code__c is unique, max 10 chars

final Date RUN_DATE = Date.today();

// ===========================================================================
// PRE-FLIGHT — dependencies present, and no half-collision with a previous run
// ===========================================================================
Map<String, Project__c> projByCode = new Map<String, Project__c>();
for (Project__c p : [SELECT Id, Project_Code__c FROM Project__c WHERE Project_Code__c IN (:PROJ_A, :PROJ_B)]) {
    projByCode.put(p.Project_Code__c, p);
}
if (projByCode.size() != 2) {
    throw new IllegalArgumentException(
        'ABORT: expected the 2 seed Projects (' + PROJ_A + ', ' + PROJ_B + ') but found '
        + projByCode.size() + '. Run scripts/seed-test-data-01-inventory.apex with DRY_RUN = false first.'
    );
}
Project__c projA = projByCode.get(PROJ_A);
Project__c projB = projByCode.get(PROJ_B);

if ([SELECT COUNT() FROM Payment_Plan__c WHERE Plan_Code__c = :PLAN_CODE] > 0) {
    throw new IllegalArgumentException(
        'ABORT: Payment Plan Code ' + PLAN_CODE + ' already exists (Plan_Code__c is unique). '
        + 'This script is one-shot — delete the previous seed data or change PLAN_CODE (here and in '
        + 'script 05) before re-running.'
    );
}
String probeCpName = TAG + ' Horizon Realty LLP';
if ([SELECT COUNT() FROM Account WHERE Name = :probeCpName] > 0) {
    throw new IllegalArgumentException(
        'ABORT: seed Accounts already present (found "' + TAG + ' Horizon Realty LLP"). '
        + 'This script is one-shot. Delete the previous seed data before re-running.'
    );
}

// ===========================================================================
// RECORD TYPE IDS
// ===========================================================================
Id rtAccBuyer = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Buyer').getRecordTypeId();
Id rtAccCorp  = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Corporate_Buyer').getRecordTypeId();
Id rtAccCp    = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Channel_Partner').getRecordTypeId();

List<String> summaryOrder = new List<String>();
Map<String, Integer> counts = new Map<String, Integer>();
List<String> notes = new List<String>();

Savepoint sp = Database.setSavepoint();

System.debug(LoggingLevel.INFO, '=== SEED 02 ACCOUNTS START (DRY_RUN=' + DRY_RUN + ') ===');

// ===========================================================================
// 1. CHANNEL PARTNER ACCOUNTS + CONTACTS
//    cpBeacon and cpKaveri have no GSTIN on purpose — that exercises
//    CommissionService's 18% reverse-charge GST branch in script 07.
// ===========================================================================
Database.DMLOptions dupAllow = new Database.DMLOptions();
dupAllow.DuplicateRuleHeader.allowSave = true;

List<Account> cpAccounts = new List<Account>{
    new Account(
        Name = TAG + ' Horizon Realty LLP', RecordTypeId = rtAccCp,
        Phone = '9820100101', CP_Status__c = 'Pending Approval', CP_Tier__c = 'Platinum',
        GSTIN__c = '27AAACH1234A1Z5', PAN__c = 'AAACH1234A',
        BillingCity = 'Pune', BillingState = 'Maharashtra', BillingCountry = 'India',
        RERA_Number__c = 'A52100' + TAG + '101', RERA_State__c = 'Maharashtra',
        KYC_Status__c = 'Verified', KYC_Verified_Date__c = RUN_DATE.addDays(-45),
        Blacklisted__c = false
    ),
    new Account(
        Name = TAG + ' Beacon Property Advisors', RecordTypeId = rtAccCp,
        Phone = '9820100102', CP_Status__c = 'Pending Approval', CP_Tier__c = 'Preferred',
        GSTIN__c = null,                              // no GSTIN -> reverse-charge GST path
        PAN__c = 'AAACB5678B',
        BillingCity = 'Navi Mumbai', BillingState = 'Maharashtra', BillingCountry = 'India',
        RERA_Number__c = 'A51700' + TAG + '102', RERA_State__c = 'Maharashtra',
        KYC_Status__c = 'Verified', KYC_Verified_Date__c = RUN_DATE.addDays(-30),
        Blacklisted__c = false
    ),
    new Account(
        Name = TAG + ' Sunridge Associates', RecordTypeId = rtAccCp,
        Phone = '9820100103', CP_Status__c = 'Pending Approval', CP_Tier__c = 'Standard',
        GSTIN__c = '27AAACS9012C1Z9', PAN__c = 'AAACS9012C',
        BillingCity = 'Pune', BillingState = 'Maharashtra', BillingCountry = 'India',
        RERA_State__c = 'Maharashtra', KYC_Status__c = 'Pending', Blacklisted__c = false
    ),
    new Account(
        Name = TAG + ' Kaveri Homes Network', RecordTypeId = rtAccCp,
        Phone = '9820100104', CP_Status__c = 'Pending Approval', CP_Tier__c = 'Standard',
        GSTIN__c = null, PAN__c = 'AAACK3456D',
        BillingCity = 'Thane', BillingState = 'Maharashtra', BillingCountry = 'India',
        RERA_State__c = 'Maharashtra', KYC_Status__c = 'Pending', Blacklisted__c = false
    )
};
Database.insert(cpAccounts, dupAllow);
Account cpHorizon  = cpAccounts[0];
Account cpBeacon   = cpAccounts[1];
Account cpSunridge = cpAccounts[2];
Account cpKaveri   = cpAccounts[3];

// Activate the two CPs script 04 will source bookings from (constraint (c)).
List<Account> cpActivations = new List<Account>{
    new Account(Id = cpHorizon.Id, CP_Status__c = 'Active', Portal_Access__c = true),
    new Account(Id = cpBeacon.Id,  CP_Status__c = 'Active', Portal_Access__c = true)
};
update cpActivations;

List<Contact> cpContacts = new List<Contact>{
    new Contact(AccountId = cpHorizon.Id, FirstName = 'Nikhil', LastName = 'Marathe-' + TAG,
                Email = 'nikhil.marathe.seed@recrm-demo.invalid', Phone = '9820100201',
                Title = 'Principal Broker', Occupation__c = 'Real Estate Broker'),
    new Contact(AccountId = cpBeacon.Id, FirstName = 'Farida', LastName = 'Contractor-' + TAG,
                Email = 'farida.contractor.seed@recrm-demo.invalid', Phone = '9820100202',
                Title = 'Managing Partner', Occupation__c = 'Real Estate Broker'),
    new Contact(AccountId = cpSunridge.Id, FirstName = 'Ramesh', LastName = 'Bhandari-' + TAG,
                Email = 'ramesh.bhandari.seed@recrm-demo.invalid', Phone = '9820100203',
                Title = 'Proprietor', Occupation__c = 'Real Estate Broker'),
    new Contact(AccountId = cpKaveri.Id, FirstName = 'Shalini', LastName = 'Rao-' + TAG,
                Email = 'shalini.rao.seed@recrm-demo.invalid', Phone = '9820100204',
                Title = 'Director', Occupation__c = 'Real Estate Broker')
};
Database.insert(cpContacts, dupAllow);

// ===========================================================================
// 2. CUSTOMER (BUYER) ACCOUNTS + CONTACTS
//    Deliberate variety so buyerProfileCard's PAN masking, NRI handling and
//    KYC states all have something to render:
//      - 2 NRI buyers (one with Passport, one without)
//      - 1 buyer with no PAN on file (masking must degrade gracefully)
//      - 1 Corporate Buyer record type
// ===========================================================================
List<Account> buyerAccounts = new List<Account>{
    new Account(Name = TAG + ' Rajesh Kulkarni', RecordTypeId = rtAccBuyer, Phone = '9820200301',
                Buyer_Type__c = 'Self-Use', PAN__c = 'ABCPK1101A', Aadhaar_Last4__c = '4417',
                KYC_Status__c = 'Verified', KYC_Verified_Date__c = RUN_DATE.addDays(-20),
                NRI_Status__c = false, Source_Of_Funds__c = 'Salary', DOB__c = Date.newInstance(1984, 3, 12),
                BillingCity = 'Pune', BillingState = 'Maharashtra', BillingCountry = 'India'),
    new Account(Name = TAG + ' Priya Shenoy', RecordTypeId = rtAccBuyer, Phone = '9820200302',
                Buyer_Type__c = 'Investor', PAN__c = 'ABCPS1102B', Aadhaar_Last4__c = '9083',
                KYC_Status__c = 'Verified', KYC_Verified_Date__c = RUN_DATE.addDays(-18),
                NRI_Status__c = false, Source_Of_Funds__c = 'Business', DOB__c = Date.newInstance(1979, 11, 2),
                BillingCity = 'Mumbai', BillingState = 'Maharashtra', BillingCountry = 'India'),
    new Account(Name = TAG + ' Arun Menon (NRI)', RecordTypeId = rtAccBuyer, Phone = '971501234567',
                Buyer_Type__c = 'Investor', PAN__c = 'ABCPM1103C', Aadhaar_Last4__c = null,
                KYC_Status__c = 'Pending', NRI_Status__c = true, Source_Of_Funds__c = 'Salary',
                DOB__c = Date.newInstance(1981, 6, 30),
                BillingCity = 'Dubai', BillingCountry = 'United Arab Emirates'),
    new Account(Name = TAG + ' Sunita Balakrishnan (NRI)', RecordTypeId = rtAccBuyer, Phone = '14085550199',
                Buyer_Type__c = 'Investor', PAN__c = null,          // no PAN on file — masking edge case
                KYC_Status__c = 'Pending', NRI_Status__c = true, Source_Of_Funds__c = 'Investment',
                DOB__c = Date.newInstance(1986, 1, 22),
                BillingCity = 'San Jose', BillingCountry = 'United States'),
    new Account(Name = TAG + ' Devang Trivedi', RecordTypeId = rtAccBuyer, Phone = '9820200305',
                Buyer_Type__c = 'Self-Use', PAN__c = 'ABCPT1105E', Aadhaar_Last4__c = '2260',
                KYC_Status__c = 'Verified', KYC_Verified_Date__c = RUN_DATE.addDays(-9),
                NRI_Status__c = false, Source_Of_Funds__c = 'Salary', DOB__c = Date.newInstance(1990, 9, 5),
                BillingCity = 'Pune', BillingState = 'Maharashtra', BillingCountry = 'India'),
    new Account(Name = TAG + ' Meera Joshi', RecordTypeId = rtAccBuyer, Phone = '9820200306',
                Buyer_Type__c = 'Self-Use', PAN__c = 'ABCPJ1106F', Aadhaar_Last4__c = '7731',
                KYC_Status__c = 'Rejected', NRI_Status__c = false, Source_Of_Funds__c = 'Inheritance',
                DOB__c = Date.newInstance(1975, 4, 18),
                BillingCity = 'Nashik', BillingState = 'Maharashtra', BillingCountry = 'India'),
    new Account(Name = TAG + ' Vikram Enterprises Pvt Ltd', RecordTypeId = rtAccCorp, Phone = '9820200307',
                Buyer_Type__c = 'Investor', PAN__c = 'AABCV1107G', GSTIN__c = '27AABCV1107G1ZK',
                KYC_Status__c = 'Verified', KYC_Verified_Date__c = RUN_DATE.addDays(-60),
                NRI_Status__c = false, Source_Of_Funds__c = 'Business',
                BillingCity = 'Mumbai', BillingState = 'Maharashtra', BillingCountry = 'India')
};
Database.insert(buyerAccounts, dupAllow);
summaryOrder.add('Account (Buyer/Corporate + CP)');
counts.put('Account (Buyer/Corporate + CP)', buyerAccounts.size() + cpAccounts.size());

Account accKulkarni = buyerAccounts[0];
Account accShenoy   = buyerAccounts[1];
Account accMenon    = buyerAccounts[2];
Account accBala     = buyerAccounts[3];
Account accTrivedi  = buyerAccounts[4];
Account accJoshi    = buyerAccounts[5];
Account accVikram   = buyerAccounts[6];

List<Contact> buyerContacts = new List<Contact>{
    new Contact(AccountId = accKulkarni.Id, FirstName = 'Rajesh', LastName = 'Kulkarni-' + TAG,
                Email = 'rajesh.kulkarni.seed@recrm-demo.invalid', Phone = '9820200301',
                PAN__c = 'ABCPK1101A', Aadhaar_Last4__c = '4417', NRI_Status__c = false,
                DOB__c = Date.newInstance(1984, 3, 12), Occupation__c = 'IT Services — Delivery Head'),
    new Contact(AccountId = accKulkarni.Id, FirstName = 'Anjali', LastName = 'Kulkarni-' + TAG,
                Email = 'anjali.kulkarni.seed@recrm-demo.invalid', Phone = '9820200311',
                PAN__c = 'ABCPK1111H', Aadhaar_Last4__c = '5528', NRI_Status__c = false,
                DOB__c = Date.newInstance(1987, 7, 9), Occupation__c = 'Architect'),   // co-buyer (joint booking)
    new Contact(AccountId = accShenoy.Id, FirstName = 'Priya', LastName = 'Shenoy-' + TAG,
                Email = 'priya.shenoy.seed@recrm-demo.invalid', Phone = '9820200302',
                PAN__c = 'ABCPS1102B', Aadhaar_Last4__c = '9083', NRI_Status__c = false,
                DOB__c = Date.newInstance(1979, 11, 2), Occupation__c = 'Business Owner'),
    new Contact(AccountId = accMenon.Id, FirstName = 'Arun', LastName = 'Menon-' + TAG,
                Email = 'arun.menon.seed@recrm-demo.invalid', Phone = '971501234567',
                PAN__c = 'ABCPM1103C', NRI_Status__c = true, Passport_Number__c = 'Z1234567',
                DOB__c = Date.newInstance(1981, 6, 30), Occupation__c = 'Petroleum Engineer'),
    new Contact(AccountId = accBala.Id, FirstName = 'Sunita', LastName = 'Balakrishnan-' + TAG,
                Email = 'sunita.bala.seed@recrm-demo.invalid', Phone = '14085550199',
                PAN__c = null, NRI_Status__c = true, Passport_Number__c = null,  // NRI, no passport captured yet
                DOB__c = Date.newInstance(1986, 1, 22), Occupation__c = 'Product Manager'),
    new Contact(AccountId = accTrivedi.Id, FirstName = 'Devang', LastName = 'Trivedi-' + TAG,
                Email = 'devang.trivedi.seed@recrm-demo.invalid', Phone = '9820200305',
                PAN__c = 'ABCPT1105E', Aadhaar_Last4__c = '2260', NRI_Status__c = false,
                DOB__c = Date.newInstance(1990, 9, 5), Occupation__c = 'Chartered Accountant'),
    new Contact(AccountId = accJoshi.Id, FirstName = 'Meera', LastName = 'Joshi-' + TAG,
                Email = 'meera.joshi.seed@recrm-demo.invalid', Phone = '9820200306',
                PAN__c = 'ABCPJ1106F', Aadhaar_Last4__c = '7731', NRI_Status__c = false,
                DOB__c = Date.newInstance(1975, 4, 18), Occupation__c = 'Consultant'),
    new Contact(AccountId = accVikram.Id, FirstName = 'Vikram', LastName = 'Shah-' + TAG,
                Email = 'vikram.shah.seed@recrm-demo.invalid', Phone = '9820200307',
                PAN__c = 'ABCPS1108J', NRI_Status__c = false,
                DOB__c = Date.newInstance(1972, 2, 14), Occupation__c = 'Director')
};
Database.insert(buyerContacts, dupAllow);
summaryOrder.add('Contact');  counts.put('Contact', buyerContacts.size() + cpContacts.size());

// ===========================================================================
// 3. COMMISSION RATE CARDS
//    Pct fields store the LITERAL display value (2.0 == 2%), matching
//    CommissionService's `basis * ratePct / 100` and Total_Pct__c's `* 100`
//    formula compensation, and matching scripts/seed-demo-data-02-customers.apex.
//    VRs honoured: All_Milestones_Required (all three > 0),
//    Effective_From_Required (set), Effective_To_After_From (left blank = open-ended).
// ===========================================================================
List<Commission_Rate_Card__c> rateCards = new List<Commission_Rate_Card__c>{
    new Commission_Rate_Card__c(Project__c = projA.Id, CP_Tier__c = 'Platinum',
        Booking_Pct__c = 2.0, Agreement_Pct__c = 1.0, Registration_Pct__c = 0.5,
        Effective_From__c = RUN_DATE.addMonths(-3),
        Notes__c = TAG + ' — Platinum rate card, Verdant Heights (3.5% total)'),
    new Commission_Rate_Card__c(Project__c = projA.Id, CP_Tier__c = 'Preferred',
        Booking_Pct__c = 1.5, Agreement_Pct__c = 0.75, Registration_Pct__c = 0.25,
        Effective_From__c = RUN_DATE.addMonths(-3),
        Notes__c = TAG + ' — Preferred rate card, Verdant Heights (2.5% total)'),
    new Commission_Rate_Card__c(Project__c = projA.Id, CP_Tier__c = 'Standard',
        Booking_Pct__c = 1.0, Agreement_Pct__c = 0.5, Registration_Pct__c = 0.25,
        Effective_From__c = RUN_DATE.addMonths(-3),
        Notes__c = TAG + ' — Standard rate card, Verdant Heights (1.75% total)'),
    new Commission_Rate_Card__c(Project__c = projB.Id, CP_Tier__c = 'Platinum',
        Booking_Pct__c = 1.75, Agreement_Pct__c = 0.75, Registration_Pct__c = 0.5,
        Effective_From__c = RUN_DATE.addMonths(-2),
        Notes__c = TAG + ' — Platinum rate card, Marina Square (3.0% total)'),
    new Commission_Rate_Card__c(Project__c = projB.Id, CP_Tier__c = 'Preferred',
        Booking_Pct__c = 1.25, Agreement_Pct__c = 0.5, Registration_Pct__c = 0.25,
        Effective_From__c = RUN_DATE.addMonths(-2),
        Notes__c = TAG + ' — Preferred rate card, Marina Square (2.0% total)')
};
insert rateCards;
summaryOrder.add('Commission_Rate_Card__c');  counts.put('Commission_Rate_Card__c', rateCards.size());

// ===========================================================================
// 4. PAYMENT PLAN + MILESTONES  (gotcha #40 sequencing — constraint (e))
//    Seed inactive -> insert milestones -> ATTEMPT activation in try/catch.
// ===========================================================================
Payment_Plan__c seedPlan = new Payment_Plan__c(
    Name = TAG + ' Construction Linked Plan',
    Plan_Code__c = PLAN_CODE,
    Active__c = false,                                  // gotcha #40
    Applicable_Project_Types__c = 'Residential;Commercial',
    Description__c = TAG + ' 4-milestone CLP: 20% on booking, 30% excavation, 30% slab, 20% possession.'
);
insert seedPlan;

List<Payment_Plan_Milestone__c> planMilestones = new List<Payment_Plan_Milestone__c>{
    new Payment_Plan_Milestone__c(Payment_Plan__c = seedPlan.Id, Sequence__c = 1,
        Trigger__c = 'On Booking', Trigger_Type__c = 'Booking', Days_From_Trigger__c = 0,
        Percentage__c = 20, Active__c = true, Description__c = 'Booking amount, payable on confirmation'),
    new Payment_Plan_Milestone__c(Payment_Plan__c = seedPlan.Id, Sequence__c = 2,
        Trigger__c = 'On Excavation', Trigger_Type__c = 'Time-Based', Days_From_Trigger__c = 60,
        Percentage__c = 30, Active__c = true, Description__c = 'On commencement of excavation'),
    new Payment_Plan_Milestone__c(Payment_Plan__c = seedPlan.Id, Sequence__c = 3,
        Trigger__c = 'On Slab Cast', Trigger_Type__c = 'Time-Based', Days_From_Trigger__c = 150,
        Percentage__c = 30, Active__c = true, Description__c = 'On casting of the final slab'),
    new Payment_Plan_Milestone__c(Payment_Plan__c = seedPlan.Id, Sequence__c = 4,
        Trigger__c = 'On Possession', Trigger_Type__c = 'Time-Based', Days_From_Trigger__c = 330,
        Percentage__c = 20, Active__c = true, Description__c = 'On offer of possession')
};
insert planMilestones;
summaryOrder.add('Payment_Plan__c');            counts.put('Payment_Plan__c', 1);
summaryOrder.add('Payment_Plan_Milestone__c');  counts.put('Payment_Plan_Milestone__c', planMilestones.size());

Boolean planActivated = false;
try {
    update new Payment_Plan__c(Id = seedPlan.Id, Active__c = true);
    planActivated = true;
} catch (Exception e) {
    // Expected failure mode per gotcha #40 — the Total_Pct_Check__c roll-up has not
    // settled yet, so Active_Plan_Total_Pct_Must_Be_100 sees an intermediate value.
    // Script 04 retries this in a later transaction; if that also fails, activate
    // manually in Setup. Nothing downstream depends on it.
    notes.add('Payment Plan "' + seedPlan.Name + '" could not be activated in-transaction '
        + '(gotcha #40, expected). Script 05 will retry in its own transaction. '
        + 'Reason: ' + e.getMessage());
}

// ===========================================================================
// SUMMARY — computed BEFORE any rollback, since a rollback invalidates Ids.
// ===========================================================================
Integer totalRecords = 0;
for (String k : summaryOrder) totalRecords += counts.get(k);

System.debug(LoggingLevel.INFO, '');
System.debug(LoggingLevel.INFO, '========== SEED 02 ACCOUNTS SUMMARY ===========');
System.debug(LoggingLevel.INFO, 'Mode: ' + (DRY_RUN ? 'DRY RUN (everything rolled back)' : 'COMMITTED'));
for (String k : summaryOrder) {
    System.debug(LoggingLevel.INFO, '  ' + k.rightPad(34, ' ') + ' : ' + counts.get(k));
}
System.debug(LoggingLevel.INFO, '  TOTAL RECORDS'.rightPad(36, ' ') + ' : ' + totalRecords);
System.debug(LoggingLevel.INFO, '  Payment Plan activated in-transaction : ' + planActivated);
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
        'DRY RUN COMPLETE — every insert/update above executed and passed validation, then was rolled '
        + 'back. Set DRY_RUN = false and re-run to commit, THEN move on to '
        + 'scripts/seed-test-data-03-leads.apex.');
} else {
    System.debug(LoggingLevel.INFO,
        'SEED 02 COMMITTED. Next: scripts/seed-test-data-03-leads.apex. '
        + 'Clean-up handle: Account/Payment Plan names begin with "' + TAG + '", Plan Code is '
        + PLAN_CODE + ', Contact emails end with ".seed@recrm-demo.invalid".');
}
