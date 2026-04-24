@IsTest(SeeAllData=false)
public class PaymentScheduleServiceTest {

    /** Create a Project/Tower/Blocked-Unit/Account/Opp chain ready for close-won. */
    private static Map<String, SObject> seedLifecycleChain(String projectCode, Decimal quotedGrossValue) {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => projectCode
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
        return new Map<String, SObject>{
            'project' => proj,
            'tower' => tower,
            'unit' => unit,
            'account' => acc,
            'opp' => opp
        };
    }

    /** Build a Payment Plan with N milestones from provided specs. */
    private static Payment_Plan__c createPlanWithSpecs(String code, List<Map<String, Object>> specs) {
        Payment_Plan__c plan = TestDataFactory.createPaymentPlan(new Map<String, Object>{
            'Plan_Code__c' => code,
            'Name' => 'Plan ' + code
        });
        for (Map<String, Object> spec : specs) {
            TestDataFactory.createPaymentPlanMilestone(plan.Id, spec);
        }
        return plan;
    }

    @IsTest
    static void testPaymentPlanSelection_CreatesScheduleRows() {
        Map<String, SObject> chain = seedLifecycleChain('TST', 5000000);
        Opportunity opp = (Opportunity) chain.get('opp');

        opp.StageName = 'Closed Won (Booked)';
        update opp;

        Opportunity refreshedOpp = [SELECT Booking__c FROM Opportunity WHERE Id = :opp.Id];
        Booking__c booking = [SELECT Id FROM Booking__c WHERE Id = :refreshedOpp.Booking__c];

        Payment_Plan__c plan = createPlanWithSpecs('P3', new List<Map<String, Object>>{
            new Map<String, Object>{ 'Sequence__c' => 1, 'Percentage__c' => 10, 'Trigger__c' => 'On Booking', 'Trigger_Type__c' => 'Booking', 'Days_From_Trigger__c' => 0 },
            new Map<String, Object>{ 'Sequence__c' => 2, 'Percentage__c' => 40, 'Trigger__c' => '30 days', 'Trigger_Type__c' => 'Time-Based', 'Days_From_Trigger__c' => 30 },
            new Map<String, Object>{ 'Sequence__c' => 3, 'Percentage__c' => 50, 'Trigger__c' => 'On Possession', 'Trigger_Type__c' => 'Possession' }
        });

        RecursionGuard.resetAll();

        Test.startTest();
        booking.Payment_Plan__c = plan.Id;
        update booking;
        Test.stopTest();

        List<Booking_Payment_Schedule__c> rows = [
            SELECT Sequence__c, Percentage__c, Scheduled_Amount__c, Expected_Date__c, Status__c, Milestone_Trigger__c
            FROM Booking_Payment_Schedule__c
            WHERE Booking__c = :booking.Id
            ORDER BY Sequence__c
        ];
        System.assertEquals(3, rows.size(), '3 schedule rows expected');
        System.assertEquals(1, rows[0].Sequence__c);
        System.assertEquals(10, rows[0].Percentage__c);
        System.assertEquals(500000, rows[0].Scheduled_Amount__c, 'row 0 = 10% of 5M');
        System.assertEquals(Date.today(), rows[0].Expected_Date__c, 'Booking trigger → booking date + 0 days');
        System.assertEquals('Pending', rows[0].Status__c);
        System.assertEquals('On Booking', rows[0].Milestone_Trigger__c);
        System.assertEquals(2000000, rows[1].Scheduled_Amount__c, 'row 1 = 40% of 5M');
        System.assertEquals(Date.today().addDays(30), rows[1].Expected_Date__c, 'Time-Based +30');
        System.assertEquals(2500000, rows[2].Scheduled_Amount__c, 'row 2 = 50% of 5M');
        System.assertEquals(null, rows[2].Expected_Date__c, 'Possession → null');
    }

