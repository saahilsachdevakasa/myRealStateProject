@IsTest(SeeAllData=false)
private class CpDashboardControllerTest {

    @IsTest
    static void testGetDashboardData_HappyPath() {
        Account cp = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'Dash CP' });
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'DSH' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        Unit__c unit = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{ 'Unit_Status__c' => 'Blocked' });

        // 2 leads attributed to this CP
        insert new List<Lead>{
            new Lead(FirstName='A', LastName='Lead1', Company='A Lead1', Source_CP__c=cp.Id, Source_Channel__c='CP', Status='New'),
            new Lead(FirstName='B', LastName='Lead2', Company='B Lead2', Source_CP__c=cp.Id, Source_Channel__c='CP', Status='New')
        };

        // 1 active booking attributed to this CP
        Account buyer = TestDataFactory.createAccount(new Map<String, Object>{ 'Name' => 'Dash Buyer' });
        Opportunity opp = TestDataFactory.createOpportunity(buyer.Id, new Map<String, Object>{
            'StageName' => 'Token Paid', 'Project__c' => proj.Id, 'Primary_Unit__c' => unit.Id,
            'Quoted_Gross_Value__c' => 5000000,
            'Source_Channel__c' => 'CP', 'Source_CP__c' => cp.Id
        });
        Booking__c bk = TestDataFactory.createBooking(opp.Id, unit.Id, buyer.Id, new Map<String, Object>{
            'Source_CP__c' => cp.Id
        });

        // 1 Accrued ledger entry (counts toward both YTD and pending)
        TestDataFactory.createCommissionLedger(bk.Id, cp.Id, new Map<String, Object>{
            'Milestone_Date__c' => Date.today(),
            'Agreement_Value_Basis__c' => 1000000, 'Rate_Pct__c' => 2,
            'GST_On_Commission__c' => 0, 'TDS_On_Commission__c' => 1000,
            'Status__c' => 'Accrued'
        });

        CP_Scope.testCpAccountId = cp.Id;

        Test.startTest();
        CpDashboardController.DashboardData d = CpDashboardController.getDashboardData();
        Test.stopTest();

        System.assertEquals(2, d.leadCount, 'Lead count');
        System.assertEquals(1, d.activeBookings, 'Active bookings');
        System.assert(d.ytdCommission > 0, 'YTD commission should be > 0');
        System.assert(d.pendingPayouts > 0, 'Pending payouts should be > 0');
    }

    @IsTest
    static void testGetDashboardData_EmptyData() {
        Account cp = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'Empty CP' });
        CP_Scope.testCpAccountId = cp.Id;

        Test.startTest();
        CpDashboardController.DashboardData d = CpDashboardController.getDashboardData();
        Test.stopTest();

        System.assertEquals(0, d.leadCount);
        System.assertEquals(0, d.activeBookings);
        System.assertEquals(0, d.ytdCommission);
        System.assertEquals(0, d.pendingPayouts);
    }
}
