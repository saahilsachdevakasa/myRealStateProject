@IsTest(SeeAllData=false)
public class PossessionServiceTest {

    /** Build full chain through close-won → Booking, then move it to 'Registered' status via Agreement.Status='Executed'. */
    private static Map<String, SObject> seedAndRegister(String projectCode) {
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

        Agreement__c agreement = TestDataFactory.createAgreement(booking.Id, new Map<String, Object>{
            'Status__c' => 'Signed',
            'Signed_Date__c' => Date.today().addDays(-10)
        });
        agreement.Status__c = 'Executed';
        agreement.Registration_Date__c = Date.today();
        RecursionGuard.resetAll();
        update agreement;

        Booking__c registeredBooking = [SELECT Id, Name, Booking_Status__c FROM Booking__c WHERE Id = :booking.Id];
        return new Map<String, SObject>{
            'project' => proj, 'tower' => tower, 'unit' => unit,
            'account' => acc, 'opp' => opp,
            'booking' => registeredBooking, 'agreement' => agreement
        };
    }

    @IsTest
    static void testCreatePossession_HappyPath() {
        Map<String, SObject> chain = seedAndRegister('HPY');
        Booking__c booking = (Booking__c) chain.get('booking');
        System.assertEquals('Registered', booking.Booking_Status__c, 'Setup precondition: Booking must be Registered');

        PossessionService.PossessionRequest req = new PossessionService.PossessionRequest();
        req.bookingId = booking.Id;

        RecursionGuard.resetAll();

        Test.startTest();
        List<Id> possessionIds = PossessionService.createPossessions(
            new List<PossessionService.PossessionRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, possessionIds.size());
        Possession__c p = [
            SELECT Id, Name, Booking__c, Status__c
            FROM Possession__c WHERE Id = :possessionIds[0]
        ];
        System.assertEquals(booking.Id, p.Booking__c);
        System.assertEquals('Ready to Offer', p.Status__c);
        System.assertEquals('POS-' + booking.Name, p.Name);

        Booking__c refreshed = [SELECT Booking_Status__c, Possession__c FROM Booking__c WHERE Id = :booking.Id];
        System.assertEquals('Possession Ready', refreshed.Booking_Status__c);
        System.assertEquals(p.Id, refreshed.Possession__c);
    }

