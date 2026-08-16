/**
 * ============================================================================
 * seed-test-data-01-inventory.apex — SCRIPT 1 OF 7
 * ============================================================================
 *
 * PART OF: the seed-test-data-* series, which creates one coherent, realistic
 *   slice of data spanning every object in the system (21 custom + Lead /
 *   Account / Contact / Opportunity) so that every LWC, Flow, Agentforce action
 *   and report has something meaningful to render.
 *
 *   The series was split out of a single 94KB file because this org's
 *   executeAnonymous ceiling is exactly 32,000 characters. Each script is its
 *   own transaction, so no in-memory state carries across files — every script
 *   from 02 onward re-queries what it needs via the 'SEED' markers below.
 *
 * DEPENDS ON: nothing. This is the first script in the series.
 *
 * PRODUCES (re-queryable by later scripts):
 *   Project__c  x2  — Project_Code__c = 'ZSA' (residential) / 'ZSB' (commercial)
 *   Tower__c    x4  — Name 'ZSA-T01', 'ZSA-T02', 'ZSB-B01', 'ZSB-B02'
 *   Unit__c     x48 — Name '{PROJ}-T{nn}-F{nn}-U{nnn}' / '{PROJ}-B{nn}-F{nn}-S{nnn}'
 *
 * HOW TO RUN
 *   sf apex run --file scripts/seed-test-data-01-inventory.apex --target-org re-crm-sdo
 *
 *   Dry run first (DRY_RUN = true, the default): every insert and every
 *   validation rule executes, then the whole thing rolls back.
 *
 *   !! IMPORTANT — RUN ORDER FOR THE SERIES !!
 *   Because a dry run rolls its own records back, you cannot dry-run all seven
 *   scripts and only then commit them: script 02's preconditions would find no
 *   Projects. The workable sequence is per script:
 *       dry-run 01 -> commit 01 -> dry-run 02 -> commit 02 -> ... -> commit 07
 *   Dry-run validation is therefore per-file, not atomic across the whole
 *   24-object run. That is an accepted trade-off of the 32,000-char split.
 *
 * SAFETY
 *   - DRY_RUN = true wraps the run in a Savepoint and rolls back at the end,
 *     AFTER every insert has executed and passed validation.
 *   - Pre-flight collision check throws if the seed Project Codes already exist,
 *     so a second run can't half-collide.
 *   - INSERT-ONLY. Nothing pre-existing is modified.
 *   - Every distinguishing text field carries the 'SEED' tag, so the whole batch
 *     is greppable / deletable later.
 *
 * WHY SYSTEM MODE (not AccessLevel.USER_MODE)
 *   Per gotcha #27, metadata-deployed custom fields carry no FLS on any profile —
 *   including System Administrator — unless explicitly granted. Running this seed
 *   in USER_MODE would fail on fields whose FLS was never granted to the running
 *   admin. Every operational seed script in scripts/ runs in system mode for the
 *   same reason. This is deliberate and is NOT a precedent for shipped Apex,
 *   which must keep using WITH SECURITY_ENFORCED / AccessLevel.USER_MODE.
 *
 * SEQUENCING CONSTRAINTS HONOURED IN THIS FILE
 *   (f) Gotcha #30: Tower__c.Tower_Name_Matches_Code requires Name to equal the
 *       derived Tower_Code__c, so the derived name is computed in Apex before
 *       insert (mirroring TestDataFactory.createTower). Unit Names are computed
 *       the same way to match the Unit_Code__c formula, even though no VR
 *       enforces it — consistency with the existing PRK/GAL inventory.
 *
 * KNOWN LIMITATIONS
 *   - AutoNumber sequences consumed by a dry run are NOT restored by the
 *     rollback. Harmless, but expect a gap in numbering after a dry run.
 * ============================================================================
 */

// ===========================================================================
// CONFIG
// ===========================================================================
Boolean DRY_RUN = false;   // true = roll everything back at the end

final String TAG    = 'SEED';
final String PROJ_A = 'ZSA';   // residential seed project code (3 uppercase — VR Project_Code_Format)
final String PROJ_B = 'ZSB';   // commercial seed project code

final Date RUN_DATE = Date.today();

// ===========================================================================
// PRE-FLIGHT — abort loudly rather than half-collide with a previous run
// ===========================================================================
List<Project__c> codeClash = [
    SELECT Id, Project_Code__c FROM Project__c WHERE Project_Code__c IN (:PROJ_A, :PROJ_B)
];
if (!codeClash.isEmpty()) {
    throw new IllegalArgumentException(
        'ABORT: seed Project Code(s) already present in this org (' + codeClash.size() + ' found). ' +
        'This script is one-shot. Delete the previous seed data, or change PROJ_A/PROJ_B to unused ' +
        '3-uppercase-letter codes (and the matching constants in scripts 02-07), before re-running.'
    );
}

