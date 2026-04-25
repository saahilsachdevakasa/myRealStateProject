public with sharing class BookingLifecycleController {

    @AuraEnabled(cacheable=true)
    public static BookingLifecycleData getLifecycleData(Id bookingId) {
        if (bookingId == null) return null;

        List<Booking__c> bookings = [
            SELECT Id, Name, Booking_Status__c, Booking_Date__c, Agreement__c, Possession__c,
                   Agreement__r.Status__c, Agreement__r.Signed_Date__c, Agreement__r.Registration_Date__c,
                   Possession__r.Status__c, Possession__r.Offered_Date__c, Possession__r.Keys_Handed_Date__c
            FROM Booking__c
            WHERE Id = :bookingId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (bookings.isEmpty()) return null;
        Booking__c b = bookings[0];

        BookingLifecycleData data = new BookingLifecycleData();
        data.currentStatus = b.Booking_Status__c;
        data.bookingDate = b.Booking_Date__c;
        if (b.Agreement__c != null) {
            data.agreementSignedDate = b.Agreement__r.Signed_Date__c;
            data.registrationDate = b.Agreement__r.Registration_Date__c;
        }
        if (b.Possession__c != null) {
            data.possessionOfferedDate = b.Possession__r.Offered_Date__c;
            data.handedOverDate = b.Possession__r.Keys_Handed_Date__c;
        }
        return data;
    }

    public class BookingLifecycleData {
        @AuraEnabled public String currentStatus;
        @AuraEnabled public Date bookingDate;
        @AuraEnabled public Date agreementSignedDate;
        @AuraEnabled public Date registrationDate;
        @AuraEnabled public Date possessionOfferedDate;
        @AuraEnabled public Date handedOverDate;
    }
}
