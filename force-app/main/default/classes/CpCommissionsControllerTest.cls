@IsTest(SeeAllData=false)
private class CpCommissionsControllerTest {

    private static Booking__c bookingFor(Account cp, Account buyer, Project__c proj, Tower__c tower, Integer unitCode) {
        Unit__c u = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => unitCode, 'Unit_Status__c' => 'Blocked'
        });
        Opportunity o = TestDataFactory.createOpportunity(buyer.Id, new Map<String, Object>{
            'StageName' => 'Token Paid', 'Project__c' => proj.Id, 'Primary_Unit__c' => u.Id,
            'Quoted_Gross_Value__c' => 5000000, 'Source_Channel__c' => 'CP', 'Source_CP__c' => cp.Id
        });
        return TestDataFactory.createBooking(o.Id, u.Id, buyer.Id, new Map<String, Object>{
            'Source_CP__c' => cp.Id
        });
    }

    @IsTest
    static void testGetMyCommissions_ReturnsOnlyCpEntries() {
        Account cpA = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'COM A' });
        Account cpB = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'COM B' });
        Account buyer = TestDataFactory.createAccount(new Map<String, Object>{ 'Name' => 'Com Buyer' });
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'COM' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);

        Booking__c bA = bookingFor(cpA, buyer, proj, tower, 101);
        Booking__c bB = bookingFor(cpB, buyer, proj, tower, 102);
        TestDataFactory.createCommissionLedger(bA.Id, cpA.Id, new Map<String, Object>{
            'Agreement_Value_Basis__c' => 1000000, 'Rate_Pct__c' => 2,
            'GST_On_Commission__c' => 0, 'TDS_On_Commission__c' => 1000, 'Status__c' => 'Accrued'
        });
        TestDataFactory.createCommissionLedger(bB.Id, cpB.Id, new Map<String, Object>{
            'Agreement_Value_Basis__c' => 2000000, 'Rate_Pct__c' => 1,
            'GST_On_Commission__c' => 0, 'TDS_On_Commission__c' => 1000, 'Status__c' => 'Paid'
        });

        CP_Scope.testCpAccountId = cpA.Id;
        Test.startTest();
        CpCommissionsController.CommissionSummary summary = CpCommissionsController.getMyCommissions();
        Test.stopTest();

        System.assertEquals(1, summary.entries.size(), 'Only CP A entries');
        System.assert(summary.totalGross > 0, 'Gross > 0');
        System.assert(summary.totalAccrued > 0, 'Has accrued');
        System.assertEquals(0, summary.totalPaid, 'No paid for CP A');
    }

    @IsTest
    static void testCpIsolation_BothDirections() {
        Account cpA = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'CMI A' });
        Account cpB = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'CMI B' });
        Account buyer = TestDataFactory.createAccount(new Map<String, Object>{ 'Name' => 'CMI Buyer' });
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'CMI' });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);

        Booking__c bA = bookingFor(cpA, buyer, proj, tower, 201);
        Booking__c bB = bookingFor(cpB, buyer, proj, tower, 202);
        TestDataFactory.createCommissionLedger(bA.Id, cpA.Id, null);
        TestDataFactory.createCommissionLedger(bA.Id, cpA.Id, null);
        TestDataFactory.createCommissionLedger(bB.Id, cpB.Id, null);

        CP_Scope.testCpAccountId = cpA.Id;
        System.assertEquals(2, CpCommissionsController.getMyCommissions().entries.size(), 'CP A → 2');
        CP_Scope.testCpAccountId = cpB.Id;
        System.assertEquals(1, CpCommissionsController.getMyCommissions().entries.size(), 'CP B → 1');
    }
}
