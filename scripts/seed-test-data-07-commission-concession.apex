/**
 * ============================================================================
 * seed-test-data-07-commission-concession.apex — SCRIPT 7 OF 7 (final)
 * ============================================================================
 *
 * DEPENDS ON: scripts 01-06 having been COMMITTED (DRY_RUN = false).
 *   Re-queried at the top of this file:
 *     Booking__c   — the 3 seed Bookings, keyed on Unit__r.Name
 *     Opportunity  — oppNego / oppEoi / oppTokenCom, keyed on Primary_Unit__r.Name
 *                    (Opportunity Name is uniform after the naming automation, so
 *                     the Primary Unit is the only stable key)
 *     Unit__c      — the three units those Opportunities sit on, by Name
 *     Contact      — buyer + CP seed Contacts, by Email
 *     Account      — the two CPs still at 'Pending Approval', by Name
 *
 * PRODUCES:
 *   Document_Checklist__c x17
 *   Commission_Payout__c (from the ledger entries CommissionService accrued in
 *                         scripts 04 and 06 — ledger rows are NEVER hand-created)
 *   Concession_Request__c x3
 *   Notification_Preference__c x12
 *   4 approval submissions (2 Concession tiers, 2 CP registrations)
 *
 * HOW TO RUN
 *   sf apex run --file scripts/seed-test-data-07-commission-concession.apex --target-org re-crm-sdo
 *   Dry-run first (DRY_RUN = true), then commit. This is the last script.
 *
 * KNOWN LIMITATIONS (carried over from the original single-file script)
 *   - Approval submissions are attempted LAST and individually try/catch'd. They
 *     depend on demo users (psm.prk@recrm-demo.invalid, saleshead@recrm-demo.invalid,
 *     and the CP approver named in CP_Registration_Approval) existing and being
 *     active on this SDO. If they aren't, the submissions are skipped and reported;
 *     every other record is unaffected. Set SUBMIT_APPROVALS = false to skip them.
 *   - This script SUBMITS for approval; it does not APPROVE. Approving requires
 *     running as the assigned approver. Both tiers therefore end with a real,
 *     pending ProcessInstance — not a Draft row — which is what was asked for.
 *   - Approvals are last so that, if this org turns out to disallow rolling back a
 *     transaction containing an Approval.process() call, everything else has
 *     already been verified. If a dry run fails at the rollback step, re-run with
 *     SUBMIT_APPROVALS = false to confirm, then do the real run with it back on.
 *   - CommissionPayoutBatch is a Database.Batchable. Calling it here would run
 *     async (outside the savepoint, so a dry run could not roll it back, and its
 *     results could not be verified in-script). Instead the payout block below
 *     replicates the batch's exact grouping and summing logic inline,
 *     synchronously. Keep the two in sync if CommissionPayoutBatch.execute()
 *     ever changes.
 *   - Document_Checklist__c and Notification_Preference__c business purpose is
 *     inferred from field metadata — no epic doc describes their intended
 *     workflow. See the block comments below for the shape chosen.
 *
 * SEQUENCING CONSTRAINTS
 *   No RecursionGuard resets are needed in this file: it issues no repeated
 *   update to any object whose after-update handler must fire more than once.
 *   (The ledger->payout link update and the single payout status update are
 *   Commission_Ledger__c / Commission_Payout__c writes, which have no guarded
 *   after-update handler in this codebase.)
 * ============================================================================
 */

// ===========================================================================
// CONFIG — must match the other scripts in the series
// ===========================================================================
Boolean DRY_RUN          = false;   // true = roll everything back at the end
Boolean SUBMIT_APPROVALS = true;   // false = skip Approval.process() calls entirely

final String TAG    = 'SEED';
final String PROJ_A = 'ZSA';
final String PROJ_B = 'ZSB';

final Id   RUNNING_USER = UserInfo.getUserId();
final Date RUN_DATE     = Date.today();

final String UNIT_BKG1 = PROJ_A + '-T01-F02-U002';
final String UNIT_BKG2 = PROJ_B + '-B01-F01-S001';
final String UNIT_BKG3 = PROJ_A + '-T01-F03-U004';
final String UNIT_NEGO = PROJ_A + '-T02-F01-U003';
final String UNIT_EOI  = PROJ_A + '-T02-F02-U001';
final String UNIT_TOKC = PROJ_B + '-B01-F02-S003';

