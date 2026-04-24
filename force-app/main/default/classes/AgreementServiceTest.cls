@IsTest(SeeAllData=false)
public class AgreementServiceTest {

    /** Build full chain: Project → Tower → Blocked Unit → Account → Opp → close-won → Booking. */
    private static Map<String, SObject> seedAndCloseWon(String projectCode) {
        RecursionGuard.resetAll();
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
            'Quoted_Gross_Value__c' => 1000000
        });
        opp.StageName = 'Closed Won (Booked)';
        RecursionGuard.resetAll();
        update opp;
        Opportunity refreshedOpp = [SELECT Booking__c FROM Opportunity WHERE Id = :opp.Id];
        Booking__c booking = [SELECT Id, Name, Booking_Status__c FROM Booking__c WHERE Id = :refreshedOpp.Booking__c];
        return new Map<String, SObject>{
            'project' => proj, 'tower' => tower, 'unit' => unit,
            'account' => acc, 'opp' => opp, 'booking' => booking
        };
    }

    @IsTest
    static void testCreateAgreement_HappyPath() {
        Map<String, SObject> chain = seedAndCloseWon('HPY');
        Booking__c booking = (Booking__c) chain.get('booking');

        AgreementService.AgreementRequest req = new AgreementService.AgreementRequest();
        req.bookingId = booking.Id;

        RecursionGuard.resetAll();

        Test.startTest();
        List<Id> agreementIds = AgreementService.createAgreements(
            new List<AgreementService.AgreementRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, agreementIds.size());
        Agreement__c a = [
            SELECT Id, Name, Booking__c, Status__c
            FROM Agreement__c WHERE Id = :agreementIds[0]
        ];
        System.assertEquals(booking.Id, a.Booking__c);
        System.assertEquals('Not Started', a.Status__c);
        System.assertEquals('AGR-' + booking.Name, a.Name);

        Booking__c refreshed = [SELECT Booking_Status__c, Agreement__c FROM Booking__c WHERE Id = :booking.Id];
        System.assertEquals('Agreement Pending', refreshed.Booking_Status__c);
        System.assertEquals(a.Id, refreshed.Agreement__c);
    }

    @IsTest
    static void testCreateAgreement_DuplicateRejected() {
        Map<String, SObject> chain = seedAndCloseWon('DUP');
        Booking__c booking = (Booking__c) chain.get('booking');

        TestDataFactory.createAgreement(booking.Id, null);

        AgreementService.AgreementRequest req = new AgreementService.AgreementRequest();
        req.bookingId = booking.Id;

        RecursionGuard.resetAll();

        Boolean caught = false;
        Test.startTest();
        try {
            AgreementService.createAgreements(
                new List<AgreementService.AgreementRequest>{ req }
            );
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Expected AuraHandledException for duplicate Agreement');
    }

    @IsTest
    static void testCreateAgreement_InvalidBookingStatus_Rejected() {
        Map<String, SObject> chain = seedAndCloseWon('INV');
        Booking__c booking = (Booking__c) chain.get('booking');
        booking.Booking_Status__c = 'Cancelled';
        RecursionGuard.resetAll();
        update booking;

        AgreementService.AgreementRequest req = new AgreementService.AgreementRequest();
        req.bookingId = booking.Id;

        RecursionGuard.resetAll();

        Boolean caught = false;
        Test.startTest();
        try {
            AgreementService.createAgreements(
                new List<AgreementService.AgreementRequest>{ req }
            );
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Expected AuraHandledException for invalid Booking_Status');
    }

    @IsTest
    static void testAgreementSigned_UpdatesBookingStatus() {
        Map<String, SObject> chain = seedAndCloseWon('SIG');
        Booking__c booking = (Booking__c) chain.get('booking');

        Agreement__c a = TestDataFactory.createAgreement(booking.Id, null);

        booking.Booking_Status__c = 'Agreement Pending';
        booking.Agreement__c = a.Id;
        RecursionGuard.resetAll();
        update booking;

        a.Status__c = 'Signed';
        a.Signed_Date__c = Date.today();
        RecursionGuard.resetAll();

        Test.startTest();
        update a;
        Test.stopTest();

        Booking__c refreshed = [SELECT Booking_Status__c FROM Booking__c WHERE Id = :booking.Id];
        System.assertEquals('Agreement Signed', refreshed.Booking_Status__c);
    }

    @IsTest
    static void testAgreementExecuted_UpdatesBookingStatus() {
        Map<String, SObject> chain = seedAndCloseWon('EXC');
        Booking__c booking = (Booking__c) chain.get('booking');

        Agreement__c a = TestDataFactory.createAgreement(booking.Id, new Map<String, Object>{
            'Status__c' => 'Signed',
            'Signed_Date__c' => Date.today().addDays(-10)
        });

        booking.Booking_Status__c = 'Agreement Signed';
        booking.Agreement__c = a.Id;
        RecursionGuard.resetAll();
        update booking;

        a.Status__c = 'Executed';
        a.Registration_Date__c = Date.today();
        RecursionGuard.resetAll();

        Test.startTest();
        update a;
        Test.stopTest();

        Booking__c refreshed = [SELECT Booking_Status__c FROM Booking__c WHERE Id = :booking.Id];
        System.assertEquals('Registered', refreshed.Booking_Status__c);
    }

    @IsTest
    static void testAgreementOtherStatusChange_NoBookingUpdate() {
        Map<String, SObject> chain = seedAndCloseWon('OTH');
        Booking__c booking = (Booking__c) chain.get('booking');

        Agreement__c a = TestDataFactory.createAgreement(booking.Id, null);

        booking.Booking_Status__c = 'Agreement Pending';
        booking.Agreement__c = a.Id;
        RecursionGuard.resetAll();
        update booking;

        a.Status__c = 'Draft Generated';
        a.Draft_Generated_Date__c = Date.today();
        RecursionGuard.resetAll();

        Test.startTest();
        update a;
        Test.stopTest();

        Booking__c refreshed = [SELECT Booking_Status__c FROM Booking__c WHERE Id = :booking.Id];
        System.assertEquals('Agreement Pending', refreshed.Booking_Status__c,
            'Booking status should not change on Draft Generated transition');
    }

    @IsTest
    static void testCreateAgreement_BulkOperation() {
        List<Booking__c> bookings = new List<Booking__c>();
        List<String> codes = new List<String>{ 'BLA', 'BLB', 'BLC' };
        for (String code : codes) {
            Map<String, SObject> chain = seedAndCloseWon(code);
            bookings.add((Booking__c) chain.get('booking'));
        }

        List<AgreementService.AgreementRequest> reqs = new List<AgreementService.AgreementRequest>();
        for (Booking__c b : bookings) {
            AgreementService.AgreementRequest r = new AgreementService.AgreementRequest();
            r.bookingId = b.Id;
            reqs.add(r);
        }

        RecursionGuard.resetAll();

        Test.startTest();
        List<Id> agreementIds = AgreementService.createAgreements(reqs);
        Test.stopTest();

        System.assertEquals(3, agreementIds.size());
        List<Agreement__c> agreements = [
            SELECT Name, Booking__c, Booking__r.Name FROM Agreement__c WHERE Id IN :agreementIds
        ];
        for (Agreement__c a : agreements) {
            System.assertEquals('AGR-' + a.Booking__r.Name, a.Name);
        }

        Integer pendingCount = [
            SELECT COUNT() FROM Booking__c
            WHERE Id IN :(new Map<Id, Booking__c>(bookings).keySet())
            AND Booking_Status__c = 'Agreement Pending'
        ];
        System.assertEquals(3, pendingCount);
    }
}
