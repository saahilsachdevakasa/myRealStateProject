/**
 * ============================================================================
 * fix-seed-lead-conversion.apex — ONE-OFF REPAIR (not part of the 01..07 series)
 * ============================================================================
 *
 * WHY THIS EXISTS
 *   scripts/seed-test-data-03-leads.apex inserted its 7 Leads with the default
 *   assignment rule engaged. RECRM_Lead_Assignment's FIRST rule entry routes
 *   every Source_Channel__c = 'CP' Lead to CP_Manager_Queue:
 *
 *       <assignedTo>CP_Manager_Queue</assignedTo>
 *       <assignedToType>Queue</assignedToType>
 *       criteria: Lead.Source_Channel__c equals CP
 *
 *   Anita Deshpande-SEED (Source CP = SEED Horizon Realty LLP) and
 *   Imran Qureshi-SEED (Source CP = SEED Beacon Property Advisors) both match,
 *   so both were owned by a Group, not a User. Salesforce refuses to convert a
 *   queue-owned Lead — 'Converted objects can only be owned by users' — and
 *   script 03's Database.convertLead(converts, false) absorbed both failures as
 *   warnings. Only Suresh Pillai-SEED converted; he is Source_Channel__c =
 *   'Referral', which falls through to the catch-all rule entry assigning the
 *   User saleshead@recrm-demo.invalid.
 *
 *   Net effect on the org: 1 Opportunity from conversion where the seed intends 3.
 *   This script converts the two stranded Leads and normalises the two resulting
 *   Opportunities to exactly the record type / stage / project / close date that
 *   script 03 would have applied.
 *
 * SCOPE — deliberately narrow
 *   Touches ONLY the two named Leads and the two Opportunities their conversion
 *   creates. No other object, no other seed script, no metadata. The assignment
 *   rule is READ for diagnosis and left untouched: routing CP-sourced Leads to
 *   the CP Manager Queue is intentional business logic.
 *
 * IDEMPOTENT
 *   Leads already converted are skipped with a note, so a second run is a no-op.
 *
 * HOW TO RUN
 *   Dry-run first (DRY_RUN = true), read the summary, then set DRY_RUN = false:
 *   sf apex run --file scripts/fix-seed-lead-conversion.apex --target-org re-crm-sdo
 *
 * CONSTRAINTS HONOURED
 *   (a) RecursionGuard is TRANSACTION-scoped. Database.convertLead may itself
 *       issue an Opportunity update, consuming 'Opportunity_afterUpdate', so the
 *       key is reset before the normalising update — otherwise OpportunityTrigger
 *       silently skips these records.
 *   (d) The Opportunity validation rules are ISCHANGED(StageName)-scoped. The
 *       normalising update is a genuine stage change; Project__c is populated in
 *       the same update, satisfying Require_Project_After_Qualified. Neither
 *       target stage reaches Negotiation, so Require_Unit_By_Negotiation is not
 *       engaged and no Primary Unit is needed.
 *   (g) Queue-owned Leads cannot be converted — see WHY THIS EXISTS above. Each
 *       Lead is re-owned to a User immediately before conversion.
 * ============================================================================
 */

/**
 * One stranded Lead and the shape script 03 intended its Opportunity to have.
 * Declared first, before any statement: anonymous Apex is reliable about class
 * declarations at the top of the block (the layout scripts/seed-demo-users.apex
 * already uses), less so about them interleaved between statements.
 */
public class ConvSpec {
    public String leadEmail;
    public String accountName;
    public String contactEmail;
    public String oppName;
    public String stage;
    public Integer closeOffsetDays;
    public ConvSpec(String leadEmail, String accountName, String contactEmail,
                    String oppName, String stage, Integer closeOffsetDays) {
        this.leadEmail       = leadEmail;
        this.accountName     = accountName;
        this.contactEmail    = contactEmail;
        this.oppName         = oppName;
        this.stage           = stage;
        this.closeOffsetDays = closeOffsetDays;
    }
}

// ===========================================================================
// CONFIG
// ===========================================================================
Boolean DRY_RUN = false;   // true = roll everything back at the end

final String TAG      = 'SEED';
final String PROJ_A   = 'ZSA';
final Date   RUN_DATE = Date.today();

// The User the stranded Leads are handed to before conversion. saleshead@ rather
// than CP_Manager_Queue's own member cpmgr@, for three reasons:
//   1. It is RECRM_Lead_Assignment's own catch-all target — the rule's designated
//      human, not an arbitrary pick — and it already owns the one seed Lead that
//      DID convert (Suresh), so it is empirically proven to work in this org.
//   2. RECRM_CP_Manager grants Opportunity Read only (no Create/Edit), so cpmgr@
//      cannot own a converted Opportunity usefully and may not even be a legal
//      owner at conversion time. RECRM_Sales_Head grants full Opportunity CRUD.
//   3. It matches the real motion: a CP Manager works the queue, then hands the
//      Lead to sales to convert. Converting is a sales action.
final String CONV_OWNER_USERNAME = 'saleshead@recrm-demo.invalid';

