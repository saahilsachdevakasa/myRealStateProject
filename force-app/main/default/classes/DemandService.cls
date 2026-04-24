public with sharing class DemandService {

    private static final Decimal AFFORDABLE_HOUSING_THRESHOLD = 4500000;
    private static final Decimal AFFORDABLE_GST_RATE = 1;
    private static final Decimal STANDARD_GST_RATE = 5;
    private static final Decimal POST_CC_GST_RATE = 0;
    private static final Decimal TDS_THRESHOLD = 5000000;
    private static final Decimal TDS_RATE = 1;
    private static final Integer DUE_DAYS = 15;

    public class DemandRequest {
        @InvocableVariable(required=true label='Payment Schedule Id')
        public Id paymentScheduleId;
    }

    @InvocableMethod(label='Raise Demand' description='Creates a Demand record from a Booking Payment Schedule milestone with computed GST and TDS.')
    public static List<Id> raiseDemands(List<DemandRequest> requests) {
        Set<Id> scheduleIds = new Set<Id>();
        for (DemandRequest r : requests) scheduleIds.add(r.paymentScheduleId);

        Map<Id, Booking_Payment_Schedule__c> schedulesById = new Map<Id, Booking_Payment_Schedule__c>([
            SELECT Id, Booking__c, Sequence__c, Milestone_Trigger__c, Percentage__c,
                   Scheduled_Amount__c, Status__c, Expected_Date__c,
                   Booking__r.Name, Booking__r.Agreement_Value__c,
                   Booking__r.Total_Consideration__c,
                   Booking__r.Unit__r.Tower__r.Project__r.CC_Received__c
            FROM Booking_Payment_Schedule__c
            WHERE Id IN :scheduleIds
            WITH SECURITY_ENFORCED
        ]);

        for (DemandRequest r : requests) {
            Booking_Payment_Schedule__c s = schedulesById.get(r.paymentScheduleId);
            if (s == null) {
                throw new AuraHandledException('Payment Schedule not found: ' + r.paymentScheduleId);
            }
            if (s.Status__c != 'Pending') {
                throw new AuraHandledException(
                    'Cannot raise demand: schedule milestone is already in status ' + s.Status__c
                );
            }
        }

        Set<Id> bookingIds = new Set<Id>();
        for (Booking_Payment_Schedule__c s : schedulesById.values()) {
            bookingIds.add(s.Booking__c);
        }
        Map<Id, Integer> demandCountByBooking = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Booking__c bookingId, COUNT(Id) cnt
            FROM Demand__c
            WHERE Booking__c IN :bookingIds
            GROUP BY Booking__c
        ]) {
            demandCountByBooking.put((Id) ar.get('bookingId'), (Integer) ar.get('cnt'));
        }

        Date today = Date.today();
        Date dueDate = today.addDays(DUE_DAYS);

        List<Demand__c> newDemands = new List<Demand__c>();
        Map<Id, Demand__c> demandByScheduleId = new Map<Id, Demand__c>();

        for (DemandRequest r : requests) {
            Booking_Payment_Schedule__c s = schedulesById.get(r.paymentScheduleId);
            Decimal principal = (s.Scheduled_Amount__c == null) ? 0 : s.Scheduled_Amount__c;
            Boolean ccReceived = (s.Booking__r.Unit__r.Tower__r.Project__r.CC_Received__c == true);
            Decimal agreementValue = (s.Booking__r.Agreement_Value__c == null) ? 0 : s.Booking__r.Agreement_Value__c;
            Decimal totalConsideration = (s.Booking__r.Total_Consideration__c == null) ? 0 : s.Booking__r.Total_Consideration__c;

            Decimal gstRate;
            if (ccReceived) {
                gstRate = POST_CC_GST_RATE;
            } else if (agreementValue <= AFFORDABLE_HOUSING_THRESHOLD) {
                gstRate = AFFORDABLE_GST_RATE;
            } else {
                gstRate = STANDARD_GST_RATE;
            }
            Decimal gstAmount = principal * (gstRate / 100);

            Decimal tdsAmount = (totalConsideration > TDS_THRESHOLD)
                ? principal * (TDS_RATE / 100)
                : 0;

            Integer currentCount = demandCountByBooking.containsKey(s.Booking__c)
                ? demandCountByBooking.get(s.Booking__c) : 0;
            Integer nextSeq = currentCount + 1;
            demandCountByBooking.put(s.Booking__c, nextSeq);

            Demand__c d = new Demand__c(
                Booking__c = s.Booking__c,
                Payment_Schedule__c = s.Id,
                Demand_Seq__c = nextSeq,
                Raised_Date__c = today,
                Due_Date__c = dueDate,
                Principal_Amount__c = principal,
                GST_Amount__c = gstAmount,
                TDS_Amount__c = tdsAmount,
                Status__c = 'Raised',
                PDF_Generated__c = false,
                Sent_To_Buyer__c = false
            );
            newDemands.add(d);
            demandByScheduleId.put(s.Id, d);
        }

        insert newDemands;

        List<Booking_Payment_Schedule__c> schedulesToUpdate = new List<Booking_Payment_Schedule__c>();
        for (Booking_Payment_Schedule__c s : schedulesById.values()) {
            schedulesToUpdate.add(new Booking_Payment_Schedule__c(
                Id = s.Id,
                Status__c = 'Demand Raised',
                Demand_Raised_Date__c = today,
                Actual_Demand__c = demandByScheduleId.get(s.Id).Id
            ));
        }
        update schedulesToUpdate;

        List<Id> demandIds = new List<Id>();
        for (Demand__c d : newDemands) demandIds.add(d.Id);
        return demandIds;
    }
}
