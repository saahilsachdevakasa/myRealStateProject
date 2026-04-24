public class OpportunityTriggerHandler {

    public void run(TriggerOperation operation, List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        if (operation == TriggerOperation.BEFORE_INSERT) {
            OpportunityNamingService.onBeforeInsert(newList);
        } else if (operation == TriggerOperation.BEFORE_UPDATE) {
            OpportunityNamingService.onBeforeUpdate(newList, oldMap);
        } else if (operation == TriggerOperation.AFTER_UPDATE) {
            if (RecursionGuard.isFirstRun('Opportunity_afterUpdate')) {
                BookingService.onOpportunityClosedWon(newList, oldMap);
            }
        }
    }
}
