trigger DemandTrigger on Demand__c (before insert) {
    new DemandTriggerHandler().run(
        Trigger.operationType,
        Trigger.new
    );
}
