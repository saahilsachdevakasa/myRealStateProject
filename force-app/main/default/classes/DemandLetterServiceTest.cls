@IsTest(SeeAllData=false)
public class DemandLetterServiceTest {

    /** Build full chain through to a raised Demand (re-uses DemandService). */
    private static List<Demand__c> seedAndRaiseDemands(String projectCode, Integer milestoneCount, String planCode, Integer raiseCount) {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => projectCode,
            'CC_Received__c' => false,
            'RERA_Number__c' => 'P51800012345',
            'RERA_State__c' => 'Maharashtra'
        });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        Unit__c unit = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Status__c' => 'Blocked'
        });
        Account acc = TestDataFactory.createAccount(new Map<String, Object>{
            'Name' => 'Buyer ' + projectCode
        });
        Opportunity opp = TestDataFactory.createOpportunity(acc.Id, new Map<String, Object>{
            'StageName' => 'Token Paid',
            'Project__c' => proj.Id,
            'Primary_Unit__c' => unit.Id,
            'EOI_Amount__c' => 100000,
            'Token_Amount__c' => 200000,
            'Quoted_Gross_Value__c' => 1000000
        });
        opp.StageName = 'Closed Won (Booked)';
        update opp;
        Opportunity refreshedOpp = [SELECT Booking__c FROM Opportunity WHERE Id = :opp.Id];
        Booking__c booking = [SELECT Id, Name FROM Booking__c WHERE Id = :refreshedOpp.Booking__c];

        Payment_Plan__c plan = TestDataFactory.createPaymentPlanWithMilestones(milestoneCount,
            new Map<String, Object>{ 'Plan_Code__c' => planCode });
        RecursionGuard.resetAll();
        booking.Payment_Plan__c = plan.Id;
        update booking;

        List<Booking_Payment_Schedule__c> schedules = [
            SELECT Id FROM Booking_Payment_Schedule__c
            WHERE Booking__c = :booking.Id ORDER BY Sequence__c
        ];

        List<DemandService.DemandRequest> reqs = new List<DemandService.DemandRequest>();
        for (Integer i = 0; i < raiseCount; i++) {
            DemandService.DemandRequest r = new DemandService.DemandRequest();
            r.paymentScheduleId = schedules[i].Id;
            reqs.add(r);
        }
        RecursionGuard.resetAll();
        List<Id> demandIds = DemandService.raiseDemands(reqs);

        return [SELECT Id, Name FROM Demand__c WHERE Id IN :demandIds ORDER BY Demand_Seq__c];
    }

    @IsTest
    static void testGenerateDemandLetter_HappyPath() {
        List<Demand__c> demands = seedAndRaiseDemands('HPY', 1, 'HPP', 1);
        Demand__c demand = demands[0];

        DemandLetterService.GenerateDemandLetterRequest req = new DemandLetterService.GenerateDemandLetterRequest();
        req.demandId = demand.Id;

        Test.startTest();
        DemandLetterService.generateDemandLetters(
            new List<DemandLetterService.GenerateDemandLetterRequest>{ req }
        );
        Test.stopTest();

        Demand__c refreshed = [SELECT PDF_Generated__c, PDF_Attachment_Id__c FROM Demand__c WHERE Id = :demand.Id];
        System.assertEquals(true, refreshed.PDF_Generated__c);
        System.assertNotEquals(null, refreshed.PDF_Attachment_Id__c);

        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocumentId, ShareType
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :demand.Id
        ];
        System.assertEquals(1, links.size());
        System.assertEquals('V', links[0].ShareType);
        System.assertEquals(refreshed.PDF_Attachment_Id__c, String.valueOf(links[0].ContentDocumentId));

        ContentVersion cv = [
            SELECT Title, PathOnClient
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
            LIMIT 1
        ];
        System.assert(cv.Title.contains(demand.Name), 'Title should contain demand name: ' + cv.Title);
        System.assertEquals(demand.Name + '.pdf', cv.PathOnClient);
    }

    @IsTest
    static void testGenerateDemandLetter_BulkOperation() {
        List<Demand__c> demands = seedAndRaiseDemands('BLK', 3, 'BLP', 3);

        List<DemandLetterService.GenerateDemandLetterRequest> reqs = new List<DemandLetterService.GenerateDemandLetterRequest>();
        for (Demand__c d : demands) {
            DemandLetterService.GenerateDemandLetterRequest r = new DemandLetterService.GenerateDemandLetterRequest();
            r.demandId = d.Id;
            reqs.add(r);
        }

        Test.startTest();
        DemandLetterService.generateDemandLetters(reqs);
        Test.stopTest();

        Integer generatedCount = [
            SELECT COUNT() FROM Demand__c
            WHERE Id IN :(new Map<Id, Demand__c>(demands).keySet())
            AND PDF_Generated__c = true
        ];
        System.assertEquals(3, generatedCount);

        Set<Id> demandIds = (new Map<Id, Demand__c>(demands)).keySet();
        Integer linkCount = [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId IN :demandIds
        ];
        System.assertEquals(3, linkCount);
    }

    @IsTest
    static void testGenerateDemandLetter_MissingDemand_Rejected() {
        List<Demand__c> demands = seedAndRaiseDemands('MIS', 1, 'MSP', 1);
        Id deletedId = demands[0].Id;
        delete demands[0];

        DemandLetterService.GenerateDemandLetterRequest req = new DemandLetterService.GenerateDemandLetterRequest();
        req.demandId = deletedId;

        Boolean caught = false;
        Test.startTest();
        try {
            DemandLetterService.generateDemandLetters(
                new List<DemandLetterService.GenerateDemandLetterRequest>{ req }
            );
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Expected AuraHandledException for non-existent Demand');
    }

    @IsTest
    static void testDemandLetterController_LoadsData() {
        List<Demand__c> demands = seedAndRaiseDemands('CTL', 1, 'CTP', 1);
        Demand__c demand = demands[0];

        Test.startTest();
        Test.setCurrentPage(Page.DemandLetter);
        ApexPages.currentPage().getParameters().put('id', demand.Id);
        DemandLetterController ctrl = new DemandLetterController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.demand, 'Demand should be loaded');
        System.assertEquals(demand.Id, ctrl.demand.Id);
        System.assertNotEquals(null, ctrl.booking);
        System.assertNotEquals(null, ctrl.unit);
        System.assertNotEquals(null, ctrl.project);
        System.assertNotEquals(null, ctrl.buyerName);
        System.assertNotEquals(null, ctrl.unitDisplay);
        System.assertNotEquals(null, ctrl.milestoneLabel);
    }

    @IsTest
    static void testDemandLetterController_NoIdParam() {
        Test.startTest();
        Test.setCurrentPage(Page.DemandLetter);
        DemandLetterController ctrl = new DemandLetterController();
        Test.stopTest();

        System.assertEquals(null, ctrl.demand, 'No id param → no data loaded');
    }
}
