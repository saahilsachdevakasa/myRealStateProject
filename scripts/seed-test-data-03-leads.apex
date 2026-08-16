/**
 * ============================================================================
 * seed-test-data-03-leads.apex — SCRIPT 3 OF 7
 * ============================================================================
 *
 * DEPENDS ON: scripts 01 and 02 having been COMMITTED (DRY_RUN = false).
 *   Re-queried at the top of this file (no in-memory state survives a
 *   transaction boundary):
 *     Project__c — by Project_Code__c IN ('ZSA','ZSB')
 *     Account    — CP + Buyer/Corporate, by their 'SEED ...' Names
 *     Contact    — by their '<first>.<last>.seed@recrm-demo.invalid' Emails
 *
 * PRODUCES (re-queryable by later scripts):
 *   Lead x7 — greppable via External_Lead_Id__c LIKE 'SEED-%'; individually
 *             identified by their deterministic Email addresses (script 04
 *             re-queries leadGaurav and leadKavya that way for Site Visits).
 *             3 of them are converted.
 *   Opportunity x3 (created by lead conversion, normalised here to their target
 *             record type / stage / project). Nothing downstream references
 *             these three, which is why the conversion and its normalising
 *             update can live in a script of their own.
 *
 * HOW TO RUN
 *   sf apex run --file scripts/seed-test-data-03-leads.apex --target-org re-crm-sdo
 *   Dry-run first (DRY_RUN = true), then commit, THEN run script 04.
 *   See script 01's header for why the series cannot be dry-run end-to-end first.
 *
 * SEQUENCING CONSTRAINTS HONOURED IN THIS FILE
 *   (a) RecursionGuard is TRANSACTION-scoped. Database.convertLead below may
 *       itself issue an Opportunity update, consuming 'Opportunity_afterUpdate',
 *       so the key is reset before the normalising update — otherwise
 *       OpportunityTrigger silently skips those three records.
 *   (d) The four Opportunity validation rules are ISCHANGED(StageName)-scoped.
 *       The normalising update below is a genuine stage change, so 'Qualified' /
 *       'Site Visit Done' are exercised for real. (Require_Unit_By_Negotiation
 *       only bites from Negotiation onwards, so no Primary Unit is needed here.)
 *   (g) Salesforce refuses to convert a QUEUE-OWNED Lead ('Converted objects can
 *       only be owned by users'). RECRM_Lead_Assignment's first rule entry routes
 *       every Source_Channel__c = 'CP' Lead to CP_Manager_Queue, which covers two
 *       of the three conversion targets here. Section 1b re-owns any queue-owned
 *       conversion target to a User immediately before section 2 converts it.
 * ============================================================================
 */

// ===========================================================================
// CONFIG — must match the other scripts in the series
// ===========================================================================
Boolean DRY_RUN = false;   // true = roll everything back at the end

final String TAG    = 'SEED';
final String PROJ_A = 'ZSA';
final String PROJ_B = 'ZSB';

final Date RUN_DATE = Date.today();

// Owner handed the queue-routed Leads immediately before conversion (section 1b).
// saleshead@ rather than the queue's own member cpmgr@, for three reasons:
//   1. It is RECRM_Lead_Assignment's own catch-all target, so it is the rule's
//      designated human, not an arbitrary pick — and it already owns Suresh below.
//   2. RECRM_CP_Manager grants Opportunity Read only (no Create/Edit), so cpmgr@
//      cannot own a converted Opportunity usefully and may not be a legal owner at
//      conversion time. RECRM_Sales_Head grants full Opportunity CRUD.
//   3. It matches the real motion: a CP Manager works the queue, then hands the
//      Lead to sales to convert. Converting is a sales action.
final String CONV_OWNER_USERNAME = 'saleshead@recrm-demo.invalid';

// ===========================================================================
// PRE-FLIGHT — re-query what scripts 01/02 created; abort loudly if absent
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

Map<String, Account> accByName = new Map<String, Account>();
String seedNamePrefix = TAG + ' %';
for (Account a : [SELECT Id, Name, CP_Status__c FROM Account WHERE Name LIKE :seedNamePrefix]) {
    accByName.put(a.Name, a);
}
Account cpHorizon   = accByName.get(TAG + ' Horizon Realty LLP');
Account cpBeacon    = accByName.get(TAG + ' Beacon Property Advisors');
Account accKulkarni = accByName.get(TAG + ' Rajesh Kulkarni');
Account accMenon    = accByName.get(TAG + ' Arun Menon (NRI)');
Account accVikram   = accByName.get(TAG + ' Vikram Enterprises Pvt Ltd');
for (Account a : new List<Account>{ cpHorizon, cpBeacon, accKulkarni, accMenon, accVikram }) {
    if (a == null) {
        throw new IllegalArgumentException('ABORT: seed Accounts missing. Commit script 02 first.');
    }
}

