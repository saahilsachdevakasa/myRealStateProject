public class PossessionNamingService {

    public static void onBeforeInsert(List<Possession__c> newPossessions) {
        Set<Id> bookingIds = new Set<Id>();
        for (Possession__c p : newPossessions) {
            if (p.Booking__c != null) bookingIds.add(p.Booking__c);
        }
        if (bookingIds.isEmpty()) return;

        Map<Id, Booking__c> bookingsById = new Map<Id, Booking__c>([
            SELECT Id, Name FROM Booking__c
            WHERE Id IN :bookingIds
            WITH SECURITY_ENFORCED
        ]);

        for (Possession__c p : newPossessions) {
            Booking__c parent = bookingsById.get(p.Booking__c);
            if (parent == null) continue;
            p.Name = 'POS-' + parent.Name;
        }
    }
}