// Values lifted verbatim from script 03's converts[0] and converts[1]. CloseDate
// offsets are relative to RUN_DATE; running this later than the original seed
// shifts the two close dates forward by the same delta, which is immaterial.
List<ConvSpec> specs = new List<ConvSpec>{
    new ConvSpec('anita.deshpande.seed@recrm-demo.invalid', TAG + ' Rajesh Kulkarni',
        'rajesh.kulkarni.seed@recrm-demo.invalid', TAG + ' Kulkarni — Verdant Heights',
        'Qualified', 40),
    new ConvSpec('imran.qureshi.seed@recrm-demo.invalid', TAG + ' Arun Menon (NRI)',
        'arun.menon.seed@recrm-demo.invalid', TAG + ' Menon — Verdant Heights',
        'Site Visit Done', 50)
};

// ===========================================================================
// PRE-FLIGHT — everything referenced must already exist; abort loudly if not
// ===========================================================================
List<String> notes = new List<String>();

Set<String> leadEmails    = new Set<String>();
Set<String> accountNames  = new Set<String>();
Set<String> contactEmails = new Set<String>();
for (ConvSpec s : specs) {
    leadEmails.add(s.leadEmail);
    accountNames.add(s.accountName);
    contactEmails.add(s.contactEmail);
}

Map<String, Lead> leadByEmail = new Map<String, Lead>();
for (Lead l : [SELECT Id, Name, Email, OwnerId, IsConverted FROM Lead WHERE Email IN :leadEmails]) {
    leadByEmail.put(l.Email, l);
}
Map<String, Account> accByName = new Map<String, Account>();
for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :accountNames]) {
    accByName.put(a.Name, a);
}
Map<String, Contact> conByEmail = new Map<String, Contact>();
for (Contact c : [SELECT Id, Email FROM Contact WHERE Email IN :contactEmails]) {
    conByEmail.put(c.Email, c);
}

List<Project__c> projs = [SELECT Id, Project_Code__c FROM Project__c WHERE Project_Code__c = :PROJ_A];
if (projs.isEmpty()) {
    throw new IllegalArgumentException('ABORT: seed Project ' + PROJ_A + ' not found. '
        + 'This script repairs seed data from scripts/seed-test-data-01..03; commit those first.');
}
Id projAId = projs[0].Id;

for (ConvSpec s : specs) {
    if (accByName.get(s.accountName) == null) {
        throw new IllegalArgumentException('ABORT: seed Account "' + s.accountName
            + '" not found. Commit scripts/seed-test-data-02-accounts.apex first.');
    }
    if (conByEmail.get(s.contactEmail) == null) {
        throw new IllegalArgumentException('ABORT: seed Contact ' + s.contactEmail
            + ' not found. Commit scripts/seed-test-data-02-accounts.apex first.');
    }
    if (leadByEmail.get(s.leadEmail) == null) {
        throw new IllegalArgumentException('ABORT: seed Lead ' + s.leadEmail
            + ' not found. Nothing to repair — check that script 03 was committed.');
    }
}

Id rtOppRes = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                    .get('Pre_sales_Residential').getRecordTypeId();

// Resolve the User the queue-owned Leads are handed to before conversion.
List<User> convOwners = [SELECT Id FROM User WHERE Username = :CONV_OWNER_USERNAME AND IsActive = true];
Id convOwnerId;
if (!convOwners.isEmpty()) {
    convOwnerId = convOwners[0].Id;
} else {
    convOwnerId = UserInfo.getUserId();
    notes.add(CONV_OWNER_USERNAME + ' is missing or inactive, so the Leads were re-owned to the '
        + 'running user in order to convert. Run scripts/seed-demo-users.apex and re-point ownership '
        + 'for demo fidelity.');
}

Savepoint sp = Database.setSavepoint();

System.debug(LoggingLevel.INFO, '=== FIX SEED LEAD CONVERSION START (DRY_RUN=' + DRY_RUN + ') ===');

// ===========================================================================
// 1. RE-OWN — the whole point of the repair. Owner must be a User, not a Group.
//    Assignment rules do not re-fire on update unless explicitly requested, so
//    the Leads stay with the User rather than bouncing back to the queue.
// ===========================================================================
List<ConvSpec> pending = new List<ConvSpec>();
List<Lead>     reOwn   = new List<Lead>();

for (ConvSpec s : specs) {
    Lead l = leadByEmail.get(s.leadEmail);
    if (l.IsConverted) {
        notes.add('Lead ' + l.Name + ' (' + s.leadEmail + ') is already converted — skipped. '
            + 'This script is idempotent; nothing to repair for this record.');
        continue;
    }
    pending.add(s);
    if (l.OwnerId.getSObjectType() != Schema.User.SObjectType) {
        reOwn.add(new Lead(Id = l.Id, OwnerId = convOwnerId));
    } else {
        notes.add('Lead ' + l.Name + ' was already User-owned (' + l.OwnerId + '); no re-own needed, '
            + 'converting as-is.');
    }
}

