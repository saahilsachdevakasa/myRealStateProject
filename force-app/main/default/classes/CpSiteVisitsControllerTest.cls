@IsTest(SeeAllData=false)
private class CpSiteVisitsControllerTest {

    @IsTest
    static void testGetMySiteVisits_ReturnsOnlyCpVisits() {
        Account cpA = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'SV CP A' });
        Account cpB = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'SV CP B' });
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'SVT' });

        Lead leadA = new Lead(FirstName='SV', LastName='LA', Company='SV LA', Source_CP__c=cpA.Id, Status='New');
        Lead leadB = new Lead(FirstName='SV', LastName='LB', Company='SV LB', Source_CP__c=cpB.Id, Status='New');
        insert new List<Lead>{ leadA, leadB };

        insert new List<Site_Visit__c>{
            new Site_Visit__c(Lead__c=leadA.Id, Project__c=proj.Id, Scheduled_DateTime__c=Datetime.now().addDays(1), Status__c='Scheduled'),
            new Site_Visit__c(Lead__c=leadB.Id, Project__c=proj.Id, Scheduled_DateTime__c=Datetime.now().addDays(2), Status__c='Scheduled')
        };

        CP_Scope.testCpAccountId = cpA.Id;
        Test.startTest();
        List<CpSiteVisitsController.VisitData> visits = CpSiteVisitsController.getMySiteVisits();
        Test.stopTest();

        System.assertEquals(1, visits.size(), 'CP A sees only their own visit');
    }

    @IsTest
    static void testCpIsolation_BothDirections() {
        Account cpA = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'SVI A' });
        Account cpB = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'SVI B' });
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'SVI' });

        Lead leadA = new Lead(FirstName='IA', LastName='LIA', Company='IA', Source_CP__c=cpA.Id, Status='New');
        Lead leadB = new Lead(FirstName='IB', LastName='LIB', Company='IB', Source_CP__c=cpB.Id, Status='New');
        insert new List<Lead>{ leadA, leadB };
        insert new List<Site_Visit__c>{
            new Site_Visit__c(Lead__c=leadA.Id, Project__c=proj.Id, Scheduled_DateTime__c=Datetime.now().addDays(1), Status__c='Scheduled'),
            new Site_Visit__c(Lead__c=leadA.Id, Project__c=proj.Id, Scheduled_DateTime__c=Datetime.now().addDays(2), Status__c='Scheduled'),
            new Site_Visit__c(Lead__c=leadB.Id, Project__c=proj.Id, Scheduled_DateTime__c=Datetime.now().addDays(3), Status__c='Scheduled')
        };

        CP_Scope.testCpAccountId = cpA.Id;
        System.assertEquals(2, CpSiteVisitsController.getMySiteVisits().size(), 'CP A sees 2');
        CP_Scope.testCpAccountId = cpB.Id;
        System.assertEquals(1, CpSiteVisitsController.getMySiteVisits().size(), 'CP B sees 1');
    }
}
