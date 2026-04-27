public class CommissionLedgerNamingService {

    public static void onBeforeInsert(List<Commission_Ledger__c> newEntries) {
        Set<Id> bookingIds = new Set<Id>();
        for (Commission_Ledger__c c : newEntries) {
            if (c.Booking__c != null) bookingIds.add(c.Booking__c);
        }
        if (bookingIds.isEmpty()) return;

        Map<Id, Booking__c> bookingsById = new Map<Id, Booking__c>([
            SELECT Id, Name FROM Booking__c
            WHERE Id IN :bookingIds
            WITH SECURITY_ENFORCED
        ]);

        Map<Id, Integer> existingCountByBooking = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Booking__c bid, COUNT(Id) cnt
            FROM Commission_Ledger__c
            WHERE Booking__c IN :bookingIds
            WITH SECURITY_ENFORCED
            GROUP BY Booking__c
        ]) {
            existingCountByBooking.put((Id) ar.get('bid'), ((Decimal) ar.get('cnt')).intValue());
        }

        Map<Id, Integer> inBatchOffsetByBooking = new Map<Id, Integer>();
        for (Commission_Ledger__c c : newEntries) {
            if (c.Booking__c == null) continue;
            Booking__c parent = bookingsById.get(c.Booking__c);
            if (parent == null) continue;

            Integer baseCount = existingCountByBooking.containsKey(c.Booking__c)
                ? existingCountByBooking.get(c.Booking__c) : 0;
            Integer offset = inBatchOffsetByBooking.containsKey(c.Booking__c)
                ? inBatchOffsetByBooking.get(c.Booking__c) : 0;

            Integer seq = baseCount + offset + 1;
            c.Name = 'CL-' + parent.Name + '-' + String.valueOf(seq).leftPad(2, '0');

            inBatchOffsetByBooking.put(c.Booking__c, offset + 1);
        }
    }
}