Integer reOwnedCount = 0;
if (!reOwn.isEmpty()) {
    for (Database.SaveResult sr : Database.update(reOwn, false)) {
        if (sr.isSuccess()) {
            reOwnedCount++;
        } else {
            notes.add('Re-own FAILED for Lead ' + sr.getId() + ': ' + sr.getErrors()[0].getMessage()
                + ' — its conversion below will fail too.');
        }
    }
}

// ===========================================================================
// 2. CONVERT — into the existing seed Account/Contact, exactly as script 03 did.
//    allOrNone = false so one failure is reported rather than aborting the other.
//    READ THE WARNINGS BLOCK: this tolerance is what masked the original bug.
// ===========================================================================
Integer convertedCount = 0;
List<Opportunity> oppUpdates = new List<Opportunity>();

if (!pending.isEmpty()) {
    List<Database.LeadConvert> converts = new List<Database.LeadConvert>();
    for (ConvSpec s : pending) {
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(leadByEmail.get(s.leadEmail).Id);
        lc.setConvertedStatus('Converted');
        lc.setAccountId(accByName.get(s.accountName).Id);
        lc.setContactId(conByEmail.get(s.contactEmail).Id);
        lc.setOpportunityName(s.oppName);
        lc.setDoNotCreateOpportunity(false);
        lc.setOverwriteLeadSource(false);
        lc.setSendNotificationEmail(false);
        converts.add(lc);
    }

    // Held positionally against `pending` so a partial failure can never shift one
    // Lead's target stage onto the other's Opportunity.
    List<Database.LeadConvertResult> results = Database.convertLead(converts, false);
    for (Integer i = 0; i < results.size(); i++) {
        Database.LeadConvertResult lcr = results[i];
        if (lcr.isSuccess()) {
            convertedCount++;
            if (lcr.getOpportunityId() != null) {
                oppUpdates.add(new Opportunity(
                    Id           = lcr.getOpportunityId(),
                    RecordTypeId = rtOppRes,
                    StageName    = pending[i].stage,
                    Project__c   = projAId,
                    CloseDate    = RUN_DATE.addDays(pending[i].closeOffsetDays),
                    Budget_Range__c = 'Rs 90L-1.4Cr'
                ));
            }
        } else {
            notes.add('Conversion FAILED for ' + pending[i].leadEmail + ': '
                + lcr.getErrors()[0].getMessage());
        }
    }
}

// ===========================================================================
// 3. NORMALISE THE CONVERTED OPPORTUNITIES  (constraints (a) and (d))
// ===========================================================================
if (!oppUpdates.isEmpty()) {
    RecursionGuard.reset('Opportunity_afterUpdate');
    update oppUpdates;
}

// ===========================================================================
// SUMMARY — computed BEFORE any rollback, since a rollback invalidates Ids.
// ===========================================================================
System.debug(LoggingLevel.INFO, '');
System.debug(LoggingLevel.INFO, '======= FIX SEED LEAD CONVERSION SUMMARY ======');
System.debug(LoggingLevel.INFO, 'Mode: ' + (DRY_RUN ? 'DRY RUN (everything rolled back)' : 'COMMITTED'));
System.debug(LoggingLevel.INFO, '  Leads in scope'.rightPad(36, ' ')        + ' : ' + specs.size());
System.debug(LoggingLevel.INFO, '  Leads re-owned to a User'.rightPad(36, ' ') + ' : ' + reOwnedCount);
System.debug(LoggingLevel.INFO, '  Leads converted'.rightPad(36, ' ')       + ' : ' + convertedCount);
System.debug(LoggingLevel.INFO, '  Opportunities normalised'.rightPad(36, ' ') + ' : ' + oppUpdates.size());
System.debug(LoggingLevel.INFO, '  Pre-convert owner'.rightPad(36, ' ')     + ' : ' + convOwnerId);
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
        'DRY RUN COMPLETE — re-ownership, both conversions and the normalising update all executed '
        + 'and passed validation, then were rolled back. Expect "Leads converted : 2" above; if it '
        + 'reads 0 or 1, read the warnings before committing. Set DRY_RUN = false and re-run to commit.');
} else {
    System.debug(LoggingLevel.INFO,
        'FIX COMMITTED. The seed org should now hold 3 Opportunities from Lead conversion. Verify: '
        + 'SELECT Name, IsConverted, ConvertedOpportunityId FROM Lead '
        + 'WHERE Email LIKE \'%.seed@recrm-demo.invalid\' — expect IsConverted = true with a non-null '
        + 'ConvertedOpportunityId on Anita, Imran and Suresh.');
}
