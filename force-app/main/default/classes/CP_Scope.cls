public with sharing class CP_Scope {

    @TestVisible
    private static Id testCpAccountId;

    public static Id getCpAccountId() {
        if (Test.isRunningTest() && testCpAccountId != null) {
            return testCpAccountId;
        }
        return currentCpAccountId();
    }

    public static Id currentCpAccountId() {
        Id userId = UserInfo.getUserId();
        List<User> users = [
            SELECT ContactId FROM User
            WHERE Id = :userId AND ContactId != null
            WITH SECURITY_ENFORCED LIMIT 1
        ];
        if (users.isEmpty() || users[0].ContactId == null) {
            throw new AuraHandledException(
                'Unable to determine your Channel Partner account. Please contact your administrator.'
            );
        }
        List<Contact> contacts = [
            SELECT AccountId FROM Contact
            WHERE Id = :users[0].ContactId
            WITH SECURITY_ENFORCED LIMIT 1
        ];
        if (contacts.isEmpty() || contacts[0].AccountId == null) {
            throw new AuraHandledException(
                'Your user is not linked to a Channel Partner account.'
            );
        }
        return contacts[0].AccountId;
    }
}
