public with sharing class PaymentScheduleService {

    public static void onPaymentPlanSelected(List<Booking__c> newBookings, Map<Id, Booking__c> oldMap) {
        Set<Id> qualifyingBookingIds = new Set<Id>();
        for (Booking__c b : newBookings) {
            Booking__c oldB = oldMap.get(b.Id);
            if (oldB.Payment_Plan__c != b.Payment_Plan__c && b.Payment_Plan__c != null) {
                qualifyingBookingIds.add(b.Id);
            }
        }
        if (qualifyingBookingIds.isEmpty()) return;

        List<Booking__c> bookings = [
            SELECT Id, Payment_Plan__c, Agreement_Value__c, Booking_Date__c
            FROM Booking__c
            WHERE Id IN :qualifyingBookingIds
            WITH SECURITY_ENFORCED
        ];

        Set<Id> planIds = new Set<Id>();
        for (Booking__c b : bookings) {
            planIds.add(b.Payment_Plan__c);
        }

        Map<Id, List<Payment_Plan_Milestone__c>> milestonesByPlan = new Map<Id, List<Payment_Plan_Milestone__c>>();
        for (Payment_Plan_Milestone__c m : [
            SELECT Id, Payment_Plan__c, Sequence__c, Trigger__c, Trigger_Type__c,
                   Days_From_Trigger__c, Percentage__c, Description__c, Active__c
            FROM Payment_Plan_Milestone__c
            WHERE Payment_Plan__c IN :planIds AND Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Sequence__c ASC
        ]) {
            if (!milestonesByPlan.containsKey(m.Payment_Plan__c)) {
                milestonesByPlan.put(m.Payment_Plan__c, new List<Payment_Plan_Milestone__c>());
            }
            milestonesByPlan.get(m.Payment_Plan__c).add(m);
        }

        delete [SELECT Id FROM Booking_Payment_Schedule__c WHERE Booking__c IN :qualifyingBookingIds];

        List<Booking_Payment_Schedule__c> newRows = new List<Booking_Payment_Schedule__c>();
        for (Booking__c b : bookings) {
            List<Payment_Plan_Milestone__c> ms = milestonesByPlan.get(b.Payment_Plan__c);
            if (ms == null || ms.isEmpty()) continue;

            Decimal agreementValue = (b.Agreement_Value__c == null) ? 0 : b.Agreement_Value__c;
            Date bookingDate = b.Booking_Date__c;

            for (Payment_Plan_Milestone__c m : ms) {
                Decimal scheduledAmount = agreementValue * (m.Percentage__c / 100);
                Date expectedDate = null;
                if (m.Trigger_Type__c == 'Booking' || m.Trigger_Type__c == 'Time-Based') {
                    Integer days = (m.Days_From_Trigger__c == null) ? 0 : m.Days_From_Trigger__c.intValue();
                    expectedDate = bookingDate.addDays(days);
                }

                newRows.add(new Booking_Payment_Schedule__c(
                    Booking__c = b.Id,
                    Sequence__c = m.Sequence__c,
                    Milestone_Trigger__c = m.Trigger__c,
                    Percentage__c = m.Percentage__c,
                    Scheduled_Amount__c = scheduledAmount,
                    Expected_Date__c = expectedDate,
                    Status__c = 'Pending',
                    Notes__c = m.Description__c
                ));
            }
        }

        if (!newRows.isEmpty()) {
            insert newRows;
        }
    }
}
