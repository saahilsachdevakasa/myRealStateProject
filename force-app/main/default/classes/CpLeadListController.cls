public with sharing class CpLeadListController {

    public class LeadData {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String status;
        @AuraEnabled public String projectName;
        @AuraEnabled public String sourceChannel;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<LeadData> getMyLeads() {
        Id cpId = CP_Scope.getCpAccountId();
        List<LeadData> result = new List<LeadData>();
        for (Lead l : [
            SELECT Id, Name, Phone, Email, Status, Source_Channel__c,
                   Project_Interest__r.Name, CreatedDate
            FROM Lead
            WHERE Source_CP__c = :cpId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            LeadData d = new LeadData();
            d.id = l.Id;
            d.name = l.Name;
            d.phone = l.Phone;
            d.email = l.Email;
            d.status = l.Status;
            d.projectName = (l.Project_Interest__c != null) ? l.Project_Interest__r.Name : null;
            d.sourceChannel = l.Source_Channel__c;
            d.createdDate = l.CreatedDate;
            result.add(d);
        }
        return result;
    }
}
