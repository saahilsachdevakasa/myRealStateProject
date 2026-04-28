public with sharing class CpPayoutsController {

    public class PayoutData {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String payoutMonth;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal gross;
        @AuraEnabled public Decimal gst;
        @AuraEnabled public Decimal tds;
        @AuraEnabled public Decimal net;
        @AuraEnabled public String paymentUTR;
    }

    @AuraEnabled(cacheable=true)
    public static List<PayoutData> getMyPayouts() {
        Id cpId = CP_Scope.getCpAccountId();
        List<PayoutData> result = new List<PayoutData>();
        for (Commission_Payout__c p : [
            SELECT Id, Name, Payout_Month__c, Status__c, Gross_Commission__c,
                   GST_Total__c, TDS_Total__c, Net_Payable__c, Payment_UTR__c
            FROM Commission_Payout__c
            WHERE Channel_Partner__c = :cpId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            PayoutData d = new PayoutData();
            d.id = p.Id;
            d.name = p.Name;
            d.payoutMonth = p.Payout_Month__c;
            d.status = p.Status__c;
            d.gross = p.Gross_Commission__c;
            d.gst = p.GST_Total__c;
            d.tds = p.TDS_Total__c;
            d.net = p.Net_Payable__c;
            d.paymentUTR = p.Payment_UTR__c;
            result.add(d);
        }
        return result;
    }
}
