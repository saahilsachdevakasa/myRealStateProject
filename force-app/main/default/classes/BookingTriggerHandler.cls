public class BookingTriggerHandler {

    public void run(TriggerOperation operation, List<Booking__c> newList, Map<Id, Booking__c> oldMap) {
        if (operation == TriggerOperation.AFTER_INSERT) {
            CommissionService.accrueOnBooking(newList);
        } else if (operation == TriggerOperation.AFTER_UPDATE) {
            if (RecursionGuard.isFirstRun('Booking_afterUpdate')) {
                PaymentScheduleService.onPaymentPlanSelected(newList, oldMap);
                CommissionService.clawbackOnCancellation(newList, oldMap);
            }
        }
    }
}
