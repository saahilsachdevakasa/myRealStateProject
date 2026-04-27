public with sharing class CommissionService {

    // ================================================================
    // ENTRY POINTS — invoked from triggers (Trigger.new + oldMap)
    // ================================================================

    public static void accrueOnBooking(List<Booking__c> bookings) {
        Set<Id> bookingIds = new Set<Id>();
        for (Booking__c b : bookings) {
            if (b.Source_CP__c != null) bookingIds.add(b.Id);
        }
        if (bookingIds.isEmpty()) return;

        List<Booking__c> hydrated = [
            SELECT Id, Source_CP__c, Agreement_Value__c, Unit__r.Tower__r.Project__c
            FROM Booking__c
            WHERE Id IN :bookingIds
            WITH SECURITY_ENFORCED
        ];
        accrueMilestone(hydrated, 'Booking');
    }

    public static void accrueOnAgreementSigned(List<Agreement__c> agreements, Map<Id, Agreement__c> oldMap) {
        Set<Id> bookingIds = new Set<Id>();
        for (Agreement__c a : agreements) {
            Agreement__c old = oldMap.get(a.Id);
            if (old.Status__c != 'Signed' && a.Status__c == 'Signed' && a.Booking__c != null) {
                bookingIds.add(a.Booking__c);
            }
        }
        if (bookingIds.isEmpty()) return;

        List<Booking__c> hydrated = [
            SELECT Id, Source_CP__c, Agreement_Value__c, Unit__r.Tower__r.Project__c
            FROM Booking__c
            WHERE Id IN :bookingIds AND Source_CP__c != null
            WITH SECURITY_ENFORCED
        ];
        if (hydrated.isEmpty()) return;
        accrueMilestone(hydrated, 'Agreement');
    }

    public static void accrueOnRegistration(List<Agreement__c> agreements, Map<Id, Agreement__c> oldMap) {
        Set<Id> bookingIds = new Set<Id>();
        for (Agreement__c a : agreements) {
            Agreement__c old = oldMap.get(a.Id);
            Boolean justRegistered = a.Registration_Date__c != null
                && old.Registration_Date__c == null
                && a.Status__c == 'Executed';
            if (justRegistered && a.Booking__c != null) {
                bookingIds.add(a.Booking__c);
            }
        }
        if (bookingIds.isEmpty()) return;

        List<Booking__c> hydrated = [
            SELECT Id, Source_CP__c, Agreement_Value__c, Unit__r.Tower__r.Project__c
            FROM Booking__c
            WHERE Id IN :bookingIds AND Source_CP__c != null
            WITH SECURITY_ENFORCED
        ];
        if (hydrated.isEmpty()) return;
        accrueMilestone(hydrated, 'Registration');
    }

    public static void clawbackOnCancellation(List<Booking__c> bookings, Map<Id, Booking__c> oldMap) {
        Set<Id> bookingIds = new Set<Id>();
        for (Booking__c b : bookings) {
            Booking__c old = oldMap.get(b.Id);
            if (old.Booking_Status__c != 'Cancelled' && b.Booking_Status__c == 'Cancelled') {
                bookingIds.add(b.Id);
            }
        }
        if (bookingIds.isEmpty()) return;

        List<Commission_Ledger__c> existing = [
            SELECT Id, Name, Booking__c, Channel_Partner__c, Rate_Card__c, Milestone__c,
                   Status__c, Agreement_Value_Basis__c, Rate_Pct__c,
                   Gross_Commission__c, GST_On_Commission__c, TDS_On_Commission__c
            FROM Commission_Ledger__c
            WHERE Booking__c IN :bookingIds
              AND Status__c IN ('Accrued', 'Approved', 'Paid')
            WITH SECURITY_ENFORCED
        ];
        if (existing.isEmpty()) return;

        List<Commission_Ledger__c> toUpdate = new List<Commission_Ledger__c>();
        List<Commission_Ledger__c> toInsert = new List<Commission_Ledger__c>();

        for (Commission_Ledger__c c : existing) {
            if (c.Status__c == 'Paid') {
                toInsert.add(buildClawbackOffset(c));
            } else {
                toUpdate.add(new Commission_Ledger__c(Id = c.Id, Status__c = 'Clawed Back'));
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!toInsert.isEmpty()) insert toInsert;
    }

    // ================================================================
    // INTERNAL — shared accrual logic
    // ================================================================

    private static void accrueMilestone(List<Booking__c> bookings, String milestone) {
        Set<Id> cpIds = new Set<Id>();
        Set<Id> projectIds = new Set<Id>();
        for (Booking__c b : bookings) {
            cpIds.add(b.Source_CP__c);
            Id pid = projectIdFor(b);
            if (pid != null) projectIds.add(pid);
        }
        if (cpIds.isEmpty() || projectIds.isEmpty()) return;

        Map<Id, Account> cpById = new Map<Id, Account>([
            SELECT Id, CP_Tier__c, GSTIN__c
            FROM Account WHERE Id IN :cpIds
            WITH SECURITY_ENFORCED
        ]);

        Set<String> tiers = new Set<String>();
        for (Account a : cpById.values()) {
            if (String.isNotBlank(a.CP_Tier__c)) tiers.add(a.CP_Tier__c);
        }
        if (tiers.isEmpty()) return;

        Map<String, Commission_Rate_Card__c> rateCardsByKey =
            RateCardService.getActiveRateCards(projectIds, tiers);

        List<Commission_Ledger__c> toInsert = new List<Commission_Ledger__c>();
        for (Booking__c b : bookings) {
            Account cp = cpById.get(b.Source_CP__c);
            if (cp == null || String.isBlank(cp.CP_Tier__c)) continue;
            Id projectId = projectIdFor(b);
            if (projectId == null) continue;

            String key = RateCardService.buildKey(projectId, cp.CP_Tier__c);
            Commission_Rate_Card__c card = rateCardsByKey.get(key);
            if (card == null) {
                System.debug(LoggingLevel.WARN, 'CommissionService: no active rate card for Booking '
                    + b.Id + ' (Project=' + projectId + ', Tier=' + cp.CP_Tier__c
                    + ') — skipping ' + milestone + ' accrual');
                continue;
            }

            Decimal ratePct = pctForMilestone(card, milestone);
            if (ratePct == null || ratePct == 0) continue;

            Decimal basis = (b.Agreement_Value__c == null) ? 0 : b.Agreement_Value__c;
            Decimal gross = (basis * ratePct / 100).setScale(2);
            Decimal gst = String.isBlank(cp.GSTIN__c) ? (gross * 0.18).setScale(2) : 0;
            Decimal tds = (gross * 0.05).setScale(2);

            toInsert.add(new Commission_Ledger__c(
                Booking__c = b.Id,
                Channel_Partner__c = cp.Id,
                Rate_Card__c = card.Id,
                Milestone__c = milestone,
                Milestone_Date__c = Date.today(),
                Agreement_Value_Basis__c = basis,
                Rate_Pct__c = ratePct,
                GST_On_Commission__c = gst,
                TDS_On_Commission__c = tds,
                Status__c = 'Accrued'
            ));
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }

    private static Commission_Ledger__c buildClawbackOffset(Commission_Ledger__c original) {
        Decimal basis = (original.Agreement_Value_Basis__c == null) ? 0 : -original.Agreement_Value_Basis__c;
        Decimal gst = (original.GST_On_Commission__c == null) ? 0 : -original.GST_On_Commission__c;
        Decimal tds = (original.TDS_On_Commission__c == null) ? 0 : -original.TDS_On_Commission__c;
        return new Commission_Ledger__c(
            Booking__c = original.Booking__c,
            Channel_Partner__c = original.Channel_Partner__c,
            Rate_Card__c = original.Rate_Card__c,
            Milestone__c = 'Clawback',
            Milestone_Date__c = Date.today(),
            Agreement_Value_Basis__c = basis,
            Rate_Pct__c = original.Rate_Pct__c,
            GST_On_Commission__c = gst,
            TDS_On_Commission__c = tds,
            Status__c = 'Accrued',
            Hold_Reason__c = 'Clawback of ' + original.Name
        );
    }

    private static Id projectIdFor(Booking__c b) {
        return (b.Unit__r != null && b.Unit__r.Tower__r != null) ? b.Unit__r.Tower__r.Project__c : null;
    }

    private static Decimal pctForMilestone(Commission_Rate_Card__c card, String milestone) {
        if (milestone == 'Booking') return card.Booking_Pct__c;
        if (milestone == 'Agreement') return card.Agreement_Pct__c;
        if (milestone == 'Registration') return card.Registration_Pct__c;
        return null;
    }
}
