@IsTest(SeeAllData=false)
private class QueryAvailableUnitsActionTest {

    @IsTest
    static void testQueryUnits_AllFilters() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'QFL' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        // Matching unit: 3BHK, East, Floor 5, corner
        Unit__c match = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 1, 'Configuration__c' => '3BHK', 'Floor__c' => 5,
            'Facing__c' => 'East', 'Corner_Unit__c' => true
        });
        // Non-matching: 2BHK
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 2, 'Configuration__c' => '2BHK' });
        // Non-matching: West facing
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 3, 'Configuration__c' => '3BHK', 'Facing__c' => 'West' });

        QueryAvailableUnitsAction.UnitQuery q = new QueryAvailableUnitsAction.UnitQuery();
        q.projectId = proj.Id;
        q.configuration = '3BHK';
        q.facing = 'East';
        q.minFloor = 3;
        q.cornerOnly = true;
        q.maxResults = 5;

        Test.startTest();
        List<QueryAvailableUnitsAction.QueryResponse> resps =
            QueryAvailableUnitsAction.queryUnits(new List<QueryAvailableUnitsAction.UnitQuery>{ q });
        Test.stopTest();

        System.assertEquals(1, resps[0].count, 'Only the corner east 3BHK on floor 5+ should match');
        System.assertEquals(match.Id, resps[0].units[0].unitId);
    }

    @IsTest
    static void testQueryUnits_NoFilters_AllAvailable() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'QNF' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 1 });
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 2 });
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 3, 'Unit_Status__c' => 'Blocked' });

        QueryAvailableUnitsAction.UnitQuery q = new QueryAvailableUnitsAction.UnitQuery();
        q.projectId = proj.Id;

        Test.startTest();
        List<QueryAvailableUnitsAction.QueryResponse> resps =
            QueryAvailableUnitsAction.queryUnits(new List<QueryAvailableUnitsAction.UnitQuery>{ q });
        Test.stopTest();

        System.assertEquals(2, resps[0].count, 'Only Available units (not Blocked) returned');
    }

    @IsTest
    static void testQueryUnits_MaxResultsCap() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'CAP' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        for (Integer i = 1; i <= 7; i++) {
            TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => i });
        }

        QueryAvailableUnitsAction.UnitQuery q = new QueryAvailableUnitsAction.UnitQuery();
        q.projectId = proj.Id;
        q.maxResults = 3;

        Test.startTest();
        List<QueryAvailableUnitsAction.QueryResponse> resps =
            QueryAvailableUnitsAction.queryUnits(new List<QueryAvailableUnitsAction.UnitQuery>{ q });
        Test.stopTest();

        System.assertEquals(3, resps[0].count, 'maxResults should cap the result count');
    }

    @IsTest
    static void testQueryUnits_PriceFilter() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'PRC' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        // Cheap unit: 5000 * 1500 = 7,500,000
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 1, 'BSP_Per_Sqft__c' => 5000
        });
        // Expensive unit: 20000 * 1500 = 30,000,000
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 2, 'BSP_Per_Sqft__c' => 20000
        });

        QueryAvailableUnitsAction.UnitQuery q = new QueryAvailableUnitsAction.UnitQuery();
        q.projectId = proj.Id;
        q.maxPrice = 10000000;  // 1Cr cap

        Test.startTest();
        List<QueryAvailableUnitsAction.QueryResponse> resps =
            QueryAvailableUnitsAction.queryUnits(new List<QueryAvailableUnitsAction.UnitQuery>{ q });
        Test.stopTest();

        System.assertEquals(1, resps[0].count, 'Only cheap unit under 1Cr cap');
        System.assert(resps[0].units[0].basePrice <= 10000000);
    }

    @IsTest
    static void testQueryByProjectName() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Name' => 'Park Residences', 'Project_Code__c' => 'QPN'
        });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 1 });
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 2 });

        QueryAvailableUnitsAction.UnitQuery q = new QueryAvailableUnitsAction.UnitQuery();
        q.projectName = 'Park Residences';

        Test.startTest();
        List<QueryAvailableUnitsAction.QueryResponse> resps =
            QueryAvailableUnitsAction.queryUnits(new List<QueryAvailableUnitsAction.UnitQuery>{ q });
        Test.stopTest();

        System.assertEquals(2, resps[0].count, 'Both units in the project resolved by name');
        System.assertEquals('Park Residences', resps[0].units[0].projectName);
    }

    @IsTest
    static void testQueryByProjectCode() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Name' => 'Code Lookup Project', 'Project_Code__c' => 'QPC'
        });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 1 });
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 2 });
        TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Number__c' => 3 });

        QueryAvailableUnitsAction.UnitQuery q = new QueryAvailableUnitsAction.UnitQuery();
        q.projectCode = 'QPC';

        Test.startTest();
        List<QueryAvailableUnitsAction.QueryResponse> resps =
            QueryAvailableUnitsAction.queryUnits(new List<QueryAvailableUnitsAction.UnitQuery>{ q });
        Test.stopTest();

        System.assertEquals(3, resps[0].count, 'All three units in the project resolved by code');
        System.assertEquals('Code Lookup Project', resps[0].units[0].projectName);
    }
}