// ===========================================================================
// PRE-FLIGHT — re-query dependencies; abort loudly if absent
// ===========================================================================
Map<String, Booking__c> bookingByUnitName = new Map<String, Booking__c>();
for (Booking__c b : [
    SELECT Id, Name, Unit__r.Name, Booking_Status__c
    FROM Booking__c WHERE Unit__r.Name IN (:UNIT_BKG1, :UNIT_BKG2, :UNIT_BKG3) ORDER BY Name
]) {
    bookingByUnitName.put(b.Unit__r.Name, b);
}
Booking__c bkg1 = bookingByUnitName.get(UNIT_BKG1);
Booking__c bkg2 = bookingByUnitName.get(UNIT_BKG2);
Booking__c bkg3 = bookingByUnitName.get(UNIT_BKG3);
if (bkg1 == null || bkg2 == null || bkg3 == null) {
    throw new IllegalArgumentException(
        'ABORT: expected 3 seed Bookings, found ' + bookingByUnitName.size() + '. Commit script 04 first.');
}
List<Booking__c> bookings = new List<Booking__c>{ bkg1, bkg2, bkg3 };

Map<String, Unit__c> unitByName = new Map<String, Unit__c>();
for (Unit__c u : [SELECT Id, Name FROM Unit__c WHERE Name IN (:UNIT_NEGO, :UNIT_EOI, :UNIT_TOKC)]) {
    unitByName.put(u.Name, u);
}
Unit__c unitNego    = unitByName.get(UNIT_NEGO);
Unit__c unitEoi     = unitByName.get(UNIT_EOI);
Unit__c unitTokenCm = unitByName.get(UNIT_TOKC);
if (unitNego == null || unitEoi == null || unitTokenCm == null) {
    throw new IllegalArgumentException('ABORT: seed Units missing. Commit script 01 first.');
}

Map<String, Opportunity> oppByUnitName = new Map<String, Opportunity>();
for (Opportunity o : [
    SELECT Id, StageName, Primary_Unit__r.Name FROM Opportunity
    WHERE Primary_Unit__r.Name IN (:UNIT_NEGO, :UNIT_EOI, :UNIT_TOKC)
]) {
    oppByUnitName.put(o.Primary_Unit__r.Name, o);
}
Opportunity oppNego     = oppByUnitName.get(UNIT_NEGO);
Opportunity oppEoi      = oppByUnitName.get(UNIT_EOI);
Opportunity oppTokenCom = oppByUnitName.get(UNIT_TOKC);
if (oppNego == null || oppEoi == null || oppTokenCom == null) {
    throw new IllegalArgumentException(
        'ABORT: the Negotiation / EOI / Token Paid seed Opportunities were not found by their '
        + 'Primary Unit. Commit script 04 first.');
}

// Buyer Contacts in their original creation order (the opt-in mix below is
// positional), then the CP Contacts.
List<String> buyerEmails = new List<String>{
    'rajesh.kulkarni.seed@recrm-demo.invalid', 'anjali.kulkarni.seed@recrm-demo.invalid',
    'priya.shenoy.seed@recrm-demo.invalid',    'arun.menon.seed@recrm-demo.invalid',
    'sunita.bala.seed@recrm-demo.invalid',     'devang.trivedi.seed@recrm-demo.invalid',
    'meera.joshi.seed@recrm-demo.invalid',     'vikram.shah.seed@recrm-demo.invalid'
};
List<String> cpEmails = new List<String>{
    'nikhil.marathe.seed@recrm-demo.invalid',  'farida.contractor.seed@recrm-demo.invalid',
    'ramesh.bhandari.seed@recrm-demo.invalid', 'shalini.rao.seed@recrm-demo.invalid'
};
Map<String, Contact> conByEmail = new Map<String, Contact>();
for (Contact c : [
    SELECT Id, Email, AccountId FROM Contact WHERE Email LIKE '%.seed@recrm-demo.invalid'
]) {
    conByEmail.put(c.Email, c);
}
List<Contact> buyerContacts = new List<Contact>();
for (String e : buyerEmails) {
    if (conByEmail.get(e) == null) {
        throw new IllegalArgumentException('ABORT: seed Contact ' + e + ' missing. Commit script 02 first.');
    }
    buyerContacts.add(conByEmail.get(e));
}
List<Contact> cpContacts = new List<Contact>();
for (String e : cpEmails) {
    if (conByEmail.get(e) == null) {
        throw new IllegalArgumentException('ABORT: seed Contact ' + e + ' missing. Commit script 02 first.');
    }
    cpContacts.add(conByEmail.get(e));
}