    @IsTest
    static void testPaymentPlanSwitch_DeletesOldCreatesNew() {
        Map<String, SObject> chain = seedLifecycleChain('SWT', 1000000);
        Opportunity opp = (Opportunity) chain.get('opp');

        opp.StageName = 'Closed Won (Booked)';
        update opp;
        Opportunity refreshedOpp = [SELECT Booking__c FROM Opportunity WHERE Id = :opp.Id];
        Booking__c booking = [SELECT Id FROM Booking__c WHERE Id = :refreshedOpp.Booking__c];

        Payment_Plan__c planA = createPlanWithSpecs('PA', new List<Map<String, Object>>{
            new Map<String, Object>{ 'Sequence__c' => 1, 'Percentage__c' => 30, 'Trigger__c' => 'A1', 'Trigger_Type__c' => 'Booking', 'Days_From_Trigger__c' => 0 },
            new Map<String, Object>{ 'Sequence__c' => 2, 'Percentage__c' => 30, 'Trigger__c' => 'A2', 'Trigger_Type__c' => 'Time-Based', 'Days_From_Trigger__c' => 30 },
            new Map<String, Object>{ 'Sequence__c' => 3, 'Percentage__c' => 40, 'Trigger__c' => 'A3', 'Trigger_Type__c' => 'Possession' }
        });
        Payment_Plan__c planB = createPlanWithSpecs('PB', new List<Map<String, Object>>{
            new Map<String, Object>{ 'Sequence__c' => 1, 'Percentage__c' => 50, 'Trigger__c' => 'B1', 'Trigger_Type__c' => 'Booking', 'Days_From_Trigger__c' => 0 },
            new Map<String, Object>{ 'Sequence__c' => 2, 'Percentage__c' => 50, 'Trigger__c' => 'B2', 'Trigger_Type__c' => 'Possession' }
        });

        RecursionGuard.resetAll();
        booking.Payment_Plan__c = planA.Id;
        update booking;
        Integer countAfterA = [SELECT COUNT() FROM Booking_Payment_Schedule__c WHERE Booking__c = :booking.Id];
        System.assertEquals(3, countAfterA, 'Plan A should create 3 rows');

        RecursionGuard.resetAll();

        Test.startTest();
        booking.Payment_Plan__c = planB.Id;
        update booking;
        Test.stopTest();

        List<Booking_Payment_Schedule__c> rows = [
            SELECT Sequence__c, Milestone_Trigger__c, Percentage__c
            FROM Booking_Payment_Schedule__c
            WHERE Booking__c = :booking.Id
            ORDER BY Sequence__c
        ];
        System.assertEquals(2, rows.size(), 'Plan A rows replaced with Plan B rows');
        System.assertEquals('B1', rows[0].Milestone_Trigger__c, 'Plan A orphans must be deleted');
        System.assertEquals('B2', rows[1].Milestone_Trigger__c);
    }