// ===========================================================================
// RECORD TYPE IDS (describe calls — no SOQL cost)
// ===========================================================================
Id rtProjectRes = Schema.SObjectType.Project__c.getRecordTypeInfosByDeveloperName().get('Residential').getRecordTypeId();
Id rtProjectCom = Schema.SObjectType.Project__c.getRecordTypeInfosByDeveloperName().get('Commercial').getRecordTypeId();
Id rtTowerRes   = Schema.SObjectType.Tower__c.getRecordTypeInfosByDeveloperName().get('Residential_Tower').getRecordTypeId();
Id rtTowerCom   = Schema.SObjectType.Tower__c.getRecordTypeInfosByDeveloperName().get('Commercial_Block').getRecordTypeId();
Id rtUnitRes    = Schema.SObjectType.Unit__c.getRecordTypeInfosByDeveloperName().get('Residential_Unit').getRecordTypeId();
Id rtUnitCom    = Schema.SObjectType.Unit__c.getRecordTypeInfosByDeveloperName().get('Commercial_Shop').getRecordTypeId();

List<String> summaryOrder = new List<String>();
Map<String, Integer> counts = new Map<String, Integer>();

Savepoint sp = Database.setSavepoint();

System.debug(LoggingLevel.INFO, '=== SEED 01 INVENTORY START (DRY_RUN=' + DRY_RUN + ') ===');

// ===========================================================================
// 1. PROJECTS
// ===========================================================================
List<Project__c> projects = new List<Project__c>{
    new Project__c(
        Name = TAG + ' Verdant Heights',
        RecordTypeId = rtProjectRes,
        Project_Code__c = PROJ_A,
        Project_Type__c = 'Residential',
        Launch_Status__c = 'Under Construction',
        City__c = 'Pune',
        State__c = 'Maharashtra',
        Location__c = 'Baner-Balewadi corridor',
        Positioning__c = 'Mid-premium 2/3/4 BHK, gated, 4.2 acres',
        RERA_Number__c = 'P52100' + TAG + '001',
        RERA_State__c = 'Maharashtra',
        CC_Received__c = false,                  // drives 5% GST bracket in DemandService
        Delivery_Date__c = RUN_DATE.addMonths(26),
        Club_Membership_Fee__c = 250000,
        Covered_Parking_Fee__c = 400000,
        Brochure_URL__c = 'https://example.invalid/seed/verdant-heights',
        Active_for_Bookings__c = true
    ),
    new Project__c(
        Name = TAG + ' Marina Square Commercial',
        RecordTypeId = rtProjectCom,
        Project_Code__c = PROJ_B,
        Project_Type__c = 'Commercial',
        Launch_Status__c = 'Newly Launched',
        City__c = 'Navi Mumbai',
        State__c = 'Maharashtra',
        Location__c = 'Vashi waterfront',
        Positioning__c = 'High-street retail and F&B, 1.6 acres',
        RERA_Number__c = 'P51700' + TAG + '002',
        RERA_State__c = 'Maharashtra',
        CC_Received__c = false,
        Delivery_Date__c = RUN_DATE.addMonths(20),
        Active_for_Bookings__c = true
    )
};
insert projects;
Project__c projA = projects[0];
Project__c projB = projects[1];
summaryOrder.add('Project__c');  counts.put('Project__c', projects.size());

// ===========================================================================
// 2. TOWERS — Name must equal derived Tower_Code__c (VR Tower_Name_Matches_Code)
//    Derived in Apex before insert, exactly as TestDataFactory.createTower does.
// ===========================================================================
List<Tower__c> towers = new List<Tower__c>();
for (Integer n = 1; n <= 2; n++) {
    towers.add(new Tower__c(
        Name = PROJ_A + '-T' + String.valueOf(n).leftPad(2, '0'),
        RecordTypeId = rtTowerRes,
        Project__c = projA.Id,
        Tower_Number__c = n,
        Tower_Type__c = 'Residential Tower',
        Total_Floors__c = 4,
        Units_Per_Floor__c = 4,
        Construction_Status__c = (n == 1) ? 'Under Construction' : 'Excavation',
        Current_Milestone__c = (n == 1) ? 'Slab Cast' : 'Foundation',
        Configuration_Mix__c = '2BHK / 3BHK / 4BHK',
        Slab_Progress__c = (n == 1) ? '3 of 4 slabs cast' : 'Foundation in progress'
    ));
}
for (Integer n = 1; n <= 2; n++) {
    towers.add(new Tower__c(
        Name = PROJ_B + '-B' + String.valueOf(n).leftPad(2, '0'),
        RecordTypeId = rtTowerCom,
        Project__c = projB.Id,
        Tower_Number__c = n,
        Tower_Type__c = 'Commercial Block',
        Total_Floors__c = 3,
        Units_Per_Floor__c = 20,
        Construction_Status__c = 'Under Construction',
        Current_Milestone__c = 'Brickwork',
        Configuration_Mix__c = 'Retail / F&B / Anchor'
    ));
}
insert towers;
summaryOrder.add('Tower__c');  counts.put('Tower__c', towers.size());

