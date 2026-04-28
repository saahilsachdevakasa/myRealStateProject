@IsTest(SeeAllData=false)
private class CpSubmitLeadControllerTest {

    @IsTest
    static void testGetActiveProjects() {
        TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'AAA', 'Name' => 'Project AAA', 'Active_for_Bookings__c' => true });
        TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'BBB', 'Name' => 'Project BBB', 'Active_for_Bookings__c' => false });

        Test.startTest();
        List<CpSubmitLeadController.ProjectOption> opts = CpSubmitLeadController.getActiveProjects();
        Test.stopTest();

        System.assertEquals(1, opts.size(), 'Only Active projects returned');
        System.assert(opts[0].label.contains('AAA'));
    }

    @IsTest
    static void testSubmitLead_HappyPath() {
        Account cp = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'Submit CP' });
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'SUB' });
        CP_Scope.testCpAccountId = cp.Id;

        Test.startTest();
        Id leadId = CpSubmitLeadController.submitLead(
            'Riya', 'Mehta', '+919811112222', 'riya@example.com',
            proj.Id, new List<String>{'2BHK', '3BHK'}, 'Wants east-facing'
        );
        Test.stopTest();

        Lead created = [
            SELECT FirstName, LastName, Company, Phone, Email, Source_CP__c,
                   Source_Channel__c, Project_Interest__c, Unit_Type_Preference__c,
                   Description, Status
            FROM Lead WHERE Id = :leadId
        ];
        System.assertEquals('Riya', created.FirstName);
        System.assertEquals('Mehta', created.LastName);
        System.assertEquals('Riya Mehta', created.Company);
        System.assertEquals(cp.Id, created.Source_CP__c);
        System.assertEquals('CP', created.Source_Channel__c);
        System.assertEquals(proj.Id, created.Project_Interest__c);
        System.assertEquals('2BHK;3BHK', created.Unit_Type_Preference__c);
        System.assertEquals('Wants east-facing', created.Description);
        System.assertEquals('New', created.Status);
    }

    @IsTest
    static void testSubmitLead_MissingLastNameThrows() {
        Account cp = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'NL CP' });
        CP_Scope.testCpAccountId = cp.Id;
        Boolean caught = false;
        Test.startTest();
        try {
            CpSubmitLeadController.submitLead('First', null, null, null, null, null, null);
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Should reject missing LastName');
    }

    @IsTest
    static void testSubmitLead_NoUnitPreferences() {
        Account cp = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'NU CP' });
        CP_Scope.testCpAccountId = cp.Id;

        Test.startTest();
        Id leadId = CpSubmitLeadController.submitLead(
            'Solo', 'Buyer', null, null, null, null, null
        );
        Test.stopTest();

        Lead created = [SELECT Unit_Type_Preference__c FROM Lead WHERE Id = :leadId];
        System.assertEquals(null, created.Unit_Type_Preference__c, 'Empty list → null preference');
    }
}
