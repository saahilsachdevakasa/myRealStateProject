public with sharing class UnitBlockingService {

    public class BlockRequest {
        @InvocableVariable(required=true label='Unit Id')
        public Id unitId;

        @InvocableVariable(required=true label='Duration (Hours)')
        public Integer durationHours;
    }

    @InvocableMethod(label='Block Unit' description='Marks a Unit as Blocked by the current user for the given duration.')
    public static void blockUnit(List<BlockRequest> requests) {
        Set<Id> unitIds = new Set<Id>();
        for (BlockRequest r : requests) {
            unitIds.add(r.unitId);
        }

        Map<Id, Unit__c> unitsById = new Map<Id, Unit__c>([
            SELECT Id, Unit_Status__c
            FROM Unit__c
            WHERE Id IN :unitIds
            WITH SECURITY_ENFORCED
        ]);

        List<Unit__c> toUpdate = new List<Unit__c>();
        Id runningUser = UserInfo.getUserId();
        DateTime nowTs = System.now();

        for (BlockRequest r : requests) {
            if (!unitsById.containsKey(r.unitId)) {
                throw new AuraHandledException('Unit not found.');
            }
            Unit__c current = unitsById.get(r.unitId);
            if (current.Unit_Status__c != 'Available' && current.Unit_Status__c != 'Blocked') {
                throw new AuraHandledException(
                    'Cannot block unit ' + r.unitId + ': current status is ' + current.Unit_Status__c +
                    '. Only Available or Blocked units can be blocked.'
                );
            }
            toUpdate.add(new Unit__c(
                Id = r.unitId,
                Unit_Status__c = 'Blocked',
                Blocked_By__c = runningUser,
                Blocked_Until__c = nowTs.addHours(r.durationHours)
            ));
        }

        Database.update(toUpdate, true);
    }
}