// ===========================================================================
// 3. UNITS — 12 per tower (floors 1-3 x 4 units). Floor__c 1..99 and
//    Unit_Number__c 1..999 keep Floor_In_Range / Unit_Number_In_Range happy.
//    Name matches the Unit_Code__c formula ({PROJ}-T{nn}-F{nn}-U{nnn} /
//    {PROJ}-B{nn}-F{nn}-S{nnn}) — script 03 re-queries specific units by Name.
// ===========================================================================
List<String> resConfigs = new List<String>{ '2BHK', '3BHK', '3BHK', '4BHK' };
List<Integer> resCarpet = new List<Integer>{  720,    980,    1010,   1350  };
List<String> facings    = new List<String>{ 'North-East', 'East', 'South-West', 'West' };
List<String> shopTypes  = new List<String>{ 'Retail', 'Retail', 'F&B', 'Kiosk' };

List<Unit__c> units = new List<Unit__c>();
for (Tower__c t : towers) {
    Boolean isCommercial = (t.Tower_Type__c == 'Commercial Block');
    for (Integer floor = 1; floor <= 3; floor++) {
        for (Integer u = 1; u <= 4; u++) {
            String unitName = t.Name
                + '-F' + String.valueOf(floor).leftPad(2, '0')
                + (isCommercial ? '-S' : '-U') + String.valueOf(u).leftPad(3, '0');

            Unit__c unit = new Unit__c(
                Name = unitName,
                Tower__c = t.Id,
                Floor__c = floor,
                Unit_Number__c = u,
                Unit_Status__c = 'Available',
                Facing__c = facings[Math.mod(u - 1, facings.size())],
                Corner_Unit__c = (u == 1 || u == 4),
                Park_Facing__c = (u == 2)
            );

            if (isCommercial) {
                unit.RecordTypeId = rtUnitCom;
                unit.Unit_Type_Class__c = 'Shop';
                unit.Configuration__c = 'Shop';
                unit.Shop_Type__c = shopTypes[Math.mod(u - 1, shopTypes.size())];
                unit.Frontage_ft__c = 18 + (u * 2);
                unit.Carpet_Area_sqft__c = 420 + (u * 30);
                unit.BuiltUp_Area_sqft__c = 500 + (u * 30);
                unit.Super_BuiltUp_Area_sqft__c = 620 + (u * 35);
                unit.BSP_Per_Sqft__c = 18500;
            } else {
                unit.RecordTypeId = rtUnitRes;
                unit.Unit_Type_Class__c = 'Residential';
                unit.Configuration__c = resConfigs[u - 1];
                unit.Carpet_Area_sqft__c = resCarpet[u - 1];
                unit.BuiltUp_Area_sqft__c = resCarpet[u - 1] + 180;
                unit.Super_BuiltUp_Area_sqft__c = resCarpet[u - 1] + 420;
                unit.BSP_Per_Sqft__c = 9800 + (floor * 100);
            }
            units.add(unit);
        }
    }
}
insert units;
summaryOrder.add('Unit__c');  counts.put('Unit__c', units.size());

// ===========================================================================
// SUMMARY — computed BEFORE any rollback, since a rollback invalidates Ids.
// ===========================================================================
Integer totalRecords = 0;
for (String k : summaryOrder) totalRecords += counts.get(k);

System.debug(LoggingLevel.INFO, '');
System.debug(LoggingLevel.INFO, '========== SEED 01 INVENTORY SUMMARY ==========');
System.debug(LoggingLevel.INFO, 'Mode: ' + (DRY_RUN ? 'DRY RUN (everything rolled back)' : 'COMMITTED'));
System.debug(LoggingLevel.INFO, 'Seed tag: ' + TAG + '   Project codes: ' + PROJ_A + ', ' + PROJ_B);
for (String k : summaryOrder) {
    System.debug(LoggingLevel.INFO, '  ' + k.rightPad(34, ' ') + ' : ' + counts.get(k));
}
System.debug(LoggingLevel.INFO, '  TOTAL RECORDS'.rightPad(36, ' ') + ' : ' + totalRecords);
System.debug(LoggingLevel.INFO, 'Governor usage: SOQL ' + Limits.getQueries() + '/' + Limits.getLimitQueries()
    + '  |  DML statements ' + Limits.getDmlStatements() + '/' + Limits.getLimitDmlStatements()
    + '  |  DML rows ' + Limits.getDmlRows() + '/' + Limits.getLimitDmlRows()
    + '  |  CPU ' + Limits.getCpuTime() + 'ms/' + Limits.getLimitCpuTime() + 'ms');
System.debug(LoggingLevel.INFO, '===============================================');

// ===========================================================================
// ROLLBACK (dry run only)
// ===========================================================================
if (DRY_RUN) {
    Database.rollback(sp);
    System.debug(LoggingLevel.INFO,
        'DRY RUN COMPLETE — every insert above executed and passed validation, then was rolled back. '
        + 'Nothing was persisted. Set DRY_RUN = false and re-run to commit, THEN move on to '
        + 'scripts/seed-test-data-02-accounts.apex.');
} else {
    System.debug(LoggingLevel.INFO,
        'SEED 01 COMMITTED. Next: scripts/seed-test-data-02-accounts.apex. '
        + 'Clean-up handle: Project Codes ' + PROJ_A + '/' + PROJ_B + ', Names begin with "' + TAG + '".');
}
