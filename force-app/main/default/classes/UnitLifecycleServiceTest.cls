@IsTest(SeeAllData=false)
public class UnitLifecycleServiceTest {

    @TestSetup
    static void setup() {
        Project__c proj = TestDataFactory.createProject(null);
        TestDataFactory.createTower(proj.Id, null);
    }

    private static Unit__c createUnitWithStatus(String status) {
        Tower__c tower = [SELECT Id FROM Tower__c LIMIT 1];
        return TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Status__c' => status
        });
    }

    @IsTest
    static void testValidTransition_AvailableToBlocked() {
        Unit__c u = createUnitWithStatus('Available');

        Test.startTest();
        u.Unit_Status__c = 'Blocked';
        update u;
        Test.stopTest();

        Unit__c refreshed = [
            SELECT Unit_Status__c, Status_History__c, Last_Status_Change__c
            FROM Unit__c WHERE Id = :u.Id
        ];
        System.assertEquals('Blocked', refreshed.Unit_Status__c);
        System.assertNotEquals(null, refreshed.Status_History__c, 'History should be written');
        System.assert(refreshed.Status_History__c.contains('Available → Blocked'),
            'History should contain transition line');
        System.assertNotEquals(null, refreshed.Last_Status_Change__c, 'Last_Status_Change should be set');
    }

    @IsTest
    static void testValidTransition_BlockedToAvailable() {
        Unit__c u = createUnitWithStatus('Blocked');
        u.Blocked_By__c = UserInfo.getUserId();
        u.Blocked_Until__c = Datetime.now().addHours(24);
        update u;

        Test.startTest();
        u.Unit_Status__c = 'Available';
        update u;
        Test.stopTest();

        Unit__c refreshed = [
            SELECT Unit_Status__c, Blocked_By__c, Blocked_Until__c, Active_Booking__c, Status_History__c
            FROM Unit__c WHERE Id = :u.Id
        ];
        System.assertEquals('Available', refreshed.Unit_Status__c);
        System.assertEquals(null, refreshed.Blocked_By__c, 'Blocked_By should be cleared');
        System.assertEquals(null, refreshed.Blocked_Until__c, 'Blocked_Until should be cleared');
        System.assertEquals(null, refreshed.Active_Booking__c, 'Active_Booking should be cleared');
        System.assert(refreshed.Status_History__c.contains('Blocked → Available'));
    }

    @IsTest
    static void testValidTransition_BlockedToBooked() {
        Unit__c u = createUnitWithStatus('Blocked');

        Test.startTest();
        u.Unit_Status__c = 'Booked';
        update u;
        Test.stopTest();

        Unit__c refreshed = [SELECT Unit_Status__c, Status_History__c FROM Unit__c WHERE Id = :u.Id];
        System.assertEquals('Booked', refreshed.Unit_Status__c);
        System.assert(refreshed.Status_History__c.contains('Blocked → Booked'));
    }

    @IsTest
    static void testValidTransition_BookedToCancelled() {
        Unit__c u = createUnitWithStatus('Booked');

        Test.startTest();
        u.Unit_Status__c = 'Cancelled';
        update u;
        Test.stopTest();

        Unit__c refreshed = [SELECT Unit_Status__c, Status_History__c FROM Unit__c WHERE Id = :u.Id];
        System.assertEquals('Cancelled', refreshed.Unit_Status__c);
        System.assert(refreshed.Status_History__c.contains('Booked → Cancelled'));
    }

    @IsTest
    static void testValidTransition_CancelledToAvailable() {
        Unit__c u = createUnitWithStatus('Cancelled');

        Test.startTest();
        u.Unit_Status__c = 'Available';
        update u;
        Test.stopTest();

        Unit__c refreshed = [SELECT Unit_Status__c, Status_History__c FROM Unit__c WHERE Id = :u.Id];
        System.assertEquals('Available', refreshed.Unit_Status__c);
        System.assert(refreshed.Status_History__c.contains('Cancelled → Available'));
    }

    @IsTest
    static void testInvalidTransition_AvailableToBooked() {
        Unit__c u = createUnitWithStatus('Available');

        Boolean caught = false;
        Test.startTest();
        try {
            u.Unit_Status__c = 'Booked';
            update u;
        } catch (DmlException e) {
            caught = true;
            System.assert(e.getMessage().contains('Invalid status transition'),
                'Expected Invalid-status-transition message, got: ' + e.getMessage());
        }
        Test.stopTest();

        System.assert(caught, 'Expected DmlException on invalid transition');
    }

    @IsTest
    static void testInvalidTransition_BookedToBlocked() {
        Unit__c u = createUnitWithStatus('Booked');

        Boolean caught = false;
        Test.startTest();
        try {
            u.Unit_Status__c = 'Blocked';
            update u;
        } catch (DmlException e) {
            caught = true;
            System.assert(e.getMessage().contains('Invalid status transition'),
                'Expected Invalid-status-transition message, got: ' + e.getMessage());
        }
        Test.stopTest();

        System.assert(caught, 'Expected DmlException on invalid transition');
    }

    @IsTest
    static void testStatusHistory_MultipleTransitions() {
        Unit__c u = createUnitWithStatus('Available');

        Test.startTest();
        u.Unit_Status__c = 'Blocked';
        update u;

        u.Unit_Status__c = 'Available';
        update u;

        u.Unit_Status__c = 'Blocked';
        update u;

        u.Unit_Status__c = 'Booked';
        update u;
        Test.stopTest();

        Unit__c refreshed = [SELECT Unit_Status__c, Status_History__c FROM Unit__c WHERE Id = :u.Id];
        System.assertEquals('Booked', refreshed.Unit_Status__c);
        System.assertNotEquals(null, refreshed.Status_History__c);
        Integer lineCount = refreshed.Status_History__c.split('\n').size();
        System.assertEquals(4, lineCount,
            'Expected 4 history lines, got: ' + refreshed.Status_History__c);
        System.assert(refreshed.Status_History__c.contains('Available → Blocked'));
        System.assert(refreshed.Status_History__c.contains('Blocked → Available'));
        System.assert(refreshed.Status_History__c.contains('Blocked → Booked'));
    }

    @IsTest
    static void testBulkTransitions() {
        Tower__c tower = [SELECT Id FROM Tower__c LIMIT 1];
        List<Unit__c> units = TestDataFactory.createUnits(tower.Id, 200, null);

        for (Unit__c u : units) {
            u.Unit_Status__c = 'Blocked';
        }

        Test.startTest();
        update units;
        Test.stopTest();

        List<Unit__c> refreshed = [
            SELECT Unit_Status__c, Status_History__c, Last_Status_Change__c
            FROM Unit__c WHERE Tower__c = :tower.Id
        ];
        System.assertEquals(200, refreshed.size());
        for (Unit__c u : refreshed) {
            System.assertEquals('Blocked', u.Unit_Status__c);
            System.assertNotEquals(null, u.Status_History__c);
            System.assert(u.Status_History__c.contains('Available → Blocked'));
            System.assertNotEquals(null, u.Last_Status_Change__c);
        }
    }
}