Map<String, Account> accByName = new Map<String, Account>();
List<String> pendingCpNames = new List<String>{ TAG + ' Sunridge Associates', TAG + ' Kaveri Homes Network' };
for (Account a : [
    SELECT Id, Name, CP_Status__c FROM Account WHERE Name IN :pendingCpNames
]) {
    accByName.put(a.Name, a);
}
Account cpSunridge = accByName.get(TAG + ' Sunridge Associates');
Account cpKaveri   = accByName.get(TAG + ' Kaveri Homes Network');
if (cpSunridge == null || cpKaveri == null) {
    throw new IllegalArgumentException('ABORT: the two pending-approval seed CP Accounts are missing. '
        + 'Commit script 02 first.');
}

if ([SELECT COUNT() FROM Document_Checklist__c WHERE Booking__c IN :bookings] > 0) {
    throw new IllegalArgumentException(
        'ABORT: the seed Bookings already have Document Checklists — this script has already run. '
        + 'It is one-shot.');
}

List<String> summaryOrder = new List<String>();
Map<String, Integer> counts = new Map<String, Integer>();
List<String> notes = new List<String>();

Savepoint sp = Database.setSavepoint();

System.debug(LoggingLevel.INFO, '=== SEED 07 COMMISSION/CONCESSION START (DRY_RUN=' + DRY_RUN + ') ===');

// ===========================================================================
// 1. Document_Checklist__c — KYC/legal document tracking per Booking.
//    Business purpose inferred from field metadata (Document_Type__c /
//    Required_For__c / Status__c / Verified_By__c + Master-Detail to Booking).
//    Modelled as one row per required document per Booking, with a realistic
//    mix of Pending / Received / Verified.
// ===========================================================================
List<Document_Checklist__c> docChecklists = new List<Document_Checklist__c>();
for (Booking__c b : bookings) {
    docChecklists.add(new Document_Checklist__c(Booking__c = b.Id, Document_Type__c = 'PAN',
        Required_For__c = 'All Co-Buyers', Status__c = 'Verified',
        Received_Date__c = RUN_DATE.addDays(-6), Verified_Date__c = RUN_DATE.addDays(-5),
        Verified_By__c = RUNNING_USER, Notes__c = TAG + ' — PAN verified against ITD portal'));
    docChecklists.add(new Document_Checklist__c(Booking__c = b.Id, Document_Type__c = 'Aadhaar-masked',
        Required_For__c = 'All Co-Buyers', Status__c = 'Received',
        Received_Date__c = RUN_DATE.addDays(-4), Notes__c = TAG + ' — masked copy on file'));
    docChecklists.add(new Document_Checklist__c(Booking__c = b.Id, Document_Type__c = 'Address Proof',
        Required_For__c = 'Primary Buyer', Status__c = 'Received',
        Received_Date__c = RUN_DATE.addDays(-4)));
    docChecklists.add(new Document_Checklist__c(Booking__c = b.Id, Document_Type__c = 'Photograph',
        Required_For__c = 'All Co-Buyers', Status__c = 'Pending'));
    docChecklists.add(new Document_Checklist__c(Booking__c = b.Id, Document_Type__c = 'Bank Statement',
        Required_For__c = 'Primary Buyer', Status__c = 'Pending'));
}
// NRI-specific documents on the CP-sourced residential booking's buyer set.
docChecklists.add(new Document_Checklist__c(Booking__c = bkg1.Id, Document_Type__c = 'Passport (NRI)',
    Required_For__c = 'NRI Only', Status__c = 'Waived',
    Notes__c = TAG + ' — resident buyer, NRI document not applicable'));
