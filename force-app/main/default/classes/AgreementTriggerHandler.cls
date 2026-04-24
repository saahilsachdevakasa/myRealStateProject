public class AgreementTriggerHandler {

    public void run(TriggerOperation operation, List<Agreement__c> newList, Map<Id, Agreement__c> oldMap) {
        if (operation == TriggerOperation.BEFORE_INSERT) {
            AgreementNamingService.onBeforeInsert(newList);
        } else if (operation == TriggerOperation.AFTER_UPDATE) {
            if (RecursionGuard.isFirstRun('Agreement_afterUpdate')) {
                AgreementService.onAfterUpdate(newList, oldMap);
            }
        }
    }
}
