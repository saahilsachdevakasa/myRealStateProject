public with sharing class CpCommissionsController {

    public class LedgerData {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String bookingName;
        @AuraEnabled public String milestone;
        @AuraEnabled public Date milestoneDate;
        @AuraEnabled public Decimal basis;
        @AuraEnabled public Decimal ratePct;
        @AuraEnabled public Decimal gross;
        @AuraEnabled public Decimal gst;
        @AuraEnabled public Decimal tds;
        @AuraEnabled public Decimal net;
        @AuraEnabled public String status;
    }

    public class CommissionSummary {
        @AuraEnabled public List<LedgerData> entries;
        @AuraEnabled public Decimal totalGross;
        @AuraEnabled public Decimal totalNet;
        @AuraEnabled public Decimal totalAccrued;
        @AuraEnabled public Decimal totalPaid;
    }

    @AuraEnabled(cacheable=true)
    public static CommissionSummary getMyCommissions() {
        Id cpId = CP_Scope.getCpAccountId();
        CommissionSummary s = new CommissionSummary();
        s.entries = new List<LedgerData>();
        s.totalGross = 0;
        s.totalNet = 0;
        s.totalAccrued = 0;
        s.totalPaid = 0;

        for (Commission_Ledger__c c : [
            SELECT Id, Name, Booking__r.Name, Milestone__c, Milestone_Date__c,
                   Agreement_Value_Basis__c, Rate_Pct__c, Gross_Commission__c,
                   GST_On_Commission__c, TDS_On_Commission__c, Net_Payable__c,
                   Status__c
            FROM Commission_Ledger__c
            WHERE Channel_Partner__c = :cpId
            WITH SECURITY_ENFORCED
            ORDER BY Milestone_Date__c DESC NULLS LAST
            LIMIT 500
        ]) {
            LedgerData d = new LedgerData();
            d.id = c.Id;
            d.name = c.Name;
            d.bookingName = (c.Booking__c != null) ? c.Booking__r.Name : null;
            d.milestone = c.Milestone__c;
            d.milestoneDate = c.Milestone_Date__c;
            d.basis = c.Agreement_Value_Basis__c;
            d.ratePct = c.Rate_Pct__c;
            d.gross = c.Gross_Commission__c;
            d.gst = c.GST_On_Commission__c;
            d.tds = c.TDS_On_Commission__c;
            d.net = c.Net_Payable__c;
            d.status = c.Status__c;
            s.entries.add(d);

            Decimal gross = (c.Gross_Commission__c == null) ? 0 : c.Gross_Commission__c;
            Decimal net = (c.Net_Payable__c == null) ? 0 : c.Net_Payable__c;
            s.totalGross += gross;
            s.totalNet += net;
            if (c.Status__c == 'Accrued' || c.Status__c == 'Approved') s.totalAccrued += net;
            if (c.Status__c == 'Paid') s.totalPaid += net;
        }
        return s;
    }
}
