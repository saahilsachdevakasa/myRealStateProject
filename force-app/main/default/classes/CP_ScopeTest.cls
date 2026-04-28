@IsTest(SeeAllData=false)
private class CP_ScopeTest {

    @IsTest
    static void testGetCpAccountId_WithTestOverride() {
        Account cp = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'Override CP' });
        CP_Scope.testCpAccountId = cp.Id;

        Test.startTest();
        Id result = CP_Scope.getCpAccountId();
        Test.stopTest();

        System.assertEquals(cp.Id, result, 'Override should be honoured in test context');
    }

    @IsTest
    static void testGetCpAccountId_NoContactThrows() {
        // Running user is System Admin — no ContactId. Override is null.
        // Expected behavior: AuraHandledException.
        Boolean caught = false;
        Test.startTest();
        try {
            CP_Scope.getCpAccountId();
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Should throw when running user has no ContactId and no override');
    }

    @IsTest
    static void testCurrentCpAccountId_DirectCall() {
        // Direct call to currentCpAccountId() bypasses the test override
        Boolean caught = false;
        Test.startTest();
        try {
            CP_Scope.currentCpAccountId();
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Direct currentCpAccountId() throws for non-portal user');
    }
}
