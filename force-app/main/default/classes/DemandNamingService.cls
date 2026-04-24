public class DemandNamingService {

    public static void onBeforeInsert(List<Demand__c> newDemands) {
        Set<Id> bookingIds = new Set<Id>();
        for (Demand__c d : newDemands) {
            if (d.Booking__c != null) bookingIds.add(d.Booking__c);
        }
        if (bookingIds.isEmpty()) return;

        Map<Id, Booking__c> bookingsById = new Map<Id, Booking__c>([
            SELECT Id, Name FROM Booking__c
            WHERE Id IN :bookingIds
            WITH SECURITY_ENFORCED
        ]);

        for (Demand__c d : newDemands) {
            Booking__c parent = bookingsById.get(d.Booking__c);
            if (parent == null) continue;
            Integer seq = (d.Demand_Seq__c == null) ? 1 : d.Demand_Seq__c.intValue();
            d.Name = 'DM-' + parent.Name + '-' + String.valueOf(seq).leftPad(2, '0');
        }
    }
}
