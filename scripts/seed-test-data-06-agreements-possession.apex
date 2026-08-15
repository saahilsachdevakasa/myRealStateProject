/**
 * ============================================================================
 * seed-test-data-06-agreements-possession.apex — SCRIPT 6 OF 7
 * ============================================================================
 *
 * DEPENDS ON: scripts 01-05 having been COMMITTED (DRY_RUN = false).
 *   Re-queried at the top of this file:
 *     Booking__c — bkg1 (unit ZSA-T01-F02-U002) and bkg2 (unit ZSB-B01-F01-S001),
 *                  keyed on Unit__r.Name. bkg3 (ZSA-T01-F03-U004) deliberately
 *                  gets no Agreement — it stays Confirmed.
 *     Contact    — conRajesh, by Email, for the possession handover.
 *
 * PRODUCES:
 *   Agreement__c x2  — bkg1's goes Not Started -> Signed -> Executed (+ registration);
 *                      bkg2's stops at Signed
 *   Possession__c x1 — bkg1 only, driven through to Handed Over
 *   Snag_Item__c x3  — against that Possession
 *   Commission_Ledger__c rows for the Agreement and Registration milestones, via
 *                      CommissionService (never hand-created; script 07 reads them)
 *
 * HOW TO RUN
 *   sf apex run --file scripts/seed-test-data-06-agreements-possession.apex --target-org re-crm-sdo
 *   Dry-run first (DRY_RUN = true), then commit, THEN run script 07.
 *
 * AUTOMATION THIS SCRIPT DELIBERATELY DRIVES
 *   - AgreementService and PossessionService are called as their real
 *     @InvocableMethods.
 *   - Agreement Signed fires CommissionService.accrueOnAgreementSigned and
 *     AgreementService.onAfterUpdate -> Booking 'Agreement Signed'.
 *   - Agreement Executed + Registration_Date fires accrueOnRegistration and
 *     AgreementService.onAfterUpdate -> Booking 'Registered'.
 *   - Possession -> Handed Over fires PossessionService's after-update sync ->
 *     Booking 'Possessed'.
 *
 * SEQUENCING CONSTRAINTS HONOURED IN THIS FILE
 *   (a) RecursionGuard is TRANSACTION-scoped and starts clean in this script's own
 *       transaction, so no reset is needed before the FIRST Agreement update. But
 *       there are TWO sequential Agreement__c updates here (Signed, then Executed),
 *       and each needs its after-update handler to fire, so
 *       RecursionGuard.reset('Agreement_afterUpdate') between them is load-bearing:
 *       without it the Registration commission milestone never accrues and Booking 1
 *       never reaches 'Registered', which in turn blocks PossessionService.
 *       There is exactly ONE Possession__c update, so 'Possession_afterUpdate'
 *       fires cleanly without a reset.
 *       Note the Booking guard is deliberately NOT reset between the Agreement
 *       transitions — that matches the original single-file script's behaviour;
 *       the Booking status writes happen inside AgreementService, not through the
 *       Booking after-update handler.
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

final String UNIT_BKG1 = PROJ_A + '-T01-F02-U002';   // residential, CP Horizon — goes all the way
final String UNIT_BKG2 = PROJ_B + '-B01-F01-S001';   // commercial,  CP Beacon — stops at Signed

// ===========================================================================
// PRE-FLIGHT — re-query dependencies; abort loudly if absent
// ===========================================================================
Map<String, Booking__c> bookingByUnitName = new Map<String, Booking__c>();
for (Booking__c b : [
    SELECT Id, Name, Unit__r.Name, Booking_Status__c, Payment_Plan__c
    FROM Booking__c WHERE Unit__r.Name IN (:UNIT_BKG1, :UNIT_BKG2)
]) {
    bookingByUnitName.put(b.Unit__r.Name, b);
}
Booking__c bkg1 = bookingByUnitName.get(UNIT_BKG1);
Booking__c bkg2 = bookingByUnitName.get(UNIT_BKG2);
if (bkg1 == null || bkg2 == null) {
    throw new IllegalArgumentException(
        'ABORT: seed Bookings on ' + UNIT_BKG1 + ' / ' + UNIT_BKG2 + ' not found. Commit script 04 first.');
}
if (bkg1.Payment_Plan__c == null) {
    throw new IllegalArgumentException(
        'ABORT: the seed Bookings carry no Payment Plan, so script 05 has not been committed. '
        + 'Run scripts/seed-test-data-05-bookings.apex with DRY_RUN = false first — the possession '
        + 'block below depends on the receipts it creates (All_Dues_Cleared__c).');
}
if ([SELECT COUNT() FROM Agreement__c WHERE Booking__c IN (:bkg1.Id, :bkg2.Id)] > 0) {
    throw new IllegalArgumentException(
        'ABORT: the seed Bookings already have Agreements — this script has already run. It is one-shot.');
}

List<Contact> rajeshRows = [
    SELECT Id FROM Contact WHERE Email = 'rajesh.kulkarni.seed@recrm-demo.invalid' LIMIT 1
];
if (rajeshRows.isEmpty()) {
    throw new IllegalArgumentException('ABORT: seed Contact rajesh.kulkarni.seed@recrm-demo.invalid '
        + 'not found. Commit script 02 first.');
}
Contact conRajesh = rajeshRows[0];

List<String> summaryOrder = new List<String>();
Map<String, Integer> counts = new Map<String, Integer>();
List<String> notes = new List<String>();

Savepoint sp = Database.setSavepoint();

System.debug(LoggingLevel.INFO, '=== SEED 06 AGREEMENTS/POSSESSION START (DRY_RUN=' + DRY_RUN + ') ===');

// ===========================================================================
// 1. AGREEMENTS — created via AgreementService (-> Booking 'Agreement Pending')
// ===========================================================================
List<AgreementService.AgreementRequest> agrReqs = new List<AgreementService.AgreementRequest>();
for (Booking__c b : new List<Booking__c>{ bkg1, bkg2 }) {
    AgreementService.AgreementRequest req = new AgreementService.AgreementRequest();
    req.bookingId = b.Id;
    agrReqs.add(req);
}
List<Id> agreementIds = AgreementService.createAgreements(agrReqs);
summaryOrder.add('Agreement__c');  counts.put('Agreement__c', agreementIds.size());

// Map agreement -> booking explicitly rather than relying on the returned list's
// ordering, so agr1 is unambiguously bkg1's.
Id agr1 = null;
Id agr2 = null;
for (Agreement__c a : [SELECT Id, Booking__c FROM Agreement__c WHERE Id IN :agreementIds]) {
    if (a.Booking__c == bkg1.Id) agr1 = a.Id;
    if (a.Booking__c == bkg2.Id) agr2 = a.Id;
}
if (agr1 == null) {
    notes.add('No Agreement was created for the residential Booking (' + UNIT_BKG1 + '). The '
        + 'Registration / Possession chain below will be skipped.');
}

if (!agreementIds.isEmpty()) {
    // Transition 1: Not Started -> Signed. Fires CommissionService.accrueOnAgreementSigned
    // for the CP-sourced bookings, and AgreementService.onAfterUpdate -> 'Agreement Signed'.
    List<Agreement__c> toSign = new List<Agreement__c>();
    for (Id aid : agreementIds) {
        toSign.add(new Agreement__c(Id = aid, Status__c = 'Signed',
            Draft_Generated_Date__c = RUN_DATE.addDays(-12),
            Sent_Date__c = DateTime.now().addDays(-10),
            Agreement_Date__c = RUN_DATE.addDays(-8),
            Signed_Date__c = RUN_DATE.addDays(-8),
            ESign_Provider__c = 'Stub', ESign_Status__c = 'Completed',
            ESign_Envelope_Id__c = 'STUB-ENV-' + TAG + '-' + String.valueOf(aid).right(6)));
    }
    update toSign;

    // Constraint (a): the update above consumed 'Agreement_afterUpdate'. Without this
    // reset, the Registration milestone never accrues and Booking 1 never reaches
    // 'Registered' (which in turn blocks PossessionService).
    RecursionGuard.reset('Agreement_afterUpdate');

    // Transition 2: Signed -> Executed + Registration_Date. Fires accrueOnRegistration
    // and AgreementService.onAfterUpdate -> Booking 'Registered'.
    if (agr1 != null) {
        update new Agreement__c(Id = agr1, Status__c = 'Executed',
            Registration_Date__c = RUN_DATE.addDays(-3),
            Registration_Number__c = 'PNE-1-' + TAG + '-00417',
            Sub_Registrar__c = 'Haveli No. 1, Pune',
            Stamp_Duty_Payable__c = 591000,
            Registration_Fees_Payable__c = 30000,
            Executed_Copy_Id__c = 'SEEDDOC-EXEC-001');
    }
}

// ===========================================================================
// 2. POSSESSION — for the fully-registered Booking only.
// ===========================================================================
List<Id> possessionIds = new List<Id>();
if (agr1 != null) {
    PossessionService.PossessionRequest pr = new PossessionService.PossessionRequest();
    pr.bookingId = bkg1.Id;
    possessionIds = PossessionService.createPossessions(
        new List<PossessionService.PossessionRequest>{ pr });   // -> Booking 'Possession Ready'
}
summaryOrder.add('Possession__c');  counts.put('Possession__c', possessionIds.size());

// ===========================================================================
// 3. SNAG ITEMS + handover
// ===========================================================================
List<Snag_Item__c> snags = new List<Snag_Item__c>();
if (!possessionIds.isEmpty()) {
    Id posId = possessionIds[0];
    snags.add(new Snag_Item__c(Possession__c = posId, Description__c = TAG + ' — Master bedroom window seal leaking',
        Category__c = 'Carpentry', Severity__c = 'Major', Status__c = 'Resolved',
        Reported_Date__c = RUN_DATE.addDays(-14), Target_Date__c = RUN_DATE.addDays(-7),
        Resolved_Date__c = RUN_DATE.addDays(-8), Assigned_To__c = RUNNING_USER));
    snags.add(new Snag_Item__c(Possession__c = posId, Description__c = TAG + ' — Kitchen sink slow drainage',
        Category__c = 'Plumbing', Severity__c = 'Minor', Status__c = 'Verified',
        Reported_Date__c = RUN_DATE.addDays(-14), Target_Date__c = RUN_DATE.addDays(-7),
        Resolved_Date__c = RUN_DATE.addDays(-9), Assigned_To__c = RUNNING_USER));
    snags.add(new Snag_Item__c(Possession__c = posId, Description__c = TAG + ' — Living room switchboard loose',
        Category__c = 'Electrical', Severity__c = 'Minor', Status__c = 'Resolved',
        Reported_Date__c = RUN_DATE.addDays(-13), Target_Date__c = RUN_DATE.addDays(-6),
        Resolved_Date__c = RUN_DATE.addDays(-7), Assigned_To__c = RUNNING_USER));
    insert snags;

    // Single possession update straight through to Handed Over — one update statement,
    // so 'Possession_afterUpdate' fires cleanly and syncs Booking 1 to 'Possessed'.
    update new Possession__c(Id = posId, Status__c = 'Handed Over',
        Offered_Date__c = RUN_DATE.addDays(-16),
        Snag_Inspection_Date__c = RUN_DATE.addDays(-14),
        Snag_Target_Date__c = RUN_DATE.addDays(-7),
        NOC_Issued__c = true, NOC_Date__c = RUN_DATE.addDays(-2),
        Keys_Handed_Date__c = RUN_DATE.addDays(-1),
        Handed_Over_By__c = RUNNING_USER,
        Handed_Over_To__c = conRajesh.Id,
        Handover_Notes__c = TAG + ' — keys handed over; all snags closed; NOC issued.');
}
summaryOrder.add('Snag_Item__c');  counts.put('Snag_Item__c', snags.size());

// ===========================================================================
// SUMMARY — computed BEFORE any rollback, since a rollback invalidates Ids.
// ===========================================================================
Integer totalRecords = 0;
for (String k : summaryOrder) totalRecords += counts.get(k);

System.debug(LoggingLevel.INFO, '');
System.debug(LoggingLevel.INFO, '== SEED 06 AGREEMENTS/POSSESSION SUMMARY ======');
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
System.debug(LoggingLevel.INFO, '-----------------------------------------------');
for (Booking__c b : [
    SELECT Name, Booking_Status__c, Unit__r.Name FROM Booking__c
    WHERE Id IN (:bkg1.Id, :bkg2.Id) ORDER BY Name
]) {
    System.debug(LoggingLevel.INFO, 'BOOKING ' + b.Name + ' | unit=' + b.Unit__r.Name
        + ' | status=' + b.Booking_Status__c);
}
System.debug(LoggingLevel.INFO, '===============================================');

// ===========================================================================
// ROLLBACK (dry run only)
// ===========================================================================
if (DRY_RUN) {
    Database.rollback(sp);
    System.debug(LoggingLevel.INFO,
        'DRY RUN COMPLETE — agreements, the sign/execute transitions, possession and snags all executed '
        + 'and passed validation, then were rolled back. Set DRY_RUN = false and re-run to commit, THEN '
        + 'move on to scripts/seed-test-data-07-commission-concession.apex.');
} else {
    System.debug(LoggingLevel.INFO,
        'SEED 06 COMMITTED. Next: scripts/seed-test-data-07-commission-concession.apex.');
}
