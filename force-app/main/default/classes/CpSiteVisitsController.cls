public with sharing class CpSiteVisitsController {

    public class VisitData {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String projectName;
        @AuraEnabled public Datetime scheduledDateTime;
        @AuraEnabled public String status;
        @AuraEnabled public String outcome;
    }

    @AuraEnabled(cacheable=true)
    public static List<VisitData> getMySiteVisits() {
        Id cpId = CP_Scope.getCpAccountId();
        List<VisitData> result = new List<VisitData>();
        for (Site_Visit__c v : [
            SELECT Id, Name, Scheduled_DateTime__c, Status__c, Outcome__c,
                   Project__r.Name
            FROM Site_Visit__c
            WHERE Lead__r.Source_CP__c = :cpId
               OR Opportunity__r.Source_CP__c = :cpId
            WITH SECURITY_ENFORCED
            ORDER BY Scheduled_DateTime__c DESC
            LIMIT 200
        ]) {
            VisitData d = new VisitData();
            d.id = v.Id;
            d.name = v.Name;
            d.projectName = (v.Project__c != null) ? v.Project__r.Name : null;
            d.scheduledDateTime = v.Scheduled_DateTime__c;
            d.status = v.Status__c;
            d.outcome = v.Outcome__c;
            result.add(d);
        }
        return result;
    }
}
