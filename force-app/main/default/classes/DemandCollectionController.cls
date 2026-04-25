public with sharing class DemandCollectionController {

    @AuraEnabled(cacheable=true)
    public static CollectionData getCollectionData(Id bookingId) {
        if (bookingId == null) return null;

        CollectionData d = new CollectionData();
        d.totalDemanded = 0;
        d.totalGST = 0;
        d.totalTDS = 0;
        d.totalNetPayable = 0;
        d.totalReceived = 0;
        d.totalOutstanding = 0;
        d.demandCount = 0;
        d.paidCount = 0;
        d.pendingCount = 0;

        List<Demand__c> demands = [
            SELECT Id, Status__c, Principal_Amount__c, GST_Amount__c, TDS_Amount__c,
                   Net_Payable__c, Amount_Received__c, Outstanding__c
            FROM Demand__c
            WHERE Booking__c = :bookingId
            WITH SECURITY_ENFORCED
        ];

        for (Demand__c dm : demands) {
            d.demandCount++;
            d.totalDemanded += (dm.Principal_Amount__c == null ? 0 : dm.Principal_Amount__c);
            d.totalGST += (dm.GST_Amount__c == null ? 0 : dm.GST_Amount__c);
            d.totalTDS += (dm.TDS_Amount__c == null ? 0 : dm.TDS_Amount__c);
            d.totalNetPayable += (dm.Net_Payable__c == null ? 0 : dm.Net_Payable__c);
            d.totalReceived += (dm.Amount_Received__c == null ? 0 : dm.Amount_Received__c);
            d.totalOutstanding += (dm.Outstanding__c == null ? 0 : dm.Outstanding__c);
            if (dm.Status__c == 'Paid') d.paidCount++;
            else if (dm.Status__c == 'Raised' || dm.Status__c == 'Partial') d.pendingCount++;
        }

        return d;
    }

    public class CollectionData {
        @AuraEnabled public Decimal totalDemanded;
        @AuraEnabled public Decimal totalGST;
        @AuraEnabled public Decimal totalTDS;
        @AuraEnabled public Decimal totalNetPayable;
        @AuraEnabled public Decimal totalReceived;
        @AuraEnabled public Decimal totalOutstanding;
        @AuraEnabled public Integer demandCount;
        @AuraEnabled public Integer paidCount;
        @AuraEnabled public Integer pendingCount;
    }
}
