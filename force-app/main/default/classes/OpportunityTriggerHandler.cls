public class OpportunityTriggerHandler {

    public void run(TriggerOperation operation, List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        if (operation == TriggerOperation.AFTER_UPDATE) {
            if (RecursionGuard.isFirstRun('Opportunity_afterUpdate')) {
                BookingService.onOpportunityClosedWon(newList, oldMap);
            }
        }
    }
}
