public with sharing class RateCardService {

    @AuraEnabled(cacheable=true)
    public static Commission_Rate_Card__c getActiveRateCard(Id projectId, String cpTier) {
        if (projectId == null || String.isBlank(cpTier)) return null;

        List<Commission_Rate_Card__c> cards = [
            SELECT Id, Name, Project__c, CP_Tier__c,
                   Booking_Pct__c, Agreement_Pct__c, Registration_Pct__c,
                   Total_Pct__c, Effective_From__c, Effective_To__c, Active__c
            FROM Commission_Rate_Card__c
            WHERE Project__c = :projectId
              AND CP_Tier__c = :cpTier
              AND Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Effective_From__c DESC
            LIMIT 1
        ];

        return cards.isEmpty() ? null : cards[0];
    }

    public static Map<String, Commission_Rate_Card__c> getActiveRateCards(Set<Id> projectIds, Set<String> cpTiers) {
        Map<String, Commission_Rate_Card__c> result = new Map<String, Commission_Rate_Card__c>();
        if (projectIds == null || projectIds.isEmpty() || cpTiers == null || cpTiers.isEmpty()) {
            return result;
        }

        List<Commission_Rate_Card__c> cards = [
            SELECT Id, Name, Project__c, CP_Tier__c,
                   Booking_Pct__c, Agreement_Pct__c, Registration_Pct__c,
                   Total_Pct__c, Effective_From__c, Effective_To__c, Active__c
            FROM Commission_Rate_Card__c
            WHERE Project__c IN :projectIds
              AND CP_Tier__c IN :cpTiers
              AND Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Effective_From__c DESC
        ];

        for (Commission_Rate_Card__c card : cards) {
            String key = buildKey(card.Project__c, card.CP_Tier__c);
            if (!result.containsKey(key)) {
                result.put(key, card);
            }
        }
        return result;
    }

    public static String buildKey(Id projectId, String cpTier) {
        return String.valueOf(projectId) + '-' + cpTier;
    }
}
