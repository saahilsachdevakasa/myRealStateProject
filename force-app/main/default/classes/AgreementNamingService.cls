public class AgreementNamingService {

    public static void onBeforeInsert(List<Agreement__c> newAgreements) {
        Set<Id> bookingIds = new Set<Id>();
        for (Agreement__c a : newAgreements) {
            if (a.Booking__c != null) bookingIds.add(a.Booking__c);
        }
        if (bookingIds.isEmpty()) return;

        Map<Id, Booking__c> bookingsById = new Map<Id, Booking__c>([
            SELECT Id, Name FROM Booking__c
            WHERE Id IN :bookingIds
            WITH SECURITY_ENFORCED
        ]);

        for (Agreement__c a : newAgreements) {
            Booking__c parent = bookingsById.get(a.Booking__c);
            if (parent == null) continue;
            a.Name = 'AGR-' + parent.Name;
        }
    }
}
