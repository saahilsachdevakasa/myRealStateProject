public with sharing class ProjectInventoryController {

    @AuraEnabled(cacheable=true)
    public static InventoryData getInventoryData(Id projectId) {
        if (projectId == null) return null;

        InventoryData d = new InventoryData();
        d.totalUnits = 0;
        d.available = 0;
        d.blocked = 0;
        d.booked = 0;
        d.cancelled = 0;

        List<AggregateResult> rows = [
            SELECT Unit_Status__c status, COUNT(Id) cnt
            FROM Unit__c
            WHERE Tower__r.Project__c = :projectId
            GROUP BY Unit_Status__c
        ];

        for (AggregateResult r : rows) {
            String status = (String) r.get('status');
            Integer cnt = ((Decimal) r.get('cnt')).intValue();
            d.totalUnits += cnt;
            if (status == 'Available') d.available = cnt;
            else if (status == 'Blocked') d.blocked = cnt;
            else if (status == 'Booked') d.booked = cnt;
            else if (status == 'Cancelled') d.cancelled = cnt;
        }

        d.sellThroughPct = (d.totalUnits == 0)
            ? 0
            : (Decimal.valueOf(d.booked) / Decimal.valueOf(d.totalUnits) * 100).setScale(1);

        return d;
    }

    public class InventoryData {
        @AuraEnabled public Integer totalUnits;
        @AuraEnabled public Integer available;
        @AuraEnabled public Integer blocked;
        @AuraEnabled public Integer booked;
        @AuraEnabled public Integer cancelled;
        @AuraEnabled public Decimal sellThroughPct;
    }
}