    @IsTest
    static void testCreatePossession_DuplicateRejected() {
        Map<String, SObject> chain = seedAndRegister('DUP');
        Booking__c booking = (Booking__c) chain.get('booking');

        TestDataFactory.createPossession(booking.Id, null);

        PossessionService.PossessionRequest req = new PossessionService.PossessionRequest();
        req.bookingId = booking.Id;

        RecursionGuard.resetAll();

        Boolean caught = false;
        Test.startTest();
        try {
            PossessionService.createPossessions(
                new List<PossessionService.PossessionRequest>{ req }
            );
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Expected AuraHandledException for duplicate Possession');
    }

    @IsTest
    static void testCreatePossession_InvalidBookingStatus_Rejected() {
        RecursionGuard.resetAll();
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => 'INV',
            'CC_Received__c' => false
        });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        Unit__c unit = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Status__c' => 'Blocked'
        });
        Account acc = TestDataFactory.createAccount(new Map<String, Object>{ 'Name' => 'Buyer INV' });
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
        Booking__c booking = [SELECT Id, Booking_Status__c FROM Booking__c WHERE Id = :refreshedOpp.Booking__c];
        System.assertEquals('Confirmed', booking.Booking_Status__c, 'Booking should be Confirmed (not yet Registered)');

        PossessionService.PossessionRequest req = new PossessionService.PossessionRequest();
        req.bookingId = booking.Id;

        RecursionGuard.resetAll();

        Boolean caught = false;
        Test.startTest();
        try {
            PossessionService.createPossessions(
                new List<PossessionService.PossessionRequest>{ req }
            );
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Expected AuraHandledException for invalid Booking_Status (Confirmed)');
    }

    @IsTest
    static void testPossessionHandedOver_UpdatesBookingStatus() {
        Map<String, SObject> chain = seedAndRegister('HND');
        Booking__c booking = (Booking__c) chain.get('booking');

        Possession__c p = TestDataFactory.createPossession(booking.Id, null);

        booking.Booking_Status__c = 'Possession Ready';
        booking.Possession__c = p.Id;
        RecursionGuard.resetAll();
        update booking;

        p.Status__c = 'Handed Over';
        p.Keys_Handed_Date__c = Date.today();
        p.Handed_Over_By__c = UserInfo.getUserId();
        RecursionGuard.resetAll();

        Test.startTest();
        update p;
        Test.stopTest();

        Booking__c refreshed = [SELECT Booking_Status__c FROM Booking__c WHERE Id = :booking.Id];
        System.assertEquals('Possessed', refreshed.Booking_Status__c);
    }

    @IsTest
    static void testPossessionOtherStatus_NoBookingUpdate() {
        Map<String, SObject> chain = seedAndRegister('OTH');
        Booking__c booking = (Booking__c) chain.get('booking');

        Possession__c p = TestDataFactory.createPossession(booking.Id, null);

        booking.Booking_Status__c = 'Possession Ready';
        booking.Possession__c = p.Id;
        RecursionGuard.resetAll();
        update booking;

        p.Status__c = 'Offered';
        p.Offered_Date__c = Date.today();
        RecursionGuard.resetAll();

        Test.startTest();
        update p;

        p.Status__c = 'Snag Phase';
        RecursionGuard.resetAll();
        update p;
        Test.stopTest();

        Booking__c refreshed = [SELECT Booking_Status__c FROM Booking__c WHERE Id = :booking.Id];
        System.assertEquals('Possession Ready', refreshed.Booking_Status__c,
            'Booking status should not change on Offered or Snag Phase transitions');
    }

    @IsTest
    static void testCreatePossession_BulkOperation() {
        List<Booking__c> bookings = new List<Booking__c>();
        List<String> codes = new List<String>{ 'BLA', 'BLB', 'BLC' };
        for (String code : codes) {
            Map<String, SObject> chain = seedAndRegister(code);
            bookings.add((Booking__c) chain.get('booking'));
        }

        List<PossessionService.PossessionRequest> reqs = new List<PossessionService.PossessionRequest>();
        for (Booking__c b : bookings) {
            PossessionService.PossessionRequest r = new PossessionService.PossessionRequest();
            r.bookingId = b.Id;
            reqs.add(r);
        }

        RecursionGuard.resetAll();

        Test.startTest();
        List<Id> possessionIds = PossessionService.createPossessions(reqs);
        Test.stopTest();

        System.assertEquals(3, possessionIds.size());
        List<Possession__c> possessions = [
            SELECT Name, Booking__c, Booking__r.Name FROM Possession__c WHERE Id IN :possessionIds
        ];
        for (Possession__c p : possessions) {
            System.assertEquals('POS-' + p.Booking__r.Name, p.Name);
        }

        Integer readyCount = [
            SELECT COUNT() FROM Booking__c
            WHERE Id IN :(new Map<Id, Booking__c>(bookings).keySet())
            AND Booking_Status__c = 'Possession Ready'
        ];
        System.assertEquals(3, readyCount);
    }

    @IsTest
    static void testSnagItems_NativeRollups() {
        Map<String, SObject> chain = seedAndRegister('SNG');
        Booking__c booking = (Booking__c) chain.get('booking');

        Possession__c p = TestDataFactory.createPossession(booking.Id, null);

        Test.startTest();
        TestDataFactory.createSnagItem(p.Id, new Map<String, Object>{
            'Description__c' => 'Leaking tap in master bathroom',
            'Category__c' => 'Plumbing',
            'Severity__c' => 'Minor',
            'Status__c' => 'Open'
        });
        TestDataFactory.createSnagItem(p.Id, new Map<String, Object>{
            'Description__c' => 'Door handle loose',
            'Category__c' => 'Carpentry',
            'Severity__c' => 'Minor',
            'Status__c' => 'In Progress'
        });
        TestDataFactory.createSnagItem(p.Id, new Map<String, Object>{
            'Description__c' => 'Paint touch-up needed',
            'Category__c' => 'Paint',
            'Severity__c' => 'Minor',
            'Status__c' => 'Resolved'
        });
        Test.stopTest();

        Integer totalSnags = [SELECT COUNT() FROM Snag_Item__c WHERE Possession__c = :p.Id];
        System.assertEquals(3, totalSnags);

        Integer openSnags = [
            SELECT COUNT() FROM Snag_Item__c
            WHERE Possession__c = :p.Id AND Status__c IN ('Open', 'In Progress')
        ];
        System.assertEquals(2, openSnags);

        Possession__c refreshed = [SELECT Snag_Count__c, Open_Snag_Count__c FROM Possession__c WHERE Id = :p.Id];
        System.assertEquals(3, refreshed.Snag_Count__c, 'Native roll-up should count all 3 snags');
        System.assertEquals(2, refreshed.Open_Snag_Count__c, 'Native roll-up should count 2 open snags (Open + In Progress)');
    }
}
