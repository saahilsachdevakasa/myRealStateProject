/*
 * E17 — Commission demo seed
 *
 * Backfills commission for the existing Happy Path Booking (BKG-PRK-26-0001)
 * which already went through the full lifecycle (Possessed) without a
 * Source_CP populated, so triggers never accrued. We:
 *
 * 1. Backfill Source_CP on BKG-PRK-26-0001 = Acme Realty Advisors (Platinum)
 * 2. Manually insert 3 ledger entries (Booking + Agreement + Registration)
 *    mirroring what the trigger chain would have created. Naming trigger
 *    populates CL-BKG-PRK-26-0001-{nn} automatically.
 * 3. Run CommissionPayoutBatch to roll up the 3 entries into a Payout.
 *
 * Idempotent — checks for existing ledger entries on the target Booking
 * before inserting.
 */

Booking__c bkg = [
    SELECT Id, Name, Source_CP__c, Agreement_Value__c
    FROM Booking__c WHERE Name = 'BKG-PRK-26-0001' LIMIT 1
];
Account acme = [
    SELECT Id, GSTIN__c FROM Account WHERE Name = 'Acme Realty Advisors' LIMIT 1
];
Project__c prk = [SELECT Id FROM Project__c WHERE Project_Code__c = 'PRK' LIMIT 1];

// Backfill Source_CP if missing
if (bkg.Source_CP__c == null) {
    bkg.Source_CP__c = acme.Id;
    update bkg;
    System.debug('Backfilled Source_CP on ' + bkg.Name + ' = Acme Realty Advisors');
}

// Find the active Platinum rate card for PRK
Commission_Rate_Card__c card = RateCardService.getActiveRateCard(prk.Id, 'Platinum');
if (card == null) {
    System.debug(LoggingLevel.ERROR, 'No active Platinum rate card for PRK — aborting');
    return;
}

// Idempotency check
Integer existing = [SELECT COUNT() FROM Commission_Ledger__c WHERE Booking__c = :bkg.Id];
if (existing > 0) {
    System.debug('BKG-PRK-26-0001 already has ' + existing + ' ledger entries — skipping accrual');
} else {
    Decimal basis = bkg.Agreement_Value__c;
    Boolean cpHasGstin = String.isNotBlank(acme.GSTIN__c);

    List<Commission_Ledger__c> entries = new List<Commission_Ledger__c>();
    for (Map<String, Object> spec : new List<Map<String, Object>>{
        new Map<String, Object>{ 'milestone' => 'Booking',      'rate' => card.Booking_Pct__c,      'date' => Date.today().addDays(-180) },
        new Map<String, Object>{ 'milestone' => 'Agreement',    'rate' => card.Agreement_Pct__c,    'date' => Date.today().addDays(-120) },
        new Map<String, Object>{ 'milestone' => 'Registration', 'rate' => card.Registration_Pct__c, 'date' => Date.today().addDays(-60) }
    }) {
        Decimal ratePct = (Decimal) spec.get('rate');
        Decimal gross = (basis * ratePct / 100).setScale(2);
        Decimal gst = cpHasGstin ? 0 : (gross * 0.18).setScale(2);
        Decimal tds = (gross * 0.05).setScale(2);
        entries.add(new Commission_Ledger__c(
            Booking__c = bkg.Id,
            Channel_Partner__c = acme.Id,
            Rate_Card__c = card.Id,
            Milestone__c = (String) spec.get('milestone'),
            Milestone_Date__c = (Date) spec.get('date'),
            Agreement_Value_Basis__c = basis,
            Rate_Pct__c = ratePct,
            GST_On_Commission__c = gst,
            TDS_On_Commission__c = tds,
            Status__c = 'Accrued'
        ));
    }
    insert entries;
    System.debug('Inserted ' + entries.size() + ' commission ledger entries for ' + bkg.Name);
    for (Commission_Ledger__c e : [
        SELECT Name, Milestone__c, Gross_Commission__c, Net_Payable__c
        FROM Commission_Ledger__c WHERE Booking__c = :bkg.Id ORDER BY CreatedDate
    ]) {
        System.debug('  ' + e.Name + ' [' + e.Milestone__c + ']  Gross=' + e.Gross_Commission__c + '  Net=' + e.Net_Payable__c);
    }
}

// Run the payout batch — rolls up all unpaid Accrued entries into Payouts per CP
Integer existingPayouts = [SELECT COUNT() FROM Commission_Payout__c WHERE Channel_Partner__c = :acme.Id];
if (existingPayouts > 0) {
    System.debug('Acme already has ' + existingPayouts + ' payouts — skipping batch run');
} else {
    Id batchId = Database.executeBatch(new CommissionPayoutBatch(), 200);
    System.debug('Started CommissionPayoutBatch jobId=' + batchId);
}

System.debug('=== COMMISSION SEED COMPLETE ===');
