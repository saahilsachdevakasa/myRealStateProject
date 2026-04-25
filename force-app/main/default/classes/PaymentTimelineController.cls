public with sharing class PaymentTimelineController {

    @AuraEnabled(cacheable=true)
    public static List<MilestoneData> getPaymentTimeline(Id bookingId) {
        if (bookingId == null) return new List<MilestoneData>();

        List<Booking_Payment_Schedule__c> schedules = [
            SELECT Id, Sequence__c, Milestone_Trigger__c, Percentage__c,
                   Scheduled_Amount__c, Status__c, Expected_Date__c,
                   Actual_Demand__c, Actual_Demand__r.Name, Actual_Demand__r.Status__c,
                   Actual_Demand__r.Amount_Received__c, Actual_Demand__r.Net_Payable__c
            FROM Booking_Payment_Schedule__c
            WHERE Booking__c = :bookingId
            WITH SECURITY_ENFORCED
            ORDER BY Sequence__c ASC
        ];

        List<MilestoneData> rows = new List<MilestoneData>();
        for (Booking_Payment_Schedule__c s : schedules) {
            MilestoneData m = new MilestoneData();
            m.id = s.Id;
            m.sequence = (s.Sequence__c == null) ? 0 : s.Sequence__c.intValue();
            m.milestoneTrigger = s.Milestone_Trigger__c;
            m.percentage = s.Percentage__c;
            m.scheduledAmount = s.Scheduled_Amount__c;
            m.status = s.Status__c;
            m.expectedDate = s.Expected_Date__c;
            if (s.Actual_Demand__c != null) {
                m.demandId = s.Actual_Demand__c;
                m.demandName = s.Actual_Demand__r.Name;
                m.demandStatus = s.Actual_Demand__r.Status__c;
                m.amountReceived = s.Actual_Demand__r.Amount_Received__c;
                m.netPayable = s.Actual_Demand__r.Net_Payable__c;
            }
            rows.add(m);
        }
        return rows;
    }

    public class MilestoneData {
        @AuraEnabled public Id id;
        @AuraEnabled public Integer sequence;
        @AuraEnabled public String milestoneTrigger;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Decimal scheduledAmount;
        @AuraEnabled public String status;
        @AuraEnabled public Date expectedDate;
        @AuraEnabled public Id demandId;
        @AuraEnabled public String demandName;
        @AuraEnabled public String demandStatus;
        @AuraEnabled public Decimal amountReceived;
        @AuraEnabled public Decimal netPayable;
    }
}
