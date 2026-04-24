public with sharing class AgreementService {

    public class AgreementRequest {
        @InvocableVariable(required=true label='Booking Id')
        public Id bookingId;
    }

    @InvocableMethod(label='Create Agreement' description='Creates an Agreement record for a Booking and transitions Booking_Status to Agreement Pending.')
    public static List<Id> createAgreements(List<AgreementRequest> requests) {
        if (requests == null || requests.isEmpty()) return new List<Id>();

        Set<Id> bookingIds = new Set<Id>();
        for (AgreementRequest r : requests) {
            if (r.bookingId == null) {
                throw new AuraHandledException('Booking Id is required on every Agreement request.');
            }
            bookingIds.add(r.bookingId);
        }

        Map<Id, Booking__c> bookingsById = new Map<Id, Booking__c>([
            SELECT Id, Name, Booking_Status__c, Agreement__c
            FROM Booking__c
            WHERE Id IN :bookingIds
            WITH SECURITY_ENFORCED
        ]);

        Set<Id> bookingsWithExistingAgreement = new Set<Id>();
        for (Agreement__c existing : [
            SELECT Id, Booking__c FROM Agreement__c
            WHERE Booking__c IN :bookingIds
        ]) {
            bookingsWithExistingAgreement.add(existing.Booking__c);
        }

        List<Agreement__c> newAgreements = new List<Agreement__c>();
        Map<Id, Agreement__c> agreementByBookingId = new Map<Id, Agreement__c>();

        for (AgreementRequest r : requests) {
            Booking__c b = bookingsById.get(r.bookingId);
            if (b == null) {
                throw new AuraHandledException('Booking not found: ' + r.bookingId);
            }
            if (b.Booking_Status__c != 'Confirmed' && b.Booking_Status__c != 'Agreement Pending') {
                throw new AuraHandledException(
                    'Cannot create Agreement when Booking_Status is ' + b.Booking_Status__c +
                    '. Allowed: Confirmed, Agreement Pending.'
                );
            }
            if (bookingsWithExistingAgreement.contains(r.bookingId)) {
                throw new AuraHandledException('Agreement already exists for Booking: ' + b.Name);
            }

            Agreement__c a = new Agreement__c(
                Booking__c = r.bookingId,
                Status__c = 'Not Started'
            );
            newAgreements.add(a);
            agreementByBookingId.put(r.bookingId, a);
        }

        insert newAgreements;

        List<Booking__c> bookingsToUpdate = new List<Booking__c>();
        for (Id bid : bookingIds) {
            Agreement__c created = agreementByBookingId.get(bid);
            bookingsToUpdate.add(new Booking__c(
                Id = bid,
                Booking_Status__c = 'Agreement Pending',
                Agreement__c = created.Id
            ));
        }
        update bookingsToUpdate;

        List<Id> agreementIds = new List<Id>();
        for (Agreement__c a : newAgreements) agreementIds.add(a.Id);
        return agreementIds;
    }

    public static void onAfterUpdate(List<Agreement__c> newList, Map<Id, Agreement__c> oldMap) {
        Map<Id, String> bookingStatusByBookingId = new Map<Id, String>();

        for (Agreement__c a : newList) {
            Agreement__c oldA = oldMap.get(a.Id);
            if (a.Status__c == oldA.Status__c) continue;
            if (a.Booking__c == null) continue;

            if (a.Status__c == 'Signed') {
                bookingStatusByBookingId.put(a.Booking__c, 'Agreement Signed');
            } else if (a.Status__c == 'Executed') {
                bookingStatusByBookingId.put(a.Booking__c, 'Registered');
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
