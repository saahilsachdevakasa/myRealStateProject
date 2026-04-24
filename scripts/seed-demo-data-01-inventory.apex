/**
 * Demo Data Seed — Part 1: Inventory
 *
 * Creates two projects with towers and units:
 *   - PRK (Park Residences) — Residential, 1 Tower, 4 units on Floor 1
 *   - GAL (Galleria Central) — Commercial, 1 Block, 2 shops on Floor 1
 *
 * Idempotent: wipes all records scoped to project codes PRK and GAL
 * (including dependent Bookings, Opportunities, Leads) before recreating.
 *
 * Run order: 01 → 02 → 03.
 * Run: sf apex run --file scripts/seed-demo-data-01-inventory.apex --target-org re-crm-sdo
 */

System.debug('=== STARTING INVENTORY SEED ===');

// ========================================================================
// CLEANUP — delete in reverse dependency order.
// Booking.Unit__c has deleteConstraint=Restrict, so Bookings must be
// deleted before their Units. Units cascade from Tower via MD, which
// cascades from Project via MD.
// ========================================================================

List<Project__c> existingProjects = [
    SELECT Id FROM Project__c WHERE Project_Code__c IN ('PRK', 'GAL')
];

if (!existingProjects.isEmpty()) {
    Set<Id> projIds = new Map<Id, Project__c>(existingProjects).keySet();

    // Get Units under these projects (via Tower)
    List<Unit__c> unitsInScope = [
        SELECT Id FROM Unit__c WHERE Tower__r.Project__c IN :projIds
    ];
    Set<Id> unitIds = new Map<Id, Unit__c>(unitsInScope).keySet();

    // Kill Bookings referencing any of those Units (cascades to Demands,
    // Receipts, Agreements, Possessions, Schedules, Snags via MD).
    List<Booking__c> bookings = [
        SELECT Id FROM Booking__c WHERE Unit__c IN :unitIds
    ];
    if (!bookings.isEmpty()) {
        System.debug('Deleting ' + bookings.size() + ' bookings on PRK/GAL units (cascades to children)');
        delete bookings;
    }

    // Kill Opps referencing these Projects or Units (SetNull constraints
    // would orphan fields but we delete outright for cleanliness)
    List<Opportunity> opps = [
        SELECT Id FROM Opportunity
        WHERE Project__c IN :projIds OR Primary_Unit__c IN :unitIds
    ];
    if (!opps.isEmpty()) {
        System.debug('Deleting ' + opps.size() + ' opportunities linked to PRK/GAL');
        delete opps;
    }

    // Kill Leads referencing these Projects
    List<Lead> leads = [SELECT Id FROM Lead WHERE Project_Interest__c IN :projIds];
    if (!leads.isEmpty()) {
        System.debug('Deleting ' + leads.size() + ' leads linked to PRK/GAL');
        delete leads;
    }

    // Now safe to delete Projects (cascades to Towers and Units)
    System.debug('Deleting ' + existingProjects.size() + ' existing projects (cascades to towers + units)');
    delete existingProjects;
}

// ========================================================================
// PROJECT 1 — PRK (Park Residences, Luxury Residential)
// ========================================================================

Project__c prk = new Project__c(
    Name = 'Park Residences',
    Project_Code__c = 'PRK',
    Project_Type__c = 'Residential',
    Positioning__c = 'Luxury',
    Launch_Status__c = 'Under Construction',
    Location__c = 'Worli',
    City__c = 'Mumbai',
    State__c = 'Maharashtra',
    RERA_Number__c = 'P51800045678',
    RERA_State__c = 'Maharashtra',
    Delivery_Date__c = Date.newInstance(2028, 6, 30),
    CC_Received__c = false,
    Club_Membership_Fee__c = 250000,
    Covered_Parking_Fee__c = 500000,
    Active_for_Bookings__c = true
);
insert prk;
System.debug('Created PRK: ' + prk.Id);

// ========================================================================
// PROJECT 2 — GAL (Galleria Central, Commercial)
// ========================================================================

Project__c gal = new Project__c(
    Name = 'Galleria Central',
    Project_Code__c = 'GAL',
    Project_Type__c = 'Commercial',
    Positioning__c = 'Premium',
    Launch_Status__c = 'Under Construction',
    Location__c = 'Hinjewadi',
    City__c = 'Pune',
    State__c = 'Maharashtra',
    RERA_Number__c = 'P52100078901',
    RERA_State__c = 'Maharashtra',
    Delivery_Date__c = Date.newInstance(2027, 12, 31),
    CC_Received__c = false,
    Active_for_Bookings__c = true
);
insert gal;
System.debug('Created GAL: ' + gal.Id);

// ========================================================================
// TOWERS — Tower Name MUST match Tower_Code formula (gotcha #30)
// Formula: Project_Code + "-T" + leftPad(Tower_Number, 2, '0') [residential]
//       or Project_Code + "-B" + leftPad(Tower_Number, 2, '0') [commercial]
// ========================================================================

