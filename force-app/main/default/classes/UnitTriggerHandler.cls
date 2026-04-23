public class UnitTriggerHandler {

    public void run(TriggerOperation operation, List<Unit__c> newList, Map<Id, Unit__c> oldMap) {
        if (operation == TriggerOperation.BEFORE_UPDATE) {
            UnitLifecycleService.onBeforeUpdate(newList, oldMap);
        }
    }
}
