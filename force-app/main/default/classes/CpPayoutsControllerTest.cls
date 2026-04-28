@IsTest(SeeAllData=false)
private class CpPayoutsControllerTest {

    @IsTest
    static void testGetMyPayouts_ReturnsOnlyCpPayouts() {
        Account cpA = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'PAY A' });
        Account cpB = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'PAY B' });

        TestDataFactory.createCommissionPayout(cpA.Id, new Map<String, Object>{ 'Status__c' => 'Draft' });
        TestDataFactory.createCommissionPayout(cpB.Id, new Map<String, Object>{ 'Status__c' => 'Paid' });

        CP_Scope.testCpAccountId = cpA.Id;
        Test.startTest();
        List<CpPayoutsController.PayoutData> payouts = CpPayoutsController.getMyPayouts();
        Test.stopTest();

        System.assertEquals(1, payouts.size(), 'Only CP A payout returned');
        System.assertEquals('Draft', payouts[0].status);
    }

    @IsTest
    static void testCpIsolation_BothDirections() {
        Account cpA = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'PI A' });
        Account cpB = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'PI B' });
        TestDataFactory.createCommissionPayout(cpA.Id, null);
        TestDataFactory.createCommissionPayout(cpA.Id, null);
        TestDataFactory.createCommissionPayout(cpB.Id, null);

        CP_Scope.testCpAccountId = cpA.Id;
        System.assertEquals(2, CpPayoutsController.getMyPayouts().size(), 'CP A → 2');
        CP_Scope.testCpAccountId = cpB.Id;
        System.assertEquals(1, CpPayoutsController.getMyPayouts().size(), 'CP B → 1');
    }
}
