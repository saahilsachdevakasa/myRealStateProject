@IsTest(SeeAllData=false)
public class UnitBlockingServiceTest {

    @TestSetup
    static void setup() {
        Project__c proj = TestDataFactory.createProject(null);
        TestDataFactory.createTower(proj.Id, null);
    }

    @IsTest
    static void testBlockUnit_HappyPath() {
        Tower__c tower = [SELECT Id FROM Tower__c LIMIT 1];
        Unit__c unit = TestDataFactory.createUnit(tower.Id, null);

        UnitBlockingService.BlockRequest req = new UnitBlockingService.BlockRequest();
        req.unitId = unit.Id;
        req.durationHours = 72;

        DateTime expected = System.now().addHours(72);

        Test.startTest();
        UnitBlockingService.blockUnit(new List<UnitBlockingService.BlockRequest>{ req });
        Test.stopTest();

        Unit__c refreshed = [
            SELECT Id, Unit_Status__c, Blocked_By__c, Blocked_Until__c
            FROM Unit__c
            WHERE Id = :unit.Id
        ];
        System.assertEquals('Blocked', refreshed.Unit_Status__c, 'Unit should be Blocked');
        System.assertEquals(UserInfo.getUserId(), refreshed.Blocked_By__c, 'Blocked_By should be running user');
        System.assertNotEquals(null, refreshed.Blocked_Until__c, 'Blocked_Until should be set');
        Long diffMs = Math.abs(refreshed.Blocked_Until__c.getTime() - expected.getTime());
        System.assert(diffMs < 5 * 60 * 1000, 'Blocked_Until should be within 5 minutes of expected (diff ms: ' + diffMs + ')');
    }

    @IsTest
    static void testBlockUnit_UnitNotFound() {
        Tower__c tower = [SELECT Id FROM Tower__c LIMIT 1];
        Unit__c unit = TestDataFactory.createUnit(tower.Id, null);
        Id deletedId = unit.Id;
        delete unit;

        UnitBlockingService.BlockRequest req = new UnitBlockingService.BlockRequest();
        req.unitId = deletedId;
        req.durationHours = 72;

        Boolean caught = false;
        Test.startTest();
        try {
            UnitBlockingService.blockUnit(new List<UnitBlockingService.BlockRequest>{ req });
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Expected AuraHandledException when Unit not found');
    }

    @IsTest
    static void testBlockUnit_BulkOperation() {
        Tower__c tower = [SELECT Id FROM Tower__c LIMIT 1];
        List<Unit__c> units = TestDataFactory.createUnits(tower.Id, 200, null);

        List<UnitBlockingService.BlockRequest> reqs = new List<UnitBlockingService.BlockRequest>();
        for (Unit__c u : units) {
            UnitBlockingService.BlockRequest r = new UnitBlockingService.BlockRequest();
            r.unitId = u.Id;
            r.durationHours = 48;
            reqs.add(r);
        }

        Test.startTest();
        UnitBlockingService.blockUnit(reqs);
        Test.stopTest();

        List<Unit__c> refreshed = [
            SELECT Id, Unit_Status__c, Blocked_By__c, Blocked_Until__c
            FROM Unit__c
            WHERE Tower__c = :tower.Id
        ];
        System.assertEquals(200, refreshed.size(), 'All 200 units should be retrieved');
        for (Unit__c u : refreshed) {
            System.assertEquals('Blocked', u.Unit_Status__c, 'Each Unit should be Blocked');
            System.assertEquals(UserInfo.getUserId(), u.Blocked_By__c, 'Each Blocked_By should be running user');
            System.assertNotEquals(null, u.Blocked_Until__c, 'Each Blocked_Until should be set');
        }
    }

    @IsTest
    static void testBlockUnit_AlreadyBlocked() {
        Tower__c tower = [SELECT Id FROM Tower__c LIMIT 1];
        Unit__c unit = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Status__c' => 'Blocked'
        });

        UnitBlockingService.BlockRequest req = new UnitBlockingService.BlockRequest();
        req.unitId = unit.Id;
        req.durationHours = 24;

        Test.startTest();
        UnitBlockingService.blockUnit(new List<UnitBlockingService.BlockRequest>{ req });
        Test.stopTest();

        Unit__c refreshed = [
            SELECT Id, Unit_Status__c, Blocked_By__c
            FROM Unit__c
            WHERE Id = :unit.Id
        ];
        System.assertEquals('Blocked', refreshed.Unit_Status__c, 'Unit should remain Blocked');
        System.assertEquals(UserInfo.getUserId(), refreshed.Blocked_By__c, 'Blocked_By should update to running user');
    }
}