Tower__c prkTower = new Tower__c(
    Name = 'PRK-T01',
    Project__c = prk.Id,
    Tower_Number__c = 1,
    Tower_Type__c = 'Residential Tower',
    Total_Floors__c = 4,
    Units_Per_Floor__c = 4,
    Construction_Status__c = 'Under Construction'
);
insert prkTower;
System.debug('Created Tower PRK-T01: ' + prkTower.Id);

Tower__c galBlock = new Tower__c(
    Name = 'GAL-B01',
    Project__c = gal.Id,
    Tower_Number__c = 1,
    Tower_Type__c = 'Commercial Block',
    Total_Floors__c = 3,
    Units_Per_Floor__c = 4,
    Construction_Status__c = 'Under Construction'
);
insert galBlock;
System.debug('Created Block GAL-B01: ' + galBlock.Id);

// ========================================================================
// UNITS — PRK Tower 1 Floor 1 (4 residential units)
// Name must match Unit_Code formula:
//   PROJ + "-T" + towerNum + "-F" + floorNum + "-U" + unitNum (residential)
//   PROJ + "-B" + towerNum + "-F" + floorNum + "-S" + unitNum (commercial)
// ========================================================================

List<Unit__c> prkUnits = new List<Unit__c>{
    new Unit__c(
        Name = 'PRK-T01-F01-U001',
        Tower__c = prkTower.Id,
        Floor__c = 1,
        Unit_Number__c = 1,
        Unit_Type_Class__c = 'Residential',
        Configuration__c = '3BHK',
        Carpet_Area_sqft__c = 1200,
        BuiltUp_Area_sqft__c = 1440,
        Super_BuiltUp_Area_sqft__c = 1800,
        BSP_Per_Sqft__c = 15000,
        Facing__c = 'East',
        Unit_Status__c = 'Available'
    ),
    new Unit__c(
        Name = 'PRK-T01-F01-U002',
        Tower__c = prkTower.Id,
        Floor__c = 1,
        Unit_Number__c = 2,
        Unit_Type_Class__c = 'Residential',
        Configuration__c = '2BHK',
        Carpet_Area_sqft__c = 850,
        BuiltUp_Area_sqft__c = 1020,
        Super_BuiltUp_Area_sqft__c = 1275,
        BSP_Per_Sqft__c = 14000,
        Facing__c = 'West',
        Unit_Status__c = 'Available'
    ),
    new Unit__c(
        Name = 'PRK-T01-F01-U003',
        Tower__c = prkTower.Id,
        Floor__c = 1,
        Unit_Number__c = 3,
        Unit_Type_Class__c = 'Residential',
        Configuration__c = '3BHK',
        Carpet_Area_sqft__c = 1300,
        BuiltUp_Area_sqft__c = 1560,
        Super_BuiltUp_Area_sqft__c = 1950,
        BSP_Per_Sqft__c = 16000,
        Facing__c = 'East',
        Corner_Unit__c = true,
        Park_Facing__c = true,
        Unit_Status__c = 'Available'
    ),
    new Unit__c(
        Name = 'PRK-T01-F01-U004',
        Tower__c = prkTower.Id,
        Floor__c = 1,
        Unit_Number__c = 4,
        Unit_Type_Class__c = 'Residential',
        Configuration__c = '2BHK',
        Carpet_Area_sqft__c = 900,
        BuiltUp_Area_sqft__c = 1080,
        Super_BuiltUp_Area_sqft__c = 1350,
        BSP_Per_Sqft__c = 13500,
        Facing__c = 'North',
        Unit_Status__c = 'Available'
    )
};
insert prkUnits;
System.debug('Created ' + prkUnits.size() + ' PRK residential units on Floor 1');

// ========================================================================
// SHOPS — GAL Block 1 Floor 1 (2 commercial shops)
// ========================================================================

List<Unit__c> galShops = new List<Unit__c>{
    new Unit__c(
        Name = 'GAL-B01-F01-S001',
        Tower__c = galBlock.Id,
        Floor__c = 1,
        Unit_Number__c = 1,
        Unit_Type_Class__c = 'Shop',
        Configuration__c = 'Shop',
        Carpet_Area_sqft__c = 500,
        BuiltUp_Area_sqft__c = 600,
        Super_BuiltUp_Area_sqft__c = 750,
        BSP_Per_Sqft__c = 30000,
        Frontage_ft__c = 25,
        Shop_Type__c = 'Retail',
        Unit_Status__c = 'Available'
    ),
    new Unit__c(
        Name = 'GAL-B01-F01-S002',
        Tower__c = galBlock.Id,
        Floor__c = 1,
        Unit_Number__c = 2,
        Unit_Type_Class__c = 'Shop',
        Configuration__c = 'Shop',
        Carpet_Area_sqft__c = 400,
        BuiltUp_Area_sqft__c = 480,
        Super_BuiltUp_Area_sqft__c = 600,
        BSP_Per_Sqft__c = 28000,
        Frontage_ft__c = 20,
        Shop_Type__c = 'F&B',
        Unit_Status__c = 'Available'
    )
};
insert galShops;
System.debug('Created ' + galShops.size() + ' GAL commercial shops on Floor 1');

System.debug('=== INVENTORY SEED COMPLETE ===');
System.debug('Summary: 2 projects, 2 towers, ' + (prkUnits.size() + galShops.size()) + ' units');