Map<String, Contact> conByEmail = new Map<String, Contact>();
for (Contact c : [SELECT Id, Email FROM Contact WHERE Email LIKE '%.seed@recrm-demo.invalid']) {
    conByEmail.put(c.Email, c);
}
Contact conRajesh = conByEmail.get('rajesh.kulkarni.seed@recrm-demo.invalid');
Contact conArun   = conByEmail.get('arun.menon.seed@recrm-demo.invalid');
Contact conVikram = conByEmail.get('vikram.shah.seed@recrm-demo.invalid');
if (conRajesh == null || conArun == null || conVikram == null) {
    throw new IllegalArgumentException('ABORT: seed Contacts missing. Commit script 02 first.');
}

if ([SELECT COUNT() FROM Lead WHERE Email = 'anita.deshpande.seed@recrm-demo.invalid'] > 0) {
    throw new IllegalArgumentException(
        'ABORT: seed Leads already present. This script is one-shot (External_Lead_Id__c is unique '
        + 'and three of these Leads get converted). Delete the previous seed data before re-running.');
}

Id rtLeadRes = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Residential_Lead').getRecordTypeId();
Id rtLeadCom = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('Commercial_Lead').getRecordTypeId();
Id rtOppRes  = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Pre_sales_Residential').getRecordTypeId();
Id rtOppCom  = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Pre_sales_Commercial').getRecordTypeId();

List<String> summaryOrder = new List<String>();
Map<String, Integer> counts = new Map<String, Integer>();
List<String> notes = new List<String>();

Database.DMLOptions dupAllow = new Database.DMLOptions();
dupAllow.DuplicateRuleHeader.allowSave = true;

Savepoint sp = Database.setSavepoint();

System.debug(LoggingLevel.INFO, '=== SEED 03 LEADS START (DRY_RUN=' + DRY_RUN + ') ===');

// ===========================================================================
// 1. LEADS
//    Inserted with the default assignment rule engaged so RECRM_Lead_Assignment
//    genuinely routes them (CP-sourced -> CP_Manager_Queue; project-aware
//    otherwise, via the Project_Code_Text__c formula field). Falls back to a
//    plain insert if the rule can't be applied on this org.
//    External_Lead_Id__c is unique, hence the timestamped token; the leads stay
//    greppable via External_Lead_Id__c LIKE 'SEED-%' and individually
//    addressable by their fixed Email values.
// ===========================================================================
String leadToken = TAG + '-' + String.valueOf(DateTime.now().getTime());

