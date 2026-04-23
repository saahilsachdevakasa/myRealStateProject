@IsTest(SeeAllData=false)
public class BookingServiceTest {

    private static Unit__c blockedUnitInProject(String projectCode) {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => projectCode
        });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        Unit__c u = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Status__c' => 'Blocked'
        });
        return u;
    }

    private static Opportunity oppReadyForCloseWon(Id accountId, Id unitId, Id projectId) {
        return TestDataFactory.createOpportunity(accountId, new Map<String, Object>{
            'StageName' => 'Token Paid',
            'Project__c' => projectId,
            'Primary_Unit__c' => unitId,
            'EOI_Amount__c' => 100000,
            'Token_Amount__c' => 200000,
            'Quoted_Gross_Value__c' => 5000000,
            'Source_Channel__c' => 'Walk-in'
        });
    }

    @IsTest
    static void testClosedWon_CreatesBooking() {
        Unit__c unit = blockedUnitInProject('TST');
        Tower__c tower = [SELECT Project__c FROM Tower__c WHERE Id = :unit.Tower__c LIMIT 1];
        Account acc = TestDataFactory.createAccount(null);
        Opportunity opp = oppReadyForCloseWon(acc.Id, unit.Id, tower.Project__c);

        Test.startTest();
        opp.StageName = 'Closed Won (Booked)';
        update opp;
        Test.stopTest();

        Opportunity refreshedOpp = [SELECT Id, Booking__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, refreshedOpp.Booking__c, 'Opportunity.Booking__c should be set');

        Booking__c booking = [
            SELECT Id, Name, Booking_Status__c, Booking_Date__c, Opportunity__c, Unit__c,
                   Primary_Buyer__c, RM_At_Booking__c, OwnerId, Source_Channel__c,
                   BSP_at_Booking__c, Quoted_Gross_Value__c
            FROM Booking__c
            WHERE Id = :refreshedOpp.Booking__c
        ];
        String yearStr = String.valueOf(Date.today().year()).right(2);
        System.assertEquals('BKG-TST-' + yearStr + '-0001', booking.Name);
        System.assertEquals('Confirmed', booking.Booking_Status__c);
        System.assertEquals(Date.today(), booking.Booking_Date__c);
        System.assertEquals(opp.Id, booking.Opportunity__c);
        System.assertEquals(unit.Id, booking.Unit__c);
        System.assertEquals(acc.Id, booking.Primary_Buyer__c);
        System.assertEquals(UserInfo.getUserId(), booking.RM_At_Booking__c);
        System.assertEquals('Walk-in', booking.Source_Channel__c);
        System.assertEquals(5000000, booking.Quoted_Gross_Value__c);

        Group psQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Post_Sales_Queue' LIMIT 1];
        System.assertEquals(psQueue.Id, booking.OwnerId, 'Booking owner should be Post_Sales_Queue');

        Unit__c refreshedUnit = [SELECT Id, Unit_Status__c, Active_Booking__c FROM Unit__c WHERE Id = :unit.Id];
        System.assertEquals('Booked', refreshedUnit.Unit_Status__c);
        System.assertEquals(booking.Id, refreshedUnit.Active_Booking__c);
    }

    @IsTest
    static void testClosedWon_UnitNotBlocked_Fails() {
        Project__c proj = TestDataFactory.createProject(null);
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        Unit__c availableUnit = TestDataFactory.createUnit(tower.Id, null);
        Account acc = TestDataFactory.createAccount(null);
        Opportunity opp = oppReadyForCloseWon(acc.Id, availableUnit.Id, proj.Id);

        Boolean caught = false;
        Test.startTest();
        try {
            opp.StageName = 'Closed Won (Booked)';
            update opp;
        } catch (DmlException e) {
            caught = true;
            System.assert(e.getMessage().contains('Blocked'),
                'Expected Booking VR error mentioning Blocked, got: ' + e.getMessage());
        }
        Test.stopTest();

        System.assert(caught, 'Expected DmlException when Unit is not Blocked at booking time');
    }

    @IsTest
    static void testClosedWon_NoDoubleBooking() {
        Unit__c unit = blockedUnitInProject('TST');
        Tower__c tower = [SELECT Project__c FROM Tower__c WHERE Id = :unit.Tower__c LIMIT 1];
        Account acc = TestDataFactory.createAccount(null);
        Opportunity opp = oppReadyForCloseWon(acc.Id, unit.Id, tower.Project__c);

        opp.StageName = 'Closed Won (Booked)';
        update opp;

        Integer bookingCountAfterFirst = [SELECT COUNT() FROM Booking__c WHERE Opportunity__c = :opp.Id];
        System.assertEquals(1, bookingCountAfterFirst, 'First close-won should create exactly one Booking');

        RecursionGuard.resetAll();

        Test.startTest();
        Opportunity reread = [SELECT Id, StageName, Booking__c FROM Opportunity WHERE Id = :opp.Id];
        update reread;
        Test.stopTest();

        Integer bookingCountAfterSecond = [SELECT COUNT() FROM Booking__c WHERE Opportunity__c = :opp.Id];
        System.assertEquals(1, bookingCountAfterSecond, 'Re-saving the Opp should NOT create a second Booking');
    }

    @IsTest
    static void testClosedWon_BulkOperation() {
        List<String> codes = new List<String>{ 'TSA', 'TSB', 'TSC', 'TSD', 'TSE' };
        List<Opportunity> opps = new List<Opportunity>();
        Map<Id, String> oppToProjectCode = new Map<Id, String>();

        for (String code : codes) {
            Unit__c u = blockedUnitInProject(code);
            Tower__c tower = [SELECT Project__c FROM Tower__c WHERE Id = :u.Tower__c LIMIT 1];
            Account acc = TestDataFactory.createAccount(new Map<String, Object>{
                'Name' => 'Buyer ' + code
            });
            Opportunity o = oppReadyForCloseWon(acc.Id, u.Id, tower.Project__c);
            opps.add(o);
            oppToProjectCode.put(o.Id, code);
        }

        for (Opportunity o : opps) {
            o.StageName = 'Closed Won (Booked)';
        }

        Test.startTest();
        update opps;
        Test.stopTest();

        List<Booking__c> bookings = [
            SELECT Id, Name, Opportunity__c
            FROM Booking__c
            WHERE Opportunity__c IN :opps
        ];
        System.assertEquals(5, bookings.size(), 'Each Opp should produce 1 Booking');

        String yearStr = String.valueOf(Date.today().year()).right(2);
        for (Booking__c b : bookings) {
            String code = oppToProjectCode.get(b.Opportunity__c);
            System.assertEquals('BKG-' + code + '-' + yearStr + '-0001', b.Name,
                'Each project gets its own seq=0001');
        }
    }

    @IsTest
    static void testBookingName_SequentialInSameProject() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => 'PRK'
        });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        Unit__c unit1 = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 1,
            'Unit_Status__c' => 'Blocked'
        });
        Unit__c unit2 = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Number__c' => 2,
            'Unit_Status__c' => 'Blocked'
        });
        Account acc1 = TestDataFactory.createAccount(new Map<String, Object>{ 'Name' => 'Buyer 1' });
        Account acc2 = TestDataFactory.createAccount(new Map<String, Object>{ 'Name' => 'Buyer 2' });
        Opportunity opp1 = oppReadyForCloseWon(acc1.Id, unit1.Id, proj.Id);
        Opportunity opp2 = oppReadyForCloseWon(acc2.Id, unit2.Id, proj.Id);

        Test.startTest();
        opp1.StageName = 'Closed Won (Booked)';
        update opp1;

        RecursionGuard.resetAll();

        opp2.StageName = 'Closed Won (Booked)';
        update opp2;
        Test.stopTest();

        String yearStr = String.valueOf(Date.today().year()).right(2);
        Booking__c b1 = [SELECT Name FROM Booking__c WHERE Opportunity__c = :opp1.Id];
        Booking__c b2 = [SELECT Name FROM Booking__c WHERE Opportunity__c = :opp2.Id];
        System.assertEquals('BKG-PRK-' + yearStr + '-0001', b1.Name);
        System.assertEquals('BKG-PRK-' + yearStr + '-0002', b2.Name);
    }
}