docChecklists.add(new Document_Checklist__c(Booking__c = bkg1.Id, Document_Type__c = 'Form 15CA',
    Required_For__c = 'NRI Only', Status__c = 'Waived',
    Notes__c = TAG + ' — resident buyer, remittance form not applicable'));
insert docChecklists;
summaryOrder.add('Document_Checklist__c');  counts.put('Document_Checklist__c', docChecklists.size());

// ===========================================================================
// 2. COMMISSION LEDGER (accrued by CommissionService in scripts 04 and 06) + PAYOUT
//    Ledger entries are NOT hand-created — they are whatever the Booking /
//    Agreement / Registration milestone accruals produced. The payout block
//    replicates CommissionPayoutBatch.execute()'s grouping and summing logic
//    inline (see KNOWN LIMITATIONS above for why not the batch).
// ===========================================================================
List<Commission_Ledger__c> ledgers = [
    SELECT Id, Name, Booking__c, Channel_Partner__c, Milestone__c, Rate_Pct__c,
           Agreement_Value_Basis__c, Gross_Commission__c, GST_On_Commission__c,
           TDS_On_Commission__c, Status__c, Payout__c
    FROM Commission_Ledger__c
    WHERE Booking__c IN :bookings
    ORDER BY Channel_Partner__c, Name
];
summaryOrder.add('Commission_Ledger__c (read)');  counts.put('Commission_Ledger__c (read)', ledgers.size());
if (ledgers.isEmpty()) {
    notes.add('No Commission_Ledger__c entries accrued in scripts 04/06. Check that the seed rate cards '
        + 'resolved for the (Project x CP_Tier) combinations used — CommissionService skips silently '
        + '(WARN log) when no active rate card matches.');
}

Map<Id, List<Commission_Ledger__c>> entriesByCp = new Map<Id, List<Commission_Ledger__c>>();
for (Commission_Ledger__c c : ledgers) {
    if (c.Payout__c != null) continue;
    if (c.Status__c != 'Accrued' && c.Status__c != 'Approved') continue;
    if (!entriesByCp.containsKey(c.Channel_Partner__c)) {
        entriesByCp.put(c.Channel_Partner__c, new List<Commission_Ledger__c>());
    }
    entriesByCp.get(c.Channel_Partner__c).add(c);
}

List<Commission_Payout__c> payouts = new List<Commission_Payout__c>();
Map<Id, Commission_Payout__c> payoutByCp = new Map<Id, Commission_Payout__c>();
if (!entriesByCp.isEmpty()) {
    String payoutMonth = String.valueOf(RUN_DATE.year()) + '-' + String.valueOf(RUN_DATE.month()).leftPad(2, '0');
    for (Id cpId : entriesByCp.keySet()) {
        Decimal grossSum = 0, gstSum = 0, tdsSum = 0;
        for (Commission_Ledger__c c : entriesByCp.get(cpId)) {
            grossSum += (c.Gross_Commission__c   == null) ? 0 : c.Gross_Commission__c;
            gstSum   += (c.GST_On_Commission__c  == null) ? 0 : c.GST_On_Commission__c;
            tdsSum   += (c.TDS_On_Commission__c  == null) ? 0 : c.TDS_On_Commission__c;
        }
        Commission_Payout__c p = new Commission_Payout__c(
            Channel_Partner__c = cpId,
            Payout_Month__c = payoutMonth,
            Status__c = 'Draft',
            Entry_Count__c = entriesByCp.get(cpId).size(),
            Gross_Commission__c = grossSum,
            GST_Total__c = gstSum,
            TDS_Total__c = tdsSum
        );
        payouts.add(p);
        payoutByCp.put(cpId, p);
    }
    insert payouts;

    List<Commission_Ledger__c> ledgersToLink = new List<Commission_Ledger__c>();
    for (Id cpId : entriesByCp.keySet()) {
        for (Commission_Ledger__c c : entriesByCp.get(cpId)) {
            ledgersToLink.add(new Commission_Ledger__c(Id = c.Id, Payout__c = payoutByCp.get(cpId).Id));
        }
    }
    update ledgersToLink;

    // Advance one payout to Approved so the CP portal's payout list isn't all Draft.
    update new Commission_Payout__c(Id = payouts[0].Id, Status__c = 'Approved',
        Approval_Date__c = RUN_DATE, Payment_UTR__c = 'UTR' + TAG + '9900112233');
}
summaryOrder.add('Commission_Payout__c');  counts.put('Commission_Payout__c', payouts.size());