List<Lead> leads = new List<Lead>{
    new Lead(RecordTypeId = rtLeadRes, FirstName = 'Anita', LastName = 'Deshpande-' + TAG,
        Company = TAG + ' Self', Email = 'anita.deshpande.seed@recrm-demo.invalid', Phone = '9820300401',
        Status = 'New', Source_Channel__c = 'CP', Source_CP__c = cpHorizon.Id,
        Project_Interest__c = projA.Id, Budget_Min__c = 9000000, Budget_Max__c = 12000000,
        Unit_Type_Preference__c = '3BHK;4BHK', Urgency__c = 'Immediate', Preferred_Channel__c = 'WhatsApp',
        Location_Preference__c = 'Baner / Balewadi', NRI_Flag__c = false, Lead_Score__c = 'Hot',
        Lead_Score_Rationale__c = 'Budget matches 3BHK inventory; immediate urgency; CP-referred.',
        External_Lead_Id__c = leadToken + '-01'),
    new Lead(RecordTypeId = rtLeadRes, FirstName = 'Gaurav', LastName = 'Sethi-' + TAG,
        Company = TAG + ' Self', Email = 'gaurav.sethi.seed@recrm-demo.invalid', Phone = '9820300402',
        Status = 'Working', Source_Channel__c = 'Walk-in',
        Project_Interest__c = projA.Id, Budget_Min__c = 6500000, Budget_Max__c = 8000000,
        Unit_Type_Preference__c = '2BHK;3BHK', Urgency__c = '3 months', Preferred_Channel__c = 'Phone',
        Location_Preference__c = 'Baner', NRI_Flag__c = false, Lead_Score__c = 'Warm',
        External_Lead_Id__c = leadToken + '-02'),
    new Lead(RecordTypeId = rtLeadRes, FirstName = 'Kavya', LastName = 'Nair-' + TAG,
        Company = TAG + ' Self', Email = 'kavya.nair.seed@recrm-demo.invalid', Phone = '9820300403',
        Status = 'Working', Source_Channel__c = 'Aggregator-99acres', Aggregator_Name__c = '99acres',
        Project_Interest__c = projA.Id, Budget_Min__c = 5500000, Budget_Max__c = 7000000,
        Unit_Type_Preference__c = '2BHK', Urgency__c = '6 months', Preferred_Channel__c = 'Email',
        NRI_Flag__c = false, Lead_Score__c = 'Warm', External_Lead_Id__c = leadToken + '-03'),
    new Lead(RecordTypeId = rtLeadRes, FirstName = 'Imran', LastName = 'Qureshi-' + TAG,
        Company = TAG + ' Self', Email = 'imran.qureshi.seed@recrm-demo.invalid', Phone = '971502223344',
        Status = 'Qualified', Source_Channel__c = 'CP', Source_CP__c = cpBeacon.Id,
        Project_Interest__c = projA.Id, Budget_Min__c = 11000000, Budget_Max__c = 14000000,
        Unit_Type_Preference__c = '4BHK', Urgency__c = 'Immediate', Preferred_Channel__c = 'WhatsApp',
        NRI_Flag__c = true, Lead_Score__c = 'Hot',
        Lead_Score_Rationale__c = 'NRI investor, top-of-band budget, CP-referred, ready to transact.',
        External_Lead_Id__c = leadToken + '-04'),
    new Lead(RecordTypeId = rtLeadRes, FirstName = 'Pooja', LastName = 'Rane-' + TAG,
        Company = TAG + ' Self', Email = 'pooja.rane.seed@recrm-demo.invalid', Phone = '9820300405',
        Status = 'Unqualified', Source_Channel__c = 'Digital',
        Budget_Min__c = 2500000, Budget_Max__c = 3500000,      // below inventory band
        Unit_Type_Preference__c = '1BHK', Urgency__c = 'Exploring', Preferred_Channel__c = 'SMS',
        NRI_Flag__c = false, Lead_Score__c = 'Cold',
        Lead_Score_Rationale__c = 'Budget below the entry price of every live project.',
        External_Lead_Id__c = leadToken + '-05'),
    new Lead(RecordTypeId = rtLeadCom, FirstName = 'Suresh', LastName = 'Pillai-' + TAG,
        Company = TAG + ' Pillai Retail Ventures', Email = 'suresh.pillai.seed@recrm-demo.invalid',
        Phone = '9820300406', Status = 'Working', Source_Channel__c = 'Referral',
        Project_Interest__c = projB.Id, Budget_Min__c = 12000000, Budget_Max__c = 18000000,
        Unit_Type_Preference__c = 'Shop', Urgency__c = '3 months', Preferred_Channel__c = 'Phone',
        NRI_Flag__c = false, Lead_Score__c = 'Warm', External_Lead_Id__c = leadToken + '-06'),
    new Lead(RecordTypeId = rtLeadCom, FirstName = 'Neha', LastName = 'Agarwal-' + TAG,
        Company = TAG + ' Agarwal F&B Holdings', Email = 'neha.agarwal.seed@recrm-demo.invalid',
        Phone = '9820300407', Status = 'New', Source_Channel__c = 'Walk-in',
        Project_Interest__c = projB.Id, Budget_Min__c = 15000000, Budget_Max__c = 22000000,
        Unit_Type_Preference__c = 'Shop;Office', Urgency__c = 'Immediate', Preferred_Channel__c = 'Email',
        NRI_Flag__c = false, Lead_Score__c = 'Hot', External_Lead_Id__c = leadToken + '-07')
};

Database.DMLOptions leadDml = new Database.DMLOptions();
leadDml.assignmentRuleHeader.useDefaultRule = true;
leadDml.DuplicateRuleHeader.allowSave = true;
Boolean assignmentRulesApplied = true;
try {
    Database.insert(leads, leadDml);
} catch (Exception e) {
    assignmentRulesApplied = false;
    notes.add('Lead assignment rule could not be applied (falling back to plain insert). '
        + 'Usually means a routing target user/queue in RECRM_Lead_Assignment is inactive on this org. '
        + 'Reason: ' + e.getMessage());
    Database.insert(leads, dupAllow);
}
summaryOrder.add('Lead');  counts.put('Lead', leads.size());

Lead leadAnita  = leads[0];
Lead leadImran  = leads[3];
Lead leadSuresh = leads[5];

