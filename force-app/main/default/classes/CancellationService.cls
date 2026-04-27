public with sharing class CancellationService {

    private static final Set<String> VALID_REASONS = new Set<String>{
        'Buyer Withdrew', 'Financing Failed', 'Dispute', 'Admin Cancelled', 'Other'
    };

    private static final Decimal DEFAULT_FORFEITURE_PCT = 10;

    public class CancellationRequest {
        @InvocableVariable(required=true label='Booking Id')
        public Id bookingId;
        @InvocableVariable(required=true label='Cancellation Reason')
        public String reason;
        @InvocableVariable(label='Forfeiture Percentage')
        public Decimal forfeiturePercent;
    }

    public class CancellationResult {
        @InvocableVariable
        public Id bookingId;
        @InvocableVariable
        public Decimal refundAmount;
        @InvocableVariable
        public Integer demandsCancelled;
        @InvocableVariable
        public Boolean agreementCancelled;
        @InvocableVariable
        public Boolean possessionUpdated;
    }

    @InvocableMethod(label='Cancel Booking' description='Cancels a Booking: closes open Demands, cancels Agreement, marks Possession Delayed, computes refund, updates Booking, releases Unit. Triggers commission clawback automatically.')
    public static List<CancellationResult> cancelBookings(List<CancellationRequest> requests) {
        if (requests == null || requests.isEmpty()) return new List<CancellationResult>();

        List<CancellationResult> results = new List<CancellationResult>();
        for (CancellationRequest req : requests) {
            results.add(cancelOne(req));
        }
        return results;
    }

    private static CancellationResult cancelOne(CancellationRequest req) {
        if (req.bookingId == null) {
            throw new AuraHandledException('Booking Id is required.');
        }
        if (String.isBlank(req.reason) || !VALID_REASONS.contains(req.reason)) {
            throw new AuraHandledException(
                'Cancellation Reason must be one of: ' + String.join(new List<String>(VALID_REASONS), ', ')
            );
        }
        Decimal forfeiturePct = (req.forfeiturePercent == null) ? DEFAULT_FORFEITURE_PCT : req.forfeiturePercent;
        if (forfeiturePct < 0 || forfeiturePct > 100) {
            throw new AuraHandledException('Forfeiture Percentage must be between 0 and 100.');
        }

        // STEP 1 — Validate
        Booking__c booking;
        try {
            booking = [
                SELECT Id, Name, Booking_Status__c, Total_Paid__c, Unit__c
                FROM Booking__c WHERE Id = :req.bookingId
                WITH SECURITY_ENFORCED LIMIT 1
            ];
        } catch (QueryException e) {
            throw new AuraHandledException('Booking not found: ' + req.bookingId);
        }
        if (booking.Booking_Status__c == 'Cancelled') {
            throw new AuraHandledException('Booking ' + booking.Name + ' is already cancelled.');
        }
        if (booking.Booking_Status__c == 'Possessed') {
            throw new AuraHandledException('Booking ' + booking.Name + ' is Possessed — cannot cancel after handover.');
        }

        CancellationResult result = new CancellationResult();
        result.bookingId = booking.Id;

        // STEP 2 — Cancel open Demands
        List<Demand__c> openDemands = [
            SELECT Id FROM Demand__c
            WHERE Booking__c = :booking.Id
              AND Status__c IN ('Raised', 'Partial', 'Overdue')
            WITH SECURITY_ENFORCED
        ];
        for (Demand__c d : openDemands) {
            d.Status__c = 'Cancelled';
            d.Cancellation_Reason__c = 'Booking Cancelled';
        }
        if (!openDemands.isEmpty()) update openDemands;
        result.demandsCancelled = openDemands.size();

        // STEP 3 — Cancel Agreement (if exists)
        List<Agreement__c> agreements = [
            SELECT Id, Status__c FROM Agreement__c
            WHERE Booking__c = :booking.Id AND Status__c != 'Cancelled'
            WITH SECURITY_ENFORCED
        ];
        if (!agreements.isEmpty()) {
            for (Agreement__c a : agreements) a.Status__c = 'Cancelled';
            update agreements;
            result.agreementCancelled = true;
        } else {
            result.agreementCancelled = false;
        }

        // STEP 4 — Mark Possession Delayed (no 'Cancelled' value in picklist)
        List<Possession__c> possessions = [
            SELECT Id, Status__c FROM Possession__c
            WHERE Booking__c = :booking.Id AND Status__c != 'Handed Over'
            WITH SECURITY_ENFORCED
        ];
        if (!possessions.isEmpty()) {
            for (Possession__c p : possessions) p.Status__c = 'Delayed';
            update possessions;
            result.possessionUpdated = true;
        } else {
            result.possessionUpdated = false;
        }

        // STEP 5 — Calculate refund
        Decimal totalPaid = (booking.Total_Paid__c == null) ? 0 : booking.Total_Paid__c;
        Decimal forfeiture = (totalPaid * forfeiturePct / 100).setScale(2);
        Decimal refund = totalPaid - forfeiture;
        result.refundAmount = refund;

        // STEP 6 — Update Booking (fires BookingTrigger AFTER_UPDATE → clawback)
        booking.Booking_Status__c = 'Cancelled';
        booking.Cancellation_Date__c = Date.today();
        booking.Cancellation_Reason__c = req.reason;
        booking.Refund_Amount__c = refund;
        update booking;

        // STEP 7 — Release Unit (Booked → Cancelled per E07 state machine)
        if (booking.Unit__c != null) {
            update new Unit__c(Id = booking.Unit__c, Unit_Status__c = 'Cancelled');
        }

        return result;
    }
}
