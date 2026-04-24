@IsTest(SeeAllData=false)
public class ReceiptAllocationServiceTest {

    /** Build full chain: Project → Tower → Blocked Unit → Account → Opp → close-won → Booking. */
    private static Map<String, SObject> seedAndCloseWon(String projectCode, Decimal quotedGrossValue) {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => projectCode,
            'CC_Received__c' => false
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

    /** Attach a payment plan with N equal milestones and raise demands for the first K schedule rows. */
    private static List<Demand__c> raiseDemandsFor(Booking__c booking, Integer milestoneCount, String planCode, Integer raiseCount) {
        Payment_Plan__c plan = TestDataFactory.createPaymentPlanWithMilestones(milestoneCount,
            new Map<String, Object>{ 'Plan_Code__c' => planCode });
        RecursionGuard.resetAll();
        booking.Payment_Plan__c = plan.Id;
        update booking;

        List<Booking_Payment_Schedule__c> schedules = [
            SELECT Id, Sequence__c
            FROM Booking_Payment_Schedule__c
            WHERE Booking__c = :booking.Id
            ORDER BY Sequence__c
        ];

        List<DemandService.DemandRequest> reqs = new List<DemandService.DemandRequest>();
        for (Integer i = 0; i < raiseCount; i++) {
            DemandService.DemandRequest r = new DemandService.DemandRequest();
            r.paymentScheduleId = schedules[i].Id;
            reqs.add(r);
        }
        RecursionGuard.resetAll();
        List<Id> demandIds = DemandService.raiseDemands(reqs);

        return [
            SELECT Id, Booking__c, Net_Payable__c, Amount_Received__c, Status__c, Principal_Amount__c
            FROM Demand__c WHERE Id IN :demandIds ORDER BY Demand_Seq__c
        ];
    }

    @IsTest
    static void testAllocateReceipt_HappyPath_FullPayment() {
        Map<String, SObject> chain = seedAndCloseWon('HPY', 1000000);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Demand__c> demands = raiseDemandsFor(booking, 1, 'HPP', 1);
        Demand__c demand = demands[0];
        Decimal netPayable = demand.Net_Payable__c;

        Receipt__c receipt = TestDataFactory.createReceipt(booking.Id, new Map<String, Object>{
            'Amount__c' => netPayable
        });

        ReceiptAllocationService.AllocationRequest req = new ReceiptAllocationService.AllocationRequest();
        req.receiptId = receipt.Id;
        req.demandId = demand.Id;
        req.amount = netPayable;

        Test.startTest();
        List<Id> allocIds = ReceiptAllocationService.allocateReceipts(
            new List<ReceiptAllocationService.AllocationRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, allocIds.size());
        Receipt_Allocation__c alloc = [
            SELECT Receipt__c, Demand__c, Amount_Allocated__c, Allocation_Type__c
            FROM Receipt_Allocation__c WHERE Id = :allocIds[0]
        ];
        System.assertEquals(receipt.Id, alloc.Receipt__c);
        System.assertEquals(demand.Id, alloc.Demand__c);
        System.assertEquals(netPayable, alloc.Amount_Allocated__c);
        System.assertEquals('Towards Demand', alloc.Allocation_Type__c);

        Demand__c d = [SELECT Amount_Received__c, Status__c FROM Demand__c WHERE Id = :demand.Id];
        System.assertEquals(netPayable, d.Amount_Received__c);
        System.assertEquals('Paid', d.Status__c);

        Receipt__c r = [SELECT Status__c, Reconciled_By__c FROM Receipt__c WHERE Id = :receipt.Id];
        System.assertEquals('Reconciled', r.Status__c);
        System.assertEquals(UserInfo.getUserId(), r.Reconciled_By__c);
    }

    @IsTest
    static void testAllocateReceipt_PartialPayment() {
        Map<String, SObject> chain = seedAndCloseWon('PRT', 1000000);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Demand__c> demands = raiseDemandsFor(booking, 1, 'PRP', 1);
        Demand__c demand = demands[0];
        Decimal netPayable = demand.Net_Payable__c;
        Decimal partial = (netPayable / 2).setScale(2);

        Receipt__c receipt = TestDataFactory.createReceipt(booking.Id, new Map<String, Object>{
            'Amount__c' => partial
        });

        ReceiptAllocationService.AllocationRequest req = new ReceiptAllocationService.AllocationRequest();
        req.receiptId = receipt.Id;
        req.demandId = demand.Id;
        req.amount = partial;

        Test.startTest();
        ReceiptAllocationService.allocateReceipts(
            new List<ReceiptAllocationService.AllocationRequest>{ req }
        );
        Test.stopTest();

        Demand__c d = [SELECT Amount_Received__c, Status__c, Outstanding__c FROM Demand__c WHERE Id = :demand.Id];
        System.assertEquals(partial, d.Amount_Received__c);
        System.assertEquals('Partial', d.Status__c);
        System.assertEquals(netPayable - partial, d.Outstanding__c);

        Receipt__c r = [SELECT Status__c FROM Receipt__c WHERE Id = :receipt.Id];
        System.assertEquals('Reconciled', r.Status__c, 'Receipt fully consumed → Reconciled');
    }

    @IsTest
    static void testAllocateReceipt_MultipleAllocationsOneDemand() {
        Map<String, SObject> chain = seedAndCloseWon('MUL', 1000000);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Demand__c> demands = raiseDemandsFor(booking, 1, 'MLP', 1);
        Demand__c demand = demands[0];
        Decimal netPayable = demand.Net_Payable__c;
        Decimal first = (netPayable / 2).setScale(2);
        Decimal second = netPayable - first;

        Receipt__c r1 = TestDataFactory.createReceipt(booking.Id, new Map<String, Object>{ 'Amount__c' => first });
        Receipt__c r2 = TestDataFactory.createReceipt(booking.Id, new Map<String, Object>{ 'Amount__c' => second });

        Test.startTest();
        ReceiptAllocationService.AllocationRequest a1 = new ReceiptAllocationService.AllocationRequest();
        a1.receiptId = r1.Id; a1.demandId = demand.Id; a1.amount = first;
        ReceiptAllocationService.allocateReceipts(new List<ReceiptAllocationService.AllocationRequest>{ a1 });

        Demand__c afterFirst = [SELECT Status__c FROM Demand__c WHERE Id = :demand.Id];
        System.assertEquals('Partial', afterFirst.Status__c);

        ReceiptAllocationService.AllocationRequest a2 = new ReceiptAllocationService.AllocationRequest();
        a2.receiptId = r2.Id; a2.demandId = demand.Id; a2.amount = second;
        ReceiptAllocationService.allocateReceipts(new List<ReceiptAllocationService.AllocationRequest>{ a2 });
        Test.stopTest();

        Demand__c afterSecond = [SELECT Amount_Received__c, Status__c FROM Demand__c WHERE Id = :demand.Id];
        System.assertEquals(netPayable, afterSecond.Amount_Received__c);
        System.assertEquals('Paid', afterSecond.Status__c);
    }

    @IsTest
    static void testAllocateReceipt_ExceedsReceiptBalance_Rejected() {
        Map<String, SObject> chain = seedAndCloseWon('XRB', 1000000);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Demand__c> demands = raiseDemandsFor(booking, 1, 'XRP', 1);

        Receipt__c receipt = TestDataFactory.createReceipt(booking.Id, new Map<String, Object>{
            'Amount__c' => 100000
        });
        TestDataFactory.createReceiptAllocation(receipt.Id, demands[0].Id, new Map<String, Object>{
            'Amount_Allocated__c' => 80000
        });

        ReceiptAllocationService.AllocationRequest req = new ReceiptAllocationService.AllocationRequest();
        req.receiptId = receipt.Id;
        req.demandId = demands[0].Id;
        req.amount = 30000;

        Boolean caught = false;
        Test.startTest();
        try {
            ReceiptAllocationService.allocateReceipts(
                new List<ReceiptAllocationService.AllocationRequest>{ req }
            );
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Expected AuraHandledException for exceeding Receipt balance');
    }

    @IsTest
    static void testAllocateReceipt_ExceedsDemandOutstanding_Rejected() {
        Map<String, SObject> chain = seedAndCloseWon('XDO', 1000000);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Demand__c> demands = raiseDemandsFor(booking, 1, 'XDP', 1);
        Decimal netPayable = demands[0].Net_Payable__c;

        Receipt__c receipt = TestDataFactory.createReceipt(booking.Id, new Map<String, Object>{
            'Amount__c' => netPayable + 100000
        });

        ReceiptAllocationService.AllocationRequest req = new ReceiptAllocationService.AllocationRequest();
        req.receiptId = receipt.Id;
        req.demandId = demands[0].Id;
        req.amount = netPayable + 50000;

        Boolean caught = false;
        Test.startTest();
        try {
            ReceiptAllocationService.allocateReceipts(
                new List<ReceiptAllocationService.AllocationRequest>{ req }
            );
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Expected AuraHandledException for exceeding Demand outstanding');
    }

    @IsTest
    static void testAllocateReceipt_CancelledDemand_Rejected() {
        Map<String, SObject> chain = seedAndCloseWon('CXD', 1000000);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Demand__c> demands = raiseDemandsFor(booking, 1, 'CXP', 1);

        Demand__c d = demands[0];
        d.Status__c = 'Cancelled';
        update d;

        Receipt__c receipt = TestDataFactory.createReceipt(booking.Id, new Map<String, Object>{
            'Amount__c' => 100000
        });

        ReceiptAllocationService.AllocationRequest req = new ReceiptAllocationService.AllocationRequest();
        req.receiptId = receipt.Id;
        req.demandId = d.Id;
        req.amount = 50000;

        Boolean caught = false;
        Test.startTest();
        try {
            ReceiptAllocationService.allocateReceipts(
                new List<ReceiptAllocationService.AllocationRequest>{ req }
            );
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Expected AuraHandledException for Cancelled Demand');
    }

    @IsTest
    static void testAllocateReceipt_BulkOperation() {
        Map<String, SObject> chain = seedAndCloseWon('BLK', 3000000);
        Booking__c booking = (Booking__c) chain.get('booking');
        List<Demand__c> demands = raiseDemandsFor(booking, 3, 'BKP', 3);

        List<Receipt__c> receipts = new List<Receipt__c>();
        for (Integer i = 0; i < 3; i++) {
            receipts.add(TestDataFactory.createReceipt(booking.Id, new Map<String, Object>{
                'Amount__c' => demands[i].Net_Payable__c
            }));
        }

        List<ReceiptAllocationService.AllocationRequest> reqs = new List<ReceiptAllocationService.AllocationRequest>();
        for (Integer i = 0; i < 3; i++) {
            ReceiptAllocationService.AllocationRequest r = new ReceiptAllocationService.AllocationRequest();
            r.receiptId = receipts[i].Id;
            r.demandId = demands[i].Id;
            r.amount = demands[i].Net_Payable__c;
            reqs.add(r);
        }

        Test.startTest();
        List<Id> allocIds = ReceiptAllocationService.allocateReceipts(reqs);
        Test.stopTest();

        System.assertEquals(3, allocIds.size());

        Integer paidCount = [
            SELECT COUNT() FROM Demand__c
            WHERE Booking__c = :booking.Id AND Status__c = 'Paid'
        ];
        System.assertEquals(3, paidCount, 'All 3 demands should be Paid');

        Integer reconciledCount = [
            SELECT COUNT() FROM Receipt__c
            WHERE Booking__c = :booking.Id AND Status__c = 'Reconciled'
        ];
        System.assertEquals(3, reconciledCount, 'All 3 receipts should be Reconciled');
    }

    @IsTest
    static void testAdvancePayment_NoDemand() {
        Map<String, SObject> chain = seedAndCloseWon('ADV', 1000000);
        Booking__c booking = (Booking__c) chain.get('booking');

        Receipt__c receipt = TestDataFactory.createReceipt(booking.Id, new Map<String, Object>{
            'Amount__c' => 50000
        });

        ReceiptAllocationService.AllocationRequest req = new ReceiptAllocationService.AllocationRequest();
        req.receiptId = receipt.Id;
        req.demandId = null;
        req.amount = 50000;
        req.allocationType = 'Advance';

        Test.startTest();
        List<Id> allocIds = ReceiptAllocationService.allocateReceipts(
            new List<ReceiptAllocationService.AllocationRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, allocIds.size());
        Receipt_Allocation__c alloc = [
            SELECT Demand__c, Allocation_Type__c, Amount_Allocated__c
            FROM Receipt_Allocation__c WHERE Id = :allocIds[0]
        ];
        System.assertEquals(null, alloc.Demand__c);
        System.assertEquals('Advance', alloc.Allocation_Type__c);
        System.assertEquals(50000, alloc.Amount_Allocated__c);

        Receipt__c r = [SELECT Status__c FROM Receipt__c WHERE Id = :receipt.Id];
        System.assertEquals('Reconciled', r.Status__c);
    }
}