// ===========================================================================
// 1b. RE-OWN QUEUE-ROUTED CONVERSION TARGETS  (constraint (g))
//     RECRM_Lead_Assignment's first rule entry sends every Source_Channel__c =
//     'CP' Lead to CP_Manager_Queue (assignedToType = Queue). Anita (Horizon)
//     and Imran (Beacon) are both CP-sourced, so both land on the queue; Suresh
//     is 'Referral' and falls through to the catch-all entry, which assigns a
//     User (saleshead@) — which is why only he used to convert.
//     Database.convertLead rejects a queue-owned Lead outright, and with
//     allOrNone = false in section 2 that rejection was absorbed as a warning,
//     leaving 1 Opportunity where the seed intends 3.
//
//     The queue routing is deliberate business logic and is NOT disabled here:
//     the Leads are genuinely routed to the queue on insert, then handed to a
//     User just before conversion — exactly what happens in the UI when someone
//     picks a Lead up out of the queue and converts it.
//
//     The test is "is the owner a Group?", not "is this Anita or Imran", so the
//     block keeps working if the assignment rule's routing changes later.
//     OwnerId must be re-queried: assignment rules run server-side and do not
//     write back to the in-memory sObjects from the insert above.
// ===========================================================================
List<User> convOwners = [SELECT Id FROM User WHERE Username = :CONV_OWNER_USERNAME AND IsActive = true];
Id convOwnerId;
if (!convOwners.isEmpty()) {
    convOwnerId = convOwners[0].Id;
} else {
    convOwnerId = UserInfo.getUserId();
    notes.add(CONV_OWNER_USERNAME + ' is missing or inactive, so queue-owned Leads were re-owned to '
        + 'the running user in order to convert. Run scripts/seed-demo-users.apex and re-point '
        + 'ownership for demo fidelity.');
}

Set<Id> conversionTargetIds = new Set<Id>{ leadAnita.Id, leadImran.Id, leadSuresh.Id };
List<Lead> leadsToReOwn = new List<Lead>();
for (Lead l : [SELECT Id, OwnerId FROM Lead WHERE Id IN :conversionTargetIds]) {
    // A queue owner is a Group, not a User — that is precisely what convertLead rejects.
    if (l.OwnerId.getSObjectType() != Schema.User.SObjectType) {
        leadsToReOwn.add(new Lead(Id = l.Id, OwnerId = convOwnerId));
    }
}

Integer reOwnedCount = 0;
if (!leadsToReOwn.isEmpty()) {
    // Assignment rules do not re-fire on update unless explicitly requested, so this
    // update sticks and does not bounce the Leads straight back to the queue.
    for (Database.SaveResult sr : Database.update(leadsToReOwn, false)) {
        if (sr.isSuccess()) {
            reOwnedCount++;
        } else {
            notes.add('Could not re-own queue-routed Lead ' + sr.getId() + ' before conversion: '
                + sr.getErrors()[0].getMessage() + ' — its conversion will fail below.');
        }
    }
}
summaryOrder.add('Lead (re-owned pre-convert)');
counts.put('Lead (re-owned pre-convert)', reOwnedCount);

// ===========================================================================
// 2. LEAD CONVERSION — 3 leads converted into the existing Buyer Accounts/Contacts.
//    allOrNone = false so a conversion failure (duplicate rules, org config) is
//    reported rather than aborting the run. Note this tolerance is what let the
//    queue-ownership failure go unnoticed before section 1b existed — always read
//    the warnings block at the end of the run, not just the record counts.
// ===========================================================================
List<Database.LeadConvert> converts = new List<Database.LeadConvert>();

Database.LeadConvert lc1 = new Database.LeadConvert();
lc1.setLeadId(leadAnita.Id);
lc1.setConvertedStatus('Converted');
lc1.setAccountId(accKulkarni.Id);
lc1.setContactId(conRajesh.Id);
lc1.setOpportunityName(TAG + ' Kulkarni — Verdant Heights');
lc1.setDoNotCreateOpportunity(false);
lc1.setOverwriteLeadSource(false);
lc1.setSendNotificationEmail(false);
converts.add(lc1);

Database.LeadConvert lc2 = new Database.LeadConvert();
lc2.setLeadId(leadImran.Id);
lc2.setConvertedStatus('Converted');
lc2.setAccountId(accMenon.Id);
lc2.setContactId(conArun.Id);
lc2.setOpportunityName(TAG + ' Menon — Verdant Heights');
lc2.setDoNotCreateOpportunity(false);
lc2.setOverwriteLeadSource(false);
lc2.setSendNotificationEmail(false);
converts.add(lc2);

