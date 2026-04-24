public class PossessionTriggerHandler {

    public void run(TriggerOperation operation, List<Possession__c> newList, Map<Id, Possession__c> oldMap) {
        if (operation == TriggerOperation.BEFORE_INSERT) {
            PossessionNamingService.onBeforeInsert(newList);
        } else if (operation == TriggerOperation.AFTER_UPDATE) {
            if (RecursionGuard.isFirstRun('Possession_afterUpdate')) {
                PossessionService.onAfterUpdate(newList, oldMap);
            }
        }
    }
}
