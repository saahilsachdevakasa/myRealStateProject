@IsTest(SeeAllData=false)
public class OpportunityNamingServiceTest {

    @IsTest
    static void testNameOnInsert_WithAccountAndProject() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => 'AAP'
        });
        Account acc = TestDataFactory.createAccount(new Map<String, Object>{
            'Name' => 'Aarti Patel'
        });

        Opportunity opp = new Opportunity(
            Name = 'placeholder',
            StageName = 'New',
            CloseDate = Date.today().addDays(60),
            AccountId = acc.Id,
            Project__c = proj.Id
        );

        Test.startTest();
        insert opp;
        Test.stopTest();

        Opportunity refreshed = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Aarti Patel - AAP', refreshed.Name);
    }

    @IsTest
    static void testNameOnInsert_AccountOnly() {
        Account acc = TestDataFactory.createAccount(new Map<String, Object>{
            'Name' => 'Solo Buyer'
        });

        Opportunity opp = new Opportunity(
            Name = 'placeholder',
            StageName = 'New',
            CloseDate = Date.today().addDays(60),
            AccountId = acc.Id
        );

        Test.startTest();
        insert opp;
        Test.stopTest();

        Opportunity refreshed = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Solo Buyer', refreshed.Name);
    }

    @IsTest
    static void testNameOnInsert_WithBudgetRange() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => 'BUD'
        });
        Account acc = TestDataFactory.createAccount(new Map<String, Object>{
            'Name' => 'Budget Buyer'
        });

        Opportunity opp = new Opportunity(
            Name = 'placeholder',
            StageName = 'New',
            CloseDate = Date.today().addDays(60),
            AccountId = acc.Id,
            Project__c = proj.Id,
            Budget_Range__c = '2BHK'
        );

        Test.startTest();
        insert opp;
        Test.stopTest();

        Opportunity refreshed = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Budget Buyer - BUD 2BHK', refreshed.Name);
    }

    @IsTest
    static void testNameUpdated_WhenProjectChanges() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => 'CHG'
        });
        Account acc = TestDataFactory.createAccount(new Map<String, Object>{
            'Name' => 'Changing Buyer'
        });

        Opportunity opp = new Opportunity(
            Name = 'placeholder',
            StageName = 'New',
            CloseDate = Date.today().addDays(60),
            AccountId = acc.Id
        );
        insert opp;

        Opportunity afterInsert = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Changing Buyer', afterInsert.Name);

        Test.startTest();
        opp.Project__c = proj.Id;
        update opp;
        Test.stopTest();

        Opportunity afterUpdate = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Changing Buyer - CHG', afterUpdate.Name);
    }

    @IsTest
    static void testNameUnchanged_WhenOtherFieldsChange() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => 'UNC'
        });
        Account acc = TestDataFactory.createAccount(new Map<String, Object>{
            'Name' => 'Stable Buyer'
        });

        Opportunity opp = new Opportunity(
            Name = 'placeholder',
            StageName = 'New',
            CloseDate = Date.today().addDays(60),
            AccountId = acc.Id,
            Project__c = proj.Id
        );
        insert opp;

        opp.Name = 'Manually Overridden';
        update opp;

        Opportunity afterManual = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Manually Overridden', afterManual.Name,
            'Name-only update must NOT retrigger rename (Project+Account unchanged)');

        Test.startTest();
        opp.StageName = 'Qualified';
        update opp;
        Test.stopTest();

        Opportunity afterStage = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Manually Overridden', afterStage.Name,
            'StageName-only update must NOT retrigger rename');
    }

    @IsTest
    static void testBulkInsert() {
        List<Project__c> projects = new List<Project__c>();
        for (String code : new List<String>{ 'BKA', 'BKB', 'BKC' }) {
            projects.add(TestDataFactory.createProject(new Map<String, Object>{
                'Project_Code__c' => code
            }));
        }

        List<Account> accounts = new List<Account>();
        for (Integer i = 1; i <= 5; i++) {
            accounts.add(TestDataFactory.createAccount(new Map<String, Object>{
                'Name' => 'Bulk Buyer ' + i
            }));
        }

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 5; i++) {
            opps.add(new Opportunity(
                Name = 'placeholder',
                StageName = 'New',
                CloseDate = Date.today().addDays(60),
                AccountId = accounts[i].Id,
                Project__c = projects[Math.mod(i, 3)].Id
            ));
        }

        Test.startTest();
        insert opps;
        Test.stopTest();

        Map<Id, Opportunity> byId = new Map<Id, Opportunity>([
            SELECT Id, Name FROM Opportunity WHERE Id IN :opps
        ]);
        for (Integer i = 0; i < 5; i++) {
            String expected = 'Bulk Buyer ' + (i + 1) + ' - ' + (new List<String>{'BKA','BKB','BKC'})[Math.mod(i, 3)];
            System.assertEquals(expected, byId.get(opps[i].Id).Name, 'Opp ' + i);
        }
    }
}