// ===========================================================================
// 3. NOTIFICATION PREFERENCES
//    Business purpose inferred from field metadata (Account__c / Contact__c
//    lookups + Email/SMS/WhatsApp/Voice opt-in checkboxes + a DND time window) —
//    no epic doc specifies who owns these rows or whether one-per-Contact is the
//    intended cardinality. Modelled as one row per buyer Contact, carrying both
//    the Contact and its parent Account, with a varied opt-in mix; CPs get one
//    each too, since they receive payout/ledger notifications.
// ===========================================================================
List<Notification_Preference__c> notifPrefs = new List<Notification_Preference__c>();
Integer npIdx = 0;
for (Contact c : buyerContacts) {
    Boolean optOutMarketingish = Math.mod(npIdx, 3) == 0;
    notifPrefs.add(new Notification_Preference__c(
        Contact__c = c.Id,
        Account__c = c.AccountId,
        Email_Optin__c = true,
        SMS_Optin__c = !optOutMarketingish,
        WhatsApp_Optin__c = Math.mod(npIdx, 2) == 0,
        Voice_Optin__c = optOutMarketingish,
        DND_Start__c = Time.newInstance(21, 30, 0, 0),
        DND_End__c = Time.newInstance(9, 0, 0, 0)
    ));
    npIdx++;
}
for (Contact c : cpContacts) {
    notifPrefs.add(new Notification_Preference__c(
        Contact__c = c.Id, Account__c = c.AccountId,
        Email_Optin__c = true, SMS_Optin__c = true,
        WhatsApp_Optin__c = true, Voice_Optin__c = false,
        DND_Start__c = Time.newInstance(22, 0, 0, 0),
        DND_End__c = Time.newInstance(8, 0, 0, 0)
    ));
}
insert notifPrefs;
summaryOrder.add('Notification_Preference__c');  counts.put('Notification_Preference__c', notifPrefs.size());

// ===========================================================================
// 4. CONCESSION REQUESTS
//    Requested_Pct__c drives which approval tier the record lands in:
//      <= 5%  -> PSM_Tier        (psm.prk)
//      >  5%  -> Sales_Head_Tier (saleshead), because PSM_Tier's step entry
//                criteria is not met and ifCriteriaNotMet = GotoNextStep.
// ===========================================================================
List<Concession_Request__c> concessions = new List<Concession_Request__c>{
    new Concession_Request__c(Opportunity__c = oppNego.Id, Unit__c = unitNego.Id,
        Requested_Pct__c = 3, Requested_Amount__c = 312000, Status__c = 'Draft',
        Requested_By__c = RUNNING_USER, Expiry_Date__c = RUN_DATE.addDays(30),
        Justification__c = TAG + ' — competing quote from a neighbouring project at 3% lower '
            + 'effective rate. Buyer is ready to pay token this week.'),
    new Concession_Request__c(Opportunity__c = oppEoi.Id, Unit__c = unitEoi.Id,
        Requested_Pct__c = 7.5, Requested_Amount__c = 990000, Status__c = 'Draft',
        Requested_By__c = RUNNING_USER, Expiry_Date__c = RUN_DATE.addDays(21),
        Justification__c = TAG + ' — NRI investor buying two units; requesting a portfolio '
            + 'discount above the standard PSM band.'),
    new Concession_Request__c(Opportunity__c = oppTokenCom.Id, Unit__c = unitTokenCm.Id,
        Requested_Pct__c = 4, Requested_Amount__c = 632000, Status__c = 'Draft',
        Requested_By__c = RUNNING_USER, Expiry_Date__c = RUN_DATE.addDays(45),
        Justification__c = TAG + ' — retail buyer committing to a 9-year lock-in; left in Draft '
            + 'deliberately so the "not yet submitted" state is represented.')
};
insert concessions;
summaryOrder.add('Concession_Request__c');  counts.put('Concession_Request__c', concessions.size());

