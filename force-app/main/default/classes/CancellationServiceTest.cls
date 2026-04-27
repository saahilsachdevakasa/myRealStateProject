@IsTest(SeeAllData=false)
private class CancellationServiceTest {

    private class Setup {
        Project__c project;
        Tower__c tower;
        Unit__c unit;
        Account cp;
        Account buyer;
        Commission_Rate_Card__c rateCard;
        Opportunity opp;
        Booking__c booking;
    }

    // Builds a Booking via Closed-Won path (so BookingTrigger AFTER_INSERT
    // fires CommissionService.accrueOnBooking → Ledger entry exists for
    // clawback assertions). Resets RecursionGuard at end so subsequent
    // updates in the test re-fire trigger handlers.
    private static Setup seedBooking(String code, Boolean withCP) {
        Setup s = new Setup();
        s.project = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => code,
            'Name' => 'Project ' + code
        });
        s.tower = TestDataFactory.createTower(s.project.Id, null);
        s.unit = TestDataFactory.createUnit(s.tower.Id, new Map<String, Object>{
            'Unit_Status__c' => 'Blocked'
        });
        s.buyer = TestDataFactory.createAccount(new Map<String, Object>{
            'Name' => 'Buyer ' + code
        });

        Map<String, Object> oppOverrides = new Map<String, Object>{
            'StageName' => 'Token Paid',
            'Project__c' => s.project.Id,
            'Primary_Unit__c' => s.unit.Id,
            'EOI_Amount__c' => 100000,
            'Token_Amount__c' => 200000,
            'Quoted_Gross_Value__c' => 5000000,
            'Source_Channel__c' => 'Walk-in'
        };
        if (withCP) {
            s.cp = TestDataFactory.createCPAccount(new Map<String, Object>{
                'Name' => 'CP ' + code,
                'CP_Tier__c' => 'Platinum',
                'CP_Status__c' => 'Active',
                'GSTIN__c' => '27ABCDE1234F1Z5'
            });
            s.rateCard = TestDataFactory.createRateCard(s.project.Id, new Map<String, Object>{
                'CP_Tier__c' => 'Platinum',
                'Booking_Pct__c' => 2,
                'Agreement_Pct__c' => 1,
                'Registration_Pct__c' => 0.5,
                'Effective_From__c' => Date.today().addMonths(-3)
            });
            oppOverrides.put('Source_Channel__c', 'CP');
            oppOverrides.put('Source_CP__c', s.cp.Id);
        }
        s.opp = TestDataFactory.createOpportunity(s.buyer.Id, oppOverrides);
        s.opp.StageName = 'Closed Won (Booked)';
        update s.opp;

        Opportunity refreshed = [SELECT Booking__c FROM Opportunity WHERE Id = :s.opp.Id];
        s.booking = [
            SELECT Id, Name, Booking_Status__c, Total_Paid__c, Unit__c, Refund_Amount__c
            FROM Booking__c WHERE Id = :refreshed.Booking__c
        ];
        RecursionGuard.resetAll();
        return s;
    }

    private static CancellationService.CancellationRequest req(Id bookingId, String reason, Decimal pct) {
        CancellationService.CancellationRequest r = new CancellationService.CancellationRequest();
        r.bookingId = bookingId;
        r.reason = reason;
        r.forfeiturePercent = pct;
        return r;
    }

    @IsTest
    static void testCancelBooking_HappyPath() {
        Setup s = seedBooking('HAP', true);

        // Add an Agreement (Signed) so Step 3 has work to do
        Agreement__c ag = TestDataFactory.createAgreement(s.booking.Id, new Map<String, Object>{
            'Status__c' => 'Signed'
        });
        // Add a Receipt so Total_Paid > 0 (and refund calculation has substance)
        Receipt__c rcpt = TestDataFactory.createReceipt(s.booking.Id, new Map<String, Object>{
            'Amount__c' => 1000000
        });
        RecursionGuard.resetAll();

        Test.startTest();
        List<CancellationService.CancellationResult> results =
            CancellationService.cancelBookings(new List<CancellationService.CancellationRequest>{
                req(s.booking.Id, 'Buyer Withdrew', 10)
            });
        Test.stopTest();

        System.assertEquals(1, results.size());
        CancellationService.CancellationResult r = results[0];
        System.assertEquals(s.booking.Id, r.bookingId);
        System.assertEquals(true, r.agreementCancelled);
        // Refund = 1,000,000 * 90% = 900,000
        System.assertEquals(900000, r.refundAmount);

        // Booking
        Booking__c afterRec = [
            SELECT Booking_Status__c, Cancellation_Date__c, Cancellation_Reason__c, Refund_Amount__c
            FROM Booking__c WHERE Id = :s.booking.Id
        ];
        System.assertEquals('Cancelled', afterRec.Booking_Status__c);
        System.assertEquals(Date.today(), afterRec.Cancellation_Date__c);
        System.assertEquals('Buyer Withdrew', afterRec.Cancellation_Reason__c);
        System.assertEquals(900000, afterRec.Refund_Amount__c);

        // Agreement
        Agreement__c agAfter = [SELECT Status__c FROM Agreement__c WHERE Id = :ag.Id];
        System.assertEquals('Cancelled', agAfter.Status__c);

        // Unit
        Unit__c unitAfter = [SELECT Unit_Status__c FROM Unit__c WHERE Id = :s.unit.Id];
        System.assertEquals('Cancelled', unitAfter.Unit_Status__c);

        // Commission ledger clawback (E17 wired via BookingTrigger AFTER_UPDATE)
        List<Commission_Ledger__c> ledgers = [
            SELECT Status__c FROM Commission_Ledger__c WHERE Booking__c = :s.booking.Id
        ];
        System.assertEquals(1, ledgers.size(), 'Should have the Booking-milestone ledger from seed');
        System.assertEquals('Clawed Back', ledgers[0].Status__c);
    }

    @IsTest
    static void testCancelBooking_AlreadyCancelled() {
        Setup s = seedBooking('ACX', false);
        s.booking.Booking_Status__c = 'Cancelled';
        update s.booking;
        RecursionGuard.resetAll();

        Boolean caught = false;
        Test.startTest();
        try {
            CancellationService.cancelBookings(new List<CancellationService.CancellationRequest>{
                req(s.booking.Id, 'Other', 10)
            });
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Expected AuraHandledException for already-cancelled Booking');
    }

    @IsTest
    static void testCancelBooking_AlreadyPossessed() {
        Setup s = seedBooking('APS', false);
        s.booking.Booking_Status__c = 'Possessed';
        update s.booking;
        RecursionGuard.resetAll();

        Boolean caught = false;
        Test.startTest();
        try {
            CancellationService.cancelBookings(new List<CancellationService.CancellationRequest>{
                req(s.booking.Id, 'Other', 10)
            });
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Expected AuraHandledException for Possessed Booking');
    }

    @IsTest
    static void testCancelBooking_NoAgreementNoPossession() {
        Setup s = seedBooking('NAP', false);

        Test.startTest();
        List<CancellationService.CancellationResult> results =
            CancellationService.cancelBookings(new List<CancellationService.CancellationRequest>{
                req(s.booking.Id, 'Financing Failed', 10)
            });
        Test.stopTest();

        CancellationService.CancellationResult r = results[0];
        System.assertEquals(false, r.agreementCancelled, 'No agreement to cancel');
        System.assertEquals(false, r.possessionUpdated, 'No possession to update');
        System.assertEquals(0, r.demandsCancelled, 'No demands to cancel');

        Booking__c afterRec = [SELECT Booking_Status__c FROM Booking__c WHERE Id = :s.booking.Id];
        System.assertEquals('Cancelled', afterRec.Booking_Status__c);

        Unit__c unitAfter = [SELECT Unit_Status__c FROM Unit__c WHERE Id = :s.unit.Id];
        System.assertEquals('Cancelled', unitAfter.Unit_Status__c);
    }

    @IsTest
    static void testCancelBooking_ZeroForfeiture() {
        Setup s = seedBooking('ZRF', false);
        Receipt__c rcpt = TestDataFactory.createReceipt(s.booking.Id, new Map<String, Object>{
            'Amount__c' => 500000
        });
        RecursionGuard.resetAll();

        Test.startTest();
        List<CancellationService.CancellationResult> results =
            CancellationService.cancelBookings(new List<CancellationService.CancellationRequest>{
                req(s.booking.Id, 'Dispute', 0)
            });
        Test.stopTest();

        // Full refund — no forfeiture
        System.assertEquals(500000, results[0].refundAmount);
    }

    @IsTest
    static void testCancelBooking_WithPossessionInProgress() {
        Setup s = seedBooking('PSS', false);
        // Move Booking forward through the lifecycle to Possession Ready
        // so we can create a Possession in 'Snag Phase' (mid-stream).
        s.booking.Booking_Status__c = 'Possession Ready';
        update s.booking;
        RecursionGuard.resetAll();

        Possession__c poss = TestDataFactory.createPossession(s.booking.Id, new Map<String, Object>{
            'Status__c' => 'Snag Phase'
        });
        RecursionGuard.resetAll();

        Test.startTest();
        List<CancellationService.CancellationResult> results =
            CancellationService.cancelBookings(new List<CancellationService.CancellationRequest>{
                req(s.booking.Id, 'Other', 10)
            });
        Test.stopTest();

        System.assertEquals(true, results[0].possessionUpdated);
        Possession__c possAfter = [SELECT Status__c FROM Possession__c WHERE Id = :poss.Id];
        System.assertEquals('Delayed', possAfter.Status__c, 'Possession marked Delayed (no Cancelled value in picklist)');
    }

    @IsTest
    static void testCancelBooking_BulkOperation() {
        Setup s1 = seedBooking('BLA', false);
        Setup s2 = seedBooking('BLB', false);
        Setup s3 = seedBooking('BLC', false);

        Test.startTest();
        List<CancellationService.CancellationResult> results =
            CancellationService.cancelBookings(new List<CancellationService.CancellationRequest>{
                req(s1.booking.Id, 'Other', 10),
                req(s2.booking.Id, 'Other', 10),
                req(s3.booking.Id, 'Other', 10)
            });
        Test.stopTest();

        System.assertEquals(3, results.size());
        Set<Id> bookingIds = new Set<Id>{ s1.booking.Id, s2.booking.Id, s3.booking.Id };
        Integer cancelled = [
            SELECT COUNT() FROM Booking__c
            WHERE Id IN :bookingIds AND Booking_Status__c = 'Cancelled'
        ];
        System.assertEquals(3, cancelled, 'All 3 bookings cancelled');

        Set<Id> unitIds = new Set<Id>{ s1.unit.Id, s2.unit.Id, s3.unit.Id };
        Integer unitsCancelled = [
            SELECT COUNT() FROM Unit__c
            WHERE Id IN :unitIds AND Unit_Status__c = 'Cancelled'
        ];
        System.assertEquals(3, unitsCancelled, 'All 3 units released to Cancelled');
    }

    @IsTest
    static void testCancelBooking_InvalidReason() {
        Setup s = seedBooking('INV', false);
        Boolean caught = false;
        Test.startTest();
        try {
            CancellationService.cancelBookings(new List<CancellationService.CancellationRequest>{
                req(s.booking.Id, 'Random Made-Up Reason', 10)
            });
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Invalid reason should throw');
    }
}
