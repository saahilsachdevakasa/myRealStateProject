trigger AgreementTrigger on Agreement__c (before insert, after update) {
    new AgreementTriggerHandler().run(
        Trigger.operationType,
        Trigger.new,
        Trigger.oldMap
    );
}
