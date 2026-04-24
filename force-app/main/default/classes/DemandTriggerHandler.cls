public class DemandTriggerHandler {

    public void run(TriggerOperation operation, List<Demand__c> newList) {
        if (operation == TriggerOperation.BEFORE_INSERT) {
            DemandNamingService.onBeforeInsert(newList);
        }
    }
}
