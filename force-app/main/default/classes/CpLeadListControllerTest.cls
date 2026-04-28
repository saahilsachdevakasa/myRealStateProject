@IsTest(SeeAllData=false)
private class CpLeadListControllerTest {

    @IsTest
    static void testGetMyLeads_ReturnsOnlyCpLeads() {
        Account cpA = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'CP Alpha' });
        Account cpB = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'CP Beta' });
        insert new List<Lead>{
            new Lead(FirstName='A', LastName='LeadA', Company='A LeadA', Source_CP__c=cpA.Id, Source_Channel__c='CP', Status='New'),
            new Lead(FirstName='B', LastName='LeadB', Company='B LeadB', Source_CP__c=cpB.Id, Source_Channel__c='CP', Status='New'),
            new Lead(FirstName='C', LastName='LeadC', Company='C LeadC', Source_Channel__c='Walk-in', Status='New')
        };

        CP_Scope.testCpAccountId = cpA.Id;
        Test.startTest();
        List<CpLeadListController.LeadData> leadsA = CpLeadListController.getMyLeads();
        Test.stopTest();

        System.assertEquals(1, leadsA.size(), 'Only Alpha lead should be returned');
        System.assertEquals('A LeadA', leadsA[0].name);
    }

    @IsTest
    static void testCpIsolation_BothDirections() {
        Account cpA = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'CP Iso A' });
        Account cpB = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'CP Iso B' });
        insert new List<Lead>{
            new Lead(FirstName='A1', LastName='IsoA1', Company='A1', Source_CP__c=cpA.Id, Source_Channel__c='CP', Status='New'),
            new Lead(FirstName='A2', LastName='IsoA2', Company='A2', Source_CP__c=cpA.Id, Source_Channel__c='CP', Status='New'),
            new Lead(FirstName='B1', LastName='IsoB1', Company='B1', Source_CP__c=cpB.Id, Source_Channel__c='CP', Status='New')
        };

        CP_Scope.testCpAccountId = cpA.Id;
        List<CpLeadListController.LeadData> leadsA = CpLeadListController.getMyLeads();
        System.assertEquals(2, leadsA.size(), 'CP A sees only A leads');
        for (CpLeadListController.LeadData ld : leadsA) {
            System.assert(ld.name.contains('IsoA'), 'No B leak in A view: ' + ld.name);
        }

        CP_Scope.testCpAccountId = cpB.Id;
        List<CpLeadListController.LeadData> leadsB = CpLeadListController.getMyLeads();
        System.assertEquals(1, leadsB.size(), 'CP B sees only B leads');
        System.assert(leadsB[0].name.contains('IsoB'), 'No A leak in B view');
    }
}