    @IsTest
    static void testPaymentPlanSelection_NoAgreementValue() {
        Map<String, SObject> chain = seedLifecycleChain('NAV', 0);
        Opportunity opp = (Opportunity) chain.get('opp');

        opp.StageName = 'Closed Won (Booked)';
        update opp;
        Opportunity refreshedOpp = [SELECT Booking__c FROM Opportunity WHERE Id = :opp.Id];
        Booking__c booking = [SELECT Id, Agreement_Value__c FROM Booking__c WHERE Id = :refreshedOpp.Booking__c];

        Payment_Plan__c plan = createPlanWithSpecs('NVP', new List<Map<String, Object>>{
            new Map<String, Object>{ 'Sequence__c' => 1, 'Percentage__c' => 100, 'Trigger__c' => 'Only', 'Trigger_Type__c' => 'Booking', 'Days_From_Trigger__c' => 0 }
        });

        RecursionGuard.resetAll();

        Test.startTest();
        booking.Payment_Plan__c = plan.Id;
        update booking;
        Test.stopTest();

        List<Booking_Payment_Schedule__c> rows = [
            SELECT Scheduled_Amount__c FROM Booking_Payment_Schedule__c WHERE Booking__c = :booking.Id
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals(0, rows[0].Scheduled_Amount__c, 'Scheduled_Amount should be 0, not null');
    }

    @IsTest
    static void testPaymentPlanSelection_BulkOperation() {
        List<String> codes = new List<String>{ 'BKA', 'BKB', 'BKC', 'BKD', 'BKE' };
        List<Opportunity> opps = new List<Opportunity>();
        for (String code : codes) {
            Map<String, SObject> chain = seedLifecycleChain(code, 2000000);
            opps.add((Opportunity) chain.get('opp'));
        }

        for (Opportunity o : opps) {
            o.StageName = 'Closed Won (Booked)';
        }
        update opps;

        List<Opportunity> closedOpps = [SELECT Id, Booking__c FROM Opportunity WHERE Id IN :opps];
        Set<Id> bookingIds = new Set<Id>();
        for (Opportunity o : closedOpps) bookingIds.add(o.Booking__c);
        List<Booking__c> bookings = [SELECT Id FROM Booking__c WHERE Id IN :bookingIds];
        System.assertEquals(5, bookings.size());

        Payment_Plan__c plan = createPlanWithSpecs('BLK', new List<Map<String, Object>>{
            new Map<String, Object>{ 'Sequence__c' => 1, 'Percentage__c' => 50, 'Trigger__c' => 'First', 'Trigger_Type__c' => 'Booking', 'Days_From_Trigger__c' => 0 },
            new Map<String, Object>{ 'Sequence__c' => 2, 'Percentage__c' => 50, 'Trigger__c' => 'Second', 'Trigger_Type__c' => 'Possession' }
        });

        for (Booking__c b : bookings) {
            b.Payment_Plan__c = plan.Id;
        }

        RecursionGuard.resetAll();

        Test.startTest();
        update bookings;
        Test.stopTest();

        Integer totalRows = [SELECT COUNT() FROM Booking_Payment_Schedule__c WHERE Booking__c IN :bookingIds];
        System.assertEquals(10, totalRows, '5 bookings × 2 milestones each = 10 rows');
    }

    @IsTest
    static void testPaymentPlanSelection_InactiveMilestonesSkipped() {
        Map<String, SObject> chain = seedLifecycleChain('INA', 3000000);
        Opportunity opp = (Opportunity) chain.get('opp');

        opp.StageName = 'Closed Won (Booked)';
        update opp;
        Opportunity refreshedOpp = [SELECT Booking__c FROM Opportunity WHERE Id = :opp.Id];
        Booking__c booking = [SELECT Id FROM Booking__c WHERE Id = :refreshedOpp.Booking__c];

        Payment_Plan__c plan = TestDataFactory.createPaymentPlan(new Map<String, Object>{
            'Plan_Code__c' => 'INC',
            'Name' => 'Plan INC',
            'Active__c' => false
        });
        TestDataFactory.createPaymentPlanMilestone(plan.Id, new Map<String, Object>{
            'Sequence__c' => 1, 'Percentage__c' => 30, 'Trigger__c' => 'M1', 'Trigger_Type__c' => 'Booking', 'Days_From_Trigger__c' => 0
        });
        TestDataFactory.createPaymentPlanMilestone(plan.Id, new Map<String, Object>{
            'Sequence__c' => 2, 'Percentage__c' => 30, 'Trigger__c' => 'M2 (inactive)', 'Trigger_Type__c' => 'Time-Based', 'Days_From_Trigger__c' => 30, 'Active__c' => false
        });
        TestDataFactory.createPaymentPlanMilestone(plan.Id, new Map<String, Object>{
            'Sequence__c' => 3, 'Percentage__c' => 20, 'Trigger__c' => 'M3', 'Trigger_Type__c' => 'Time-Based', 'Days_From_Trigger__c' => 60
        });
        TestDataFactory.createPaymentPlanMilestone(plan.Id, new Map<String, Object>{
            'Sequence__c' => 4, 'Percentage__c' => 20, 'Trigger__c' => 'M4', 'Trigger_Type__c' => 'Possession'
        });

        RecursionGuard.resetAll();

        Test.startTest();
        booking.Payment_Plan__c = plan.Id;
        update booking;
        Test.stopTest();

        List<Booking_Payment_Schedule__c> rows = [
            SELECT Milestone_Trigger__c FROM Booking_Payment_Schedule__c
            WHERE Booking__c = :booking.Id
            ORDER BY Sequence__c
        ];
        System.assertEquals(3, rows.size(), 'Inactive milestone should be skipped');
        for (Booking_Payment_Schedule__c r : rows) {
            System.assert(!r.Milestone_Trigger__c.contains('inactive'),
                'No row should reference the inactive milestone, got: ' + r.Milestone_Trigger__c);
        }
    }
}
