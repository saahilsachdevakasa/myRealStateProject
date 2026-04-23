trigger UnitTrigger on Unit__c (before update) {
    new UnitTriggerHandler().run(
        Trigger.operationType,
        Trigger.new,
        Trigger.oldMap
    );
}
