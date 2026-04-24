public class OpportunityNamingService {

    public static void onBeforeInsert(List<Opportunity> newOpps) {
        setNames(newOpps);
    }

    public static void onBeforeUpdate(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        List<Opportunity> toRename = new List<Opportunity>();
        for (Opportunity opp : newOpps) {
            Opportunity old = oldMap.get(opp.Id);
            if (opp.Project__c != old.Project__c || opp.AccountId != old.AccountId) {
                toRename.add(opp);
            }
        }
        if (!toRename.isEmpty()) {
            setNames(toRename);
        }
    }

    private static void setNames(List<Opportunity> opps) {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> projectIds = new Set<Id>();
        for (Opportunity opp : opps) {
            if (opp.AccountId != null) accountIds.add(opp.AccountId);
            if (opp.Project__c != null) projectIds.add(opp.Project__c);
        }

        Map<Id, Account> accounts = accountIds.isEmpty()
            ? new Map<Id, Account>()
            : new Map<Id, Account>([SELECT Id, Name FROM Account WHERE Id IN :accountIds]);

        Map<Id, Project__c> projects = projectIds.isEmpty()
            ? new Map<Id, Project__c>()
            : new Map<Id, Project__c>([SELECT Id, Project_Code__c FROM Project__c WHERE Id IN :projectIds]);

        for (Opportunity opp : opps) {
            String name = '';

            if (opp.AccountId != null && accounts.containsKey(opp.AccountId)) {
                name = accounts.get(opp.AccountId).Name;
            }

            if (opp.Project__c != null && projects.containsKey(opp.Project__c)) {
                name += (name == '' ? '' : ' - ') + projects.get(opp.Project__c).Project_Code__c;
            }

            if (String.isNotBlank(opp.Budget_Range__c)) {
                name += (name == '' ? '' : ' ') + opp.Budget_Range__c;
            }

            if (String.isNotBlank(name)) {
                opp.Name = name;
            }
        }
    }
}
