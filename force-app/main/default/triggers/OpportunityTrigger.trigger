trigger OpportunityTrigger on Opportunity (after update) {
    new OpportunityTriggerHandler().run(
        Trigger.operationType,
        Trigger.new,
        Trigger.oldMap
    );
}