// ===========================================================================
// 5. APPROVAL SUBMISSIONS (last — each independently try/catch'd)
// ===========================================================================
Integer approvalsSubmitted = 0;

if (SUBMIT_APPROVALS) {
    // 5a. Concession_Approval — one into each tier.
    Map<Id, String> concessionTier = new Map<Id, String>{
        concessions[0].Id => 'PSM_Tier (3%)',
        concessions[1].Id => 'Sales_Head_Tier (7.5%)'
    };
    for (Id crId : concessionTier.keySet()) {
        try {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(crId);
            req.setProcessDefinitionNameOrId('Concession_Approval');
            req.setSkipEntryCriteria(false);
            req.setComments(TAG + ' — submitted by the seed-test-data series to populate '
                + concessionTier.get(crId) + ' approval history.');
            Approval.ProcessResult res = Approval.process(req, false);
            if (res.isSuccess()) {
                approvalsSubmitted++;
            } else {
                notes.add('Concession approval submission returned errors for ' + crId + ': '
                    + res.getErrors()[0].getMessage());
            }
        } catch (Exception e) {
            notes.add('Concession approval submission threw for ' + crId + ' ('
                + concessionTier.get(crId) + '). Most likely the tier approver user '
                + '(psm.prk@recrm-demo.invalid / saleshead@recrm-demo.invalid) is missing or '
                + 'inactive on this org. Reason: ' + e.getMessage());
        }
    }

    // 5b. CP_Registration_Approval — the two CPs still at 'Pending Approval'.
    for (Account cp : new List<Account>{ cpSunridge, cpKaveri }) {
        try {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(cp.Id);
            req.setProcessDefinitionNameOrId('CP_Registration_Approval');
            req.setSkipEntryCriteria(false);
            req.setComments(TAG + ' — CP empanelment submitted by the seed-test-data series.');
            Approval.ProcessResult res = Approval.process(req, false);
            if (res.isSuccess()) {
                approvalsSubmitted++;
            } else {
                notes.add('CP registration approval returned errors for ' + cp.Name + ': '
                    + res.getErrors()[0].getMessage());
            }
        } catch (Exception e) {
            notes.add('CP registration approval threw for ' + cp.Name + '. The approver named in '
                + 'CP_Registration_Approval may not exist on this org. Reason: ' + e.getMessage());
        }
    }
} else {
    notes.add('SUBMIT_APPROVALS = false — no records were submitted for approval. '
        + 'Concession_Request__c rows remain in Draft and the two pending CP Accounts remain '
        + 'at CP_Status__c = Pending Approval.');
}
summaryOrder.add('Approval submissions');  counts.put('Approval submissions', approvalsSubmitted);

// ===========================================================================
// SUMMARY — computed BEFORE any rollback, since a rollback invalidates Ids.
// ===========================================================================
Integer totalRecords = 0;
for (String k : summaryOrder) {
    if (k != 'Approval submissions' && k != 'Commission_Ledger__c (read)') {
        totalRecords += counts.get(k);
    }
}

System.debug(LoggingLevel.INFO, '');
System.debug(LoggingLevel.INFO, '=== SEED 07 COMMISSION/CONCESSION SUMMARY =====');
System.debug(LoggingLevel.INFO, 'Mode: ' + (DRY_RUN ? 'DRY RUN (everything rolled back)' : 'COMMITTED'));
for (String k : summaryOrder) {
    System.debug(LoggingLevel.INFO, '  ' + k.rightPad(34, ' ') + ' : ' + counts.get(k));
}
System.debug(LoggingLevel.INFO, '  TOTAL NEW RECORDS'.rightPad(36, ' ') + ' : ' + totalRecords);
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
        'DRY RUN COMPLETE — checklists, payouts, preferences, concessions and approval submissions all '
        + 'executed, then were rolled back. Set DRY_RUN = false and re-run to commit. '
        + 'That completes the seed-test-data series.');
} else {
    System.debug(LoggingLevel.INFO,
        'SEED 07 COMMITTED — the seed-test-data series is complete. Clean-up handle: Account/Project/'
        + 'Payment Plan names begin with "' + TAG + '", Project Codes are ' + PROJ_A + '/' + PROJ_B + '.');
}
