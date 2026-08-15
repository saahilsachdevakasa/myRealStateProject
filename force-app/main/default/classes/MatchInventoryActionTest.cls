@IsTest(SeeAllData=false)
private class MatchInventoryActionTest {

    private static MatchInventoryAction.MatchRequest req(Id leadId) {
        MatchInventoryAction.MatchRequest r = new MatchInventoryAction.MatchRequest();
        r.leadId = leadId;
        return r;
    }

    private static Lead createLead(Id projectId, Decimal minB, Decimal maxB, String prefs) {
        Lead l = new Lead(
            FirstName = 'Match', LastName = 'Tester', Company = 'Match Tester',
            Status = 'New',
            Project_Interest__c = projectId,
            Budget_Min__c = minB, Budget_Max__c = maxB,
            Unit_Type_Preference__c = prefs
        );
        insert l;
        return l;
    }

    @IsTest
    static void testMatchInventory_HappyPath() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'MIH' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 1, 'Floor__c' => 3, 'Configuration__c' => '2BHK',
            'Carpet_Area_sqft__c' => 800, 'Super_BuiltUp_Area_sqft__c' => 1000, 'BSP_Per_Sqft__c' => 10000,
            'Facing__c' => 'East', 'Corner_Unit__c' => true, 'Park_Facing__c' => true
        });
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 2, 'Floor__c' => 1, 'Configuration__c' => '2BHK',
            'Super_BuiltUp_Area_sqft__c' => 1000, 'BSP_Per_Sqft__c' => 10000,
            'Facing__c' => 'West'
        });
        Lead l = createLead(proj.Id, 5000000, 20000000, '2BHK');

        Test.startTest();
        List<MatchInventoryAction.MatchResponse> resps =
            MatchInventoryAction.matchInventory(new List<MatchInventoryAction.MatchRequest>{ req(l.Id) });
        Test.stopTest();

        MatchInventoryAction.MatchResponse r = resps[0];
        System.assert(r.matchCount >= 1 && r.matchCount <= 3, 'Expected 1..3 matches, got ' + r.matchCount);
        for (MatchInventoryAction.UnitMatch m : r.matches) {
            System.assertEquals('2BHK', m.configuration, 'All matches must be 2BHK');
        }
        Lead refreshed = [SELECT Suggested_Units__c FROM Lead WHERE Id = :l.Id];
        System.assert(String.isNotBlank(refreshed.Suggested_Units__c), 'Suggested_Units should be populated');
    }

    @IsTest
    static void testMatchInventory_NoMatchingUnits() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'NMU' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 1, 'Configuration__c' => '3BHK'
            // Default Base_Price = 10000 * 1500 = 15M
        });
        Lead l = createLead(proj.Id, 1000, 5000, '3BHK');  // Way below price

        Test.startTest();
        List<MatchInventoryAction.MatchResponse> resps =
            MatchInventoryAction.matchInventory(new List<MatchInventoryAction.MatchRequest>{ req(l.Id) });
        Test.stopTest();

        System.assertEquals(0, resps[0].matchCount, 'Budget too low → no matches');
        System.assert(resps[0].summary.contains('No matching'), 'Summary should indicate none found');
    }

    @IsTest
    static void testMatchInventory_ConfigurationFiltering() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'CFG' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 1, 'Configuration__c' => '1BHK' });
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 2, 'Configuration__c' => '2BHK' });
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 3, 'Configuration__c' => '3BHK' });
        Lead l = createLead(proj.Id, 5000000, 25000000, '2BHK');

        Test.startTest();
        List<MatchInventoryAction.MatchResponse> resps =
            MatchInventoryAction.matchInventory(new List<MatchInventoryAction.MatchRequest>{ req(l.Id) });
        Test.stopTest();

        System.assertEquals(1, resps[0].matchCount, 'Only 2BHK should match');
        System.assertEquals('2BHK', resps[0].matches[0].configuration);
    }

    @IsTest
    static void testMatchInventory_ScoringOrder() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'SCR' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        Unit__c plain = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 1, 'Configuration__c' => '3BHK', 'Floor__c' => 1, 'Facing__c' => 'West'
        });
        Unit__c corner = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 2, 'Configuration__c' => '3BHK', 'Floor__c' => 1,
            'Facing__c' => 'West', 'Corner_Unit__c' => true
        });
        Unit__c premium = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 3, 'Configuration__c' => '3BHK', 'Floor__c' => 5,
            'Facing__c' => 'East', 'Corner_Unit__c' => true, 'Park_Facing__c' => true
        });
        Lead l = createLead(proj.Id, 5000000, 25000000, '3BHK');

        Test.startTest();
        List<MatchInventoryAction.MatchResponse> resps =
            MatchInventoryAction.matchInventory(new List<MatchInventoryAction.MatchRequest>{ req(l.Id) });
        Test.stopTest();

        System.assertEquals(3, resps[0].matchCount);
        // Premium unit (corner + park + east + higher floor + config) should score highest → first
        System.assertEquals(premium.Id, resps[0].matches[0].unitId, 'Premium unit ranks first');
        // Plain unit should rank last
        System.assertEquals(plain.Id, resps[0].matches[2].unitId, 'Plain unit ranks last');
    }

    @IsTest
    static void testMatchInventory_NoLeadId() {
        Test.startTest();
        List<MatchInventoryAction.MatchResponse> resps =
            MatchInventoryAction.matchInventory(new List<MatchInventoryAction.MatchRequest>{ req(null) });
        Test.stopTest();
        System.assertEquals(0, resps[0].matchCount);
    }

    @IsTest
    static void testMatchInventory_NoProjectInterest() {
        Lead l = new Lead(LastName='X', Company='X', Status='New');
        insert l;
        Test.startTest();
        List<MatchInventoryAction.MatchResponse> resps =
            MatchInventoryAction.matchInventory(new List<MatchInventoryAction.MatchRequest>{ req(l.Id) });
        Test.stopTest();
        System.assert(resps[0].summary.contains('Project'), 'Summary should mention project requirement');
    }
}