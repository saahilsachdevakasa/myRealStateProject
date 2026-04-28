public with sharing class CpSubmitLeadController {

    public class ProjectOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    @AuraEnabled(cacheable=true)
    public static List<ProjectOption> getActiveProjects() {
        List<ProjectOption> options = new List<ProjectOption>();
        for (Project__c p : [
            SELECT Id, Name, Project_Code__c
            FROM Project__c
            WHERE Active_for_Bookings__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Name
        ]) {
            ProjectOption o = new ProjectOption();
            o.value = p.Id;
            o.label = p.Name + ' (' + p.Project_Code__c + ')';
            options.add(o);
        }
        return options;
    }

    @AuraEnabled
    public static Id submitLead(
        String firstName, String lastName, String phone, String email,
        Id projectId, List<String> unitPreferences, String notes
    ) {
        Id cpId = CP_Scope.getCpAccountId();
        if (String.isBlank(lastName)) {
            throw new AuraHandledException('Last Name is required.');
        }
        String company = (String.isNotBlank(firstName) ? firstName + ' ' : '') + lastName;
        String unitPref = (unitPreferences == null || unitPreferences.isEmpty())
            ? null : String.join(unitPreferences, ';');

        Lead l = new Lead(
            FirstName = firstName,
            LastName = lastName,
            Phone = phone,
            Email = email,
            Company = company,
            Source_Channel__c = 'CP',
            Source_CP__c = cpId,
            Project_Interest__c = projectId,
            Unit_Type_Preference__c = unitPref,
            Description = notes,
            Status = 'New'
        );
        insert l;
        return l.Id;
    }
}
