trigger PossessionTrigger on Possession__c (before insert, after update) {
    new PossessionTriggerHandler().run(
        Trigger.operationType,
        Trigger.new,
        Trigger.oldMap
    );
}
