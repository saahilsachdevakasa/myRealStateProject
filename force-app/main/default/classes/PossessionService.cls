public with sharing class PossessionService {

    public class PossessionRequest {
        @InvocableVariable(required=true label='Booking Id')
        public Id bookingId;
    }

    @InvocableMethod(label='Create Possession' description='Creates a Possession record for a Booking and transitions Booking_Status to Possession Ready.')
    public static List<Id> createPossessions(List<PossessionRequest> requests) {
        if (requests == null || requests.isEmpty()) return new List<Id>();

        Set<Id> bookingIds = new Set<Id>();
        for (PossessionRequest r : requests) {
            if (r.bookingId == null) {
                throw new AuraHandledException('Booking Id is required on every Possession request.');
            }
            bookingIds.add(r.bookingId);
        }

        Map<Id, Booking__c> bookingsById = new Map<Id, Booking__c>([
            SELECT Id, Name, Booking_Status__c, Possession__c
            FROM Booking__c
            WHERE Id IN :bookingIds
            WITH SECURITY_ENFORCED
        ]);

        Set<Id> bookingsWithExistingPossession = new Set<Id>();
        for (Possession__c existing : [
            SELECT Id, Booking__c FROM Possession__c
            WHERE Booking__c IN :bookingIds
        ]) {
            bookingsWithExistingPossession.add(existing.Booking__c);
        }

        List<Possession__c> newPossessions = new List<Possession__c>();
        Map<Id, Possession__c> possessionByBookingId = new Map<Id, Possession__c>();

        for (PossessionRequest r : requests) {
            Booking__c b = bookingsById.get(r.bookingId);
            if (b == null) {
                throw new AuraHandledException('Booking not found: ' + r.bookingId);
            }
            if (b.Booking_Status__c != 'Registered' && b.Booking_Status__c != 'Possession Ready') {
                throw new AuraHandledException(
                    'Cannot create Possession when Booking_Status is ' + b.Booking_Status__c +
                    '. Allowed: Registered, Possession Ready.'
                );
            }
            if (bookingsWithExistingPossession.contains(r.bookingId)) {
                throw new AuraHandledException('Possession already exists for Booking: ' + b.Name);
            }

            Possession__c p = new Possession__c(
                Booking__c = r.bookingId,
                Status__c = 'Ready to Offer'
            );
            newPossessions.add(p);
            possessionByBookingId.put(r.bookingId, p);
        }

        insert newPossessions;

        List<Booking__c> bookingsToUpdate = new List<Booking__c>();
        for (Id bid : bookingIds) {
            Possession__c created = possessionByBookingId.get(bid);
            bookingsToUpdate.add(new Booking__c(
                Id = bid,
                Booking_Status__c = 'Possession Ready',
                Possession__c = created.Id
            ));
        }
        update bookingsToUpdate;

        List<Id> possessionIds = new List<Id>();
        for (Possession__c p : newPossessions) possessionIds.add(p.Id);
        return possessionIds;
    }

    public static void onAfterUpdate(List<Possession__c> newList, Map<Id, Possession__c> oldMap) {
        Map<Id, String> bookingStatusByBookingId = new Map<Id, String>();

        for (Possession__c p : newList) {
            Possession__c oldP = oldMap.get(p.Id);
            if (p.Status__c == oldP.Status__c) continue;
            if (p.Booking__c == null) continue;

            if (p.Status__c == 'Handed Over') {
                bookingStatusByBookingId.put(p.Booking__c, 'Possessed');
            }
        }

        if (bookingStatusByBookingId.isEmpty()) return;

        List<Booking__c> bookingsToUpdate = new List<Booking__c>();
        for (Id bid : bookingStatusByBookingId.keySet()) {
            bookingsToUpdate.add(new Booking__c(
                Id = bid,
                Booking_Status__c = bookingStatusByBookingId.get(bid)
            ));
        }
        update bookingsToUpdate;
    }
}
