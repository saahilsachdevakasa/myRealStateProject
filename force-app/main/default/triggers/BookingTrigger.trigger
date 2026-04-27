trigger BookingTrigger on Booking__c (after insert, after update) {
    new BookingTriggerHandler().run(
        Trigger.operationType,
        Trigger.new,
        Trigger.oldMap
    );
}
