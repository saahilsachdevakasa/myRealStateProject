/**
 * @description Cancels Bookings and cascades the cancellation across open Demands,
 *              the Agreement, the Possession and the linked Unit.
 *
 *              Bulkified: every related record for the whole request list is hydrated
 *              up front with `Set<Id>`-keyed queries (4 SOQL total, regardless of
 *              request count), validation and field mutation happen in memory, and
 *              exactly one DML statement is issued per SObject type. Mirrors the
 *              bulkification pattern in `ReceiptAllocationService.allocateReceipts`.
 *
 *              The Booking update fires `BookingTrigger` AFTER_UPDATE, which drives
 *              the commission clawback.
 */
public with sharing class CancellationService {

    private static final Set<String> VALID_REASONS = new Set<String>{
        'Buyer Withdrew', 'Financing Failed', 'Dispute', 'Admin Cancelled', 'Other'
    };

    private static final Decimal DEFAULT_FORFEITURE_PCT = 10;

    private static final Set<String> OPEN_DEMAND_STATUSES = new Set<String>{
        'Raised', 'Partial', 'Overdue'
    };

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

    /**
     * @description Cancels every Booking in the request list.
     * @param requests One CancellationRequest per Booking to cancel.
     * @return One CancellationResult per request, in the same order as the input.
     */
    @InvocableMethod(label='Cancel Booking' description='Cancels a Booking: closes open Demands, cancels Agreement, marks Possession Delayed, computes refund, updates Booking, releases Unit. Triggers commission clawback automatically.')
    public static List<CancellationResult> cancelBookings(List<CancellationRequest> requests) {
        if (requests == null || requests.isEmpty()) return new List<CancellationResult>();

        // ---- PASS 1: request-level validation + Id harvest (no SOQL, no DML) ----
        Set<Id> bookingIds = new Set<Id>();
        for (CancellationRequest req : requests) {
            validateRequest(req);
            bookingIds.add(req.bookingId);
        }

        // ---- PASS 2: bulk-hydrate everything the whole batch needs (4 SOQL total) ----
        Map<Id, Booking__c> bookingsById = new Map<Id, Booking__c>([
            SELECT Id, Name, Booking_Status__c, Total_Paid__c, Unit__c
            FROM Booking__c WHERE Id IN :bookingIds
            WITH SECURITY_ENFORCED
        ]);

        Map<Id, List<Demand__c>> openDemandsByBooking = new Map<Id, List<Demand__c>>();
        for (Demand__c d : [
            SELECT Id, Booking__c FROM Demand__c
            WHERE Booking__c IN :bookingIds
              AND Status__c IN :OPEN_DEMAND_STATUSES
            WITH SECURITY_ENFORCED
        ]) {
            if (!openDemandsByBooking.containsKey(d.Booking__c)) {
                openDemandsByBooking.put(d.Booking__c, new List<Demand__c>());
            }
            openDemandsByBooking.get(d.Booking__c).add(d);
        }

        Map<Id, List<Agreement__c>> agreementsByBooking = new Map<Id, List<Agreement__c>>();
        for (Agreement__c a : [
            SELECT Id, Booking__c, Status__c FROM Agreement__c
            WHERE Booking__c IN :bookingIds AND Status__c != 'Cancelled'
            WITH SECURITY_ENFORCED
        ]) {
            if (!agreementsByBooking.containsKey(a.Booking__c)) {
                agreementsByBooking.put(a.Booking__c, new List<Agreement__c>());
            }
            agreementsByBooking.get(a.Booking__c).add(a);
        }

        Map<Id, List<Possession__c>> possessionsByBooking = new Map<Id, List<Possession__c>>();
        for (Possession__c p : [
            SELECT Id, Booking__c, Status__c FROM Possession__c
            WHERE Booking__c IN :bookingIds AND Status__c != 'Handed Over'
            WITH SECURITY_ENFORCED
        ]) {
            if (!possessionsByBooking.containsKey(p.Booking__c)) {
                possessionsByBooking.put(p.Booking__c, new List<Possession__c>());
            }
            possessionsByBooking.get(p.Booking__c).add(p);
        }

        // ---- PASS 3: per-request validation and in-memory mutation ----
        List<CancellationResult> results = new List<CancellationResult>();
        List<Demand__c> demandsToUpdate = new List<Demand__c>();
        List<Agreement__c> agreementsToUpdate = new List<Agreement__c>();
        List<Possession__c> possessionsToUpdate = new List<Possession__c>();
        Map<Id, Booking__c> bookingsToUpdate = new Map<Id, Booking__c>();
        Map<Id, Unit__c> unitsToUpdate = new Map<Id, Unit__c>();

        for (CancellationRequest req : requests) {
            // STEP 1 — Validate
            Booking__c booking = bookingsById.get(req.bookingId);
            if (booking == null) {
                throw new AuraHandledException('Booking not found: ' + req.bookingId);
            }
            // Status is mutated in memory at STEP 6 below, so a duplicate request for
            // the same Booking inside one invocation is rejected exactly as it was
            // when each request re-queried the Booking.
            if (booking.Booking_Status__c == 'Cancelled') {
                throw new AuraHandledException('Booking ' + booking.Name + ' is already cancelled.');
            }
            if (booking.Booking_Status__c == 'Possessed') {
                throw new AuraHandledException('Booking ' + booking.Name + ' is Possessed — cannot cancel after handover.');
            }

            Decimal forfeiturePct = (req.forfeiturePercent == null) ? DEFAULT_FORFEITURE_PCT : req.forfeiturePercent;

            CancellationResult result = new CancellationResult();
            result.bookingId = booking.Id;

            // STEP 2 — Cancel open Demands
            List<Demand__c> openDemands = openDemandsByBooking.containsKey(booking.Id)
                ? openDemandsByBooking.get(booking.Id) : new List<Demand__c>();
            for (Demand__c d : openDemands) {
                d.Status__c = 'Cancelled';
                d.Cancellation_Reason__c = 'Booking Cancelled';
            }
            demandsToUpdate.addAll(openDemands);
            result.demandsCancelled = openDemands.size();

            // STEP 3 — Cancel Agreement (if exists)
            List<Agreement__c> agreements = agreementsByBooking.containsKey(booking.Id)
                ? agreementsByBooking.get(booking.Id) : new List<Agreement__c>();
            if (!agreements.isEmpty()) {
                for (Agreement__c a : agreements) a.Status__c = 'Cancelled';
                agreementsToUpdate.addAll(agreements);
                result.agreementCancelled = true;
            } else {
                result.agreementCancelled = false;
            }

            // STEP 4 — Mark Possession Delayed (no 'Cancelled' value in picklist)
            List<Possession__c> possessions = possessionsByBooking.containsKey(booking.Id)
                ? possessionsByBooking.get(booking.Id) : new List<Possession__c>();
            if (!possessions.isEmpty()) {
                for (Possession__c p : possessions) p.Status__c = 'Delayed';
                possessionsToUpdate.addAll(possessions);
                result.possessionUpdated = true;
            } else {
                result.possessionUpdated = false;
            }

            // STEP 5 — Calculate refund
            Decimal totalPaid = (booking.Total_Paid__c == null) ? 0 : booking.Total_Paid__c;
            Decimal forfeiture = (totalPaid * forfeiturePct / 100).setScale(2);
            Decimal refund = totalPaid - forfeiture;
            result.refundAmount = refund;

            // STEP 6 — Stage the Booking update (fires BookingTrigger AFTER_UPDATE → clawback)
            booking.Booking_Status__c = 'Cancelled';
            booking.Cancellation_Date__c = Date.today();
            booking.Cancellation_Reason__c = req.reason;
            booking.Refund_Amount__c = refund;
            bookingsToUpdate.put(booking.Id, booking);

            // STEP 7 — Stage the Unit release (Booked → Cancelled per E07 state machine)
            if (booking.Unit__c != null) {
                unitsToUpdate.put(booking.Unit__c, new Unit__c(Id = booking.Unit__c, Unit_Status__c = 'Cancelled'));
            }

            results.add(result);
        }

        // ---- PASS 4: one DML per SObject type, in the original per-request order ----
        if (!demandsToUpdate.isEmpty())     update demandsToUpdate;
        if (!agreementsToUpdate.isEmpty())  update agreementsToUpdate;
        if (!possessionsToUpdate.isEmpty()) update possessionsToUpdate;
        if (!bookingsToUpdate.isEmpty())    update bookingsToUpdate.values();
        if (!unitsToUpdate.isEmpty())       update unitsToUpdate.values();

        return results;
    }

    /**
     * @description Validates a single request's own fields. Runs before any SOQL so a
     *              malformed request never consumes query or DML capacity.
     */
    private static void validateRequest(CancellationRequest req) {
        if (req == null || req.bookingId == null) {
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
    }
}