Database.LeadConvert lc3 = new Database.LeadConvert();
lc3.setLeadId(leadSuresh.Id);
lc3.setConvertedStatus('Converted');
lc3.setAccountId(accVikram.Id);
lc3.setContactId(conVikram.Id);
lc3.setOpportunityName(TAG + ' Vikram Enterprises — Marina Square');
lc3.setDoNotCreateOpportunity(false);
lc3.setOverwriteLeadSource(false);
lc3.setSendNotificationEmail(false);
converts.add(lc3);

// Target stage / record type / project per conversion, held positionally against
// `converts` so a partial failure can never shift a commercial target onto a
// residential Opportunity.
List<String> convStages   = new List<String>{ 'Qualified', 'Site Visit Done', 'Qualified' };
List<Id>     convRts      = new List<Id>{ rtOppRes, rtOppRes, rtOppCom };
List<Id>     convProjects = new List<Id>{ projA.Id, projA.Id, projB.Id };

List<Opportunity> convertedOppUpdates = new List<Opportunity>();
Integer convertedLeadCount = 0;
List<Database.LeadConvertResult> convResults = Database.convertLead(converts, false);
for (Integer i = 0; i < convResults.size(); i++) {
    Database.LeadConvertResult lcr = convResults[i];
    if (lcr.isSuccess()) {
        convertedLeadCount++;
        if (lcr.getOpportunityId() != null) {
            convertedOppUpdates.add(new Opportunity(
                Id = lcr.getOpportunityId(),
                RecordTypeId = convRts[i],
                StageName = convStages[i],
                Project__c = convProjects[i],
                CloseDate = RUN_DATE.addDays(40 + (i * 10)),
                Budget_Range__c = 'Rs 90L-1.4Cr'
            ));
        }
    } else {
        notes.add('Lead conversion failed for ' + lcr.getLeadId() + ': ' + lcr.getErrors()[0].getMessage());
    }
}
summaryOrder.add('Lead (converted)');  counts.put('Lead (converted)', convertedLeadCount);

// ===========================================================================
// 3. NORMALISE THE CONVERTED OPPORTUNITIES
//    Constraint (a): reset the guard first — Database.convertLead above may
//    already have issued an Opportunity update in this transaction.
// ===========================================================================
if (!convertedOppUpdates.isEmpty()) {
    RecursionGuard.reset('Opportunity_afterUpdate');
    update convertedOppUpdates;
}
summaryOrder.add('Opportunity (from conversion)');
counts.put('Opportunity (from conversion)', convertedOppUpdates.size());

// ===========================================================================
// SUMMARY — computed BEFORE any rollback, since a rollback invalidates Ids.
// ===========================================================================
// Keys that describe an operation on an already-counted record rather than a new
// record — excluded so the total stays a true record count.
Set<String> nonRecordKeys = new Set<String>{ 'Lead (converted)', 'Lead (re-owned pre-convert)' };
Integer totalRecords = 0;
for (String k : summaryOrder) {
    if (!nonRecordKeys.contains(k)) totalRecords += counts.get(k);
}

System.debug(LoggingLevel.INFO, '');
System.debug(LoggingLevel.INFO, '=========== SEED 03 LEADS SUMMARY =============');
System.debug(LoggingLevel.INFO, 'Mode: ' + (DRY_RUN ? 'DRY RUN (everything rolled back)' : 'COMMITTED'));
for (String k : summaryOrder) {
    System.debug(LoggingLevel.INFO, '  ' + k.rightPad(34, ' ') + ' : ' + counts.get(k));
}
System.debug(LoggingLevel.INFO, '  TOTAL RECORDS'.rightPad(36, ' ') + ' : ' + totalRecords);
System.debug(LoggingLevel.INFO, '  Lead assignment rules applied        : ' + assignmentRulesApplied);
System.debug(LoggingLevel.INFO, '  Pre-convert owner for queued Leads   : ' + convOwnerId);
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
        'DRY RUN COMPLETE — leads, assignment routing and the three conversions all executed and passed '
        + 'validation, then were rolled back. Set DRY_RUN = false and re-run to commit, THEN move on to '
        + 'scripts/seed-test-data-04-opportunities.apex.');
} else {
    System.debug(LoggingLevel.INFO,
        'SEED 03 COMMITTED. Next: scripts/seed-test-data-04-opportunities.apex. '
        + 'Clean-up handle: Lead External_Lead_Id__c LIKE \'' + TAG + '-%\'.');
}
