@IsTest(SeeAllData=false)
public class DemandServiceTest {

    /** Build full chain: Project (CC override allowed) → Tower → Blocked Unit → Account → Opp → close-won → Booking. */
    private static Map<String, SObject> seedAndCloseWon(String projectCode, Decimal quotedGrossValue, Boolean ccReceived) {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => projectCode,
            'CC_Received__c' => ccReceived
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
            'Quoted_Gross_Value__c' => quotedGrossValue
        });
        opp.StageName = 'Closed Won (Booked)';
        update opp;
        Opportunity refreshedOpp = [SELECT Booking__c FROM Opportunity WHERE Id = :opp.Id];
        Booking__c booking = [SELECT Id, Name FROM Booking__c WHERE Id = :refreshedOpp.Booking__c];
        return new Map<String, SObject>{
            'project' => proj, 'tower' => tower, 'unit' => unit,
            'account' => acc, 'opp' => opp, 'booking' => booking
        };
    }

    /** Attach a Payment Plan with N equal-percentage milestones to a Booking and return the schedule rows. */
    private static List<Booking_Payment_Schedule__c> attachPlan(Booking__c booking, Integer milestoneCount, String planCode) {
        Payment_Plan__c plan = TestDataFactory.createPaymentPlanWithMilestones(milestoneCount,
            new Map<String, Object>{ 'Plan_Code__c' => planCode });
        RecursionGuard.resetAll();
        booking.Payment_Plan__c = plan.Id;
        update booking;
        return [
            SELECT Id, Status__c, Scheduled_Amount__c, Sequence__c
            FROM Booking_Payment_Schedule__c
            WHERE Booking__c = :booking.Id
            ORDER BY Sequence__c
        ];
    }

    @IsTest
    static void testRaiseDemand_HappyPath() {
        Map<String, SObject> chain = seedAndCloseWon('HPY', 1000000, false);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Booking_Payment_Schedule__c> schedules = attachPlan(booking, 1, 'HPP');

        DemandService.DemandRequest req = new DemandService.DemandRequest();
        req.paymentScheduleId = schedules[0].Id;

        RecursionGuard.resetAll();

        Test.startTest();
        List<Id> demandIds = DemandService.raiseDemands(new List<DemandService.DemandRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, demandIds.size());
        Demand__c d = [
            SELECT Id, Name, Booking__c, Payment_Schedule__c, Demand_Seq__c,
                   Principal_Amount__c, GST_Amount__c, TDS_Amount__c, Status__c,
                   Raised_Date__c, Due_Date__c
            FROM Demand__c WHERE Id = :demandIds[0]
        ];
        System.assertEquals(booking.Id, d.Booking__c);
        System.assertEquals(schedules[0].Id, d.Payment_Schedule__c);
        System.assertEquals(1, d.Demand_Seq__c);
        System.assertEquals('DM-' + booking.Name + '-01', d.Name);
        System.assertEquals('Raised', d.Status__c);
        System.assertEquals(Date.today(), d.Raised_Date__c);
        System.assertEquals(Date.today().addDays(15), d.Due_Date__c);
        System.assertEquals(1000000, d.Principal_Amount__c);
        System.assertEquals(10000, d.GST_Amount__c, 'Affordable: 1M * 1% = 10k');
        System.assertEquals(0, d.TDS_Amount__c, 'Total Consideration < 50L → no TDS');

        Booking_Payment_Schedule__c refreshed = [
            SELECT Status__c, Demand_Raised_Date__c, Actual_Demand__c
            FROM Booking_Payment_Schedule__c WHERE Id = :schedules[0].Id
        ];
        System.assertEquals('Demand Raised', refreshed.Status__c);
        System.assertEquals(Date.today(), refreshed.Demand_Raised_Date__c);
        System.assertEquals(d.Id, refreshed.Actual_Demand__c);
    }

    @IsTest
    static void testRaiseDemand_AlreadyRaised_Rejected() {
        Map<String, SObject> chain = seedAndCloseWon('ARJ', 1000000, false);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Booking_Payment_Schedule__c> schedules = attachPlan(booking, 1, 'ARP');

        Booking_Payment_Schedule__c sch = schedules[0];
        sch.Status__c = 'Demand Raised';
        update sch;

        DemandService.DemandRequest req = new DemandService.DemandRequest();
        req.paymentScheduleId = sch.Id;

        Boolean caught = false;
        Test.startTest();
        try {
            DemandService.raiseDemands(new List<DemandService.DemandRequest>{ req });
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Expected AuraHandledException for already-raised schedule');
    }

    @IsTest
    static void testRaiseDemand_SequentialNumbering() {
        Map<String, SObject> chain = seedAndCloseWon('SEQ', 1000000, false);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Booking_Payment_Schedule__c> schedules = attachPlan(booking, 3, 'SQP');

        Test.startTest();
        DemandService.DemandRequest r1 = new DemandService.DemandRequest();
        r1.paymentScheduleId = schedules[0].Id;
        RecursionGuard.resetAll();
        List<Id> firstIds = DemandService.raiseDemands(new List<DemandService.DemandRequest>{ r1 });

        DemandService.DemandRequest r2 = new DemandService.DemandRequest();
        r2.paymentScheduleId = schedules[1].Id;
        RecursionGuard.resetAll();
        List<Id> secondIds = DemandService.raiseDemands(new List<DemandService.DemandRequest>{ r2 });
        Test.stopTest();

        Demand__c d1 = [SELECT Name, Demand_Seq__c FROM Demand__c WHERE Id = :firstIds[0]];
        Demand__c d2 = [SELECT Name, Demand_Seq__c FROM Demand__c WHERE Id = :secondIds[0]];
        System.assertEquals(1, d1.Demand_Seq__c);
        System.assertEquals(2, d2.Demand_Seq__c);
        System.assert(d1.Name.endsWith('-01'), 'd1 name should end -01: ' + d1.Name);
        System.assert(d2.Name.endsWith('-02'), 'd2 name should end -02: ' + d2.Name);
    }

    @IsTest
    static void testRaiseDemand_GSTZeroPostCC() {
        Map<String, SObject> chain = seedAndCloseWon('CCC', 5000000, true);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Booking_Payment_Schedule__c> schedules = attachPlan(booking, 1, 'CCP');

        DemandService.DemandRequest req = new DemandService.DemandRequest();
        req.paymentScheduleId = schedules[0].Id;

        RecursionGuard.resetAll();

        Test.startTest();
        List<Id> demandIds = DemandService.raiseDemands(new List<DemandService.DemandRequest>{ req });
        Test.stopTest();

        Demand__c d = [SELECT GST_Amount__c FROM Demand__c WHERE Id = :demandIds[0]];
        System.assertEquals(0, d.GST_Amount__c, 'CC_Received=true → GST=0');
    }

    @IsTest
    static void testRaiseDemand_TDSZeroBelowThreshold() {
        Map<String, SObject> chain = seedAndCloseWon('TDS', 1000000, false);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Booking_Payment_Schedule__c> schedules = attachPlan(booking, 1, 'TDP');

        DemandService.DemandRequest req = new DemandService.DemandRequest();
        req.paymentScheduleId = schedules[0].Id;

        RecursionGuard.resetAll();

        Test.startTest();
        List<Id> demandIds = DemandService.raiseDemands(new List<DemandService.DemandRequest>{ req });
        Test.stopTest();

        Demand__c d = [SELECT TDS_Amount__c FROM Demand__c WHERE Id = :demandIds[0]];
        System.assertEquals(0, d.TDS_Amount__c, 'Total Consideration 1M < 50L → no TDS');
    }

    @IsTest
    static void testRaiseDemand_BulkOperation() {
        Map<String, SObject> chain = seedAndCloseWon('BLK', 1000000, false);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Booking_Payment_Schedule__c> schedules = attachPlan(booking, 5, 'BKP');

        List<DemandService.DemandRequest> reqs = new List<DemandService.DemandRequest>();
        for (Booking_Payment_Schedule__c s : schedules) {
            DemandService.DemandRequest r = new DemandService.DemandRequest();
            r.paymentScheduleId = s.Id;
            reqs.add(r);
        }

        RecursionGuard.resetAll();

        Test.startTest();
        List<Id> demandIds = DemandService.raiseDemands(reqs);
        Test.stopTest();

        System.assertEquals(5, demandIds.size());
        List<Demand__c> demands = [
            SELECT Demand_Seq__c, Name FROM Demand__c
            WHERE Id IN :demandIds ORDER BY Demand_Seq__c
        ];
        for (Integer i = 0; i < 5; i++) {
            System.assertEquals(i + 1, demands[i].Demand_Seq__c, 'Seq ' + (i+1));
            System.assert(demands[i].Name.endsWith('-' + String.valueOf(i+1).leftPad(2, '0')),
                'Demand ' + i + ' name should end -' + String.valueOf(i+1).leftPad(2, '0') + ', got: ' + demands[i].Name);
        }

        Integer raisedCount = [
            SELECT COUNT() FROM Booking_Payment_Schedule__c
            WHERE Booking__c = :booking.Id AND Status__c = 'Demand Raised'
        ];
        System.assertEquals(5, raisedCount, 'All 5 schedule rows should be Demand Raised');
    }
}
