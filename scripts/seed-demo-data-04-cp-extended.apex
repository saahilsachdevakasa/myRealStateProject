/*
 * E14 — Extended CP demo seed
 * Adds 3 Channel Partner Accounts (Preferred, Standard, Pending Approval)
 * and 4 Commission Rate Cards (PRK x Preferred, PRK x Standard,
 * GAL x Preferred, GAL x Standard) so the demo shows tier diversity
 * for the commission engine (E17).
 *
 * Idempotent — checks for existing records by Name / (Project + Tier)
 * before inserting.
 */

Id cpRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Channel_Partner').getRecordTypeId();

// ========================================================================
// CHANNEL PARTNERS — 3 additional CPs
// ========================================================================

Map<String, Account> existingByName = new Map<String, Account>();
for (Account a : [
    SELECT Id, Name FROM Account
    WHERE RecordTypeId = :cpRt
      AND Name IN ('Prime Properties', 'Metro Realtors', 'New Prospect Realty')
]) {
    existingByName.put(a.Name, a);
}

List<Account> cpsToInsert = new List<Account>();

if (!existingByName.containsKey('Prime Properties')) {
    cpsToInsert.add(new Account(
        Name = 'Prime Properties',
        RecordTypeId = cpRt,
        Phone = '+91 98200 30001',
        PAN__c = 'AABCP3001E',
        RERA_Number__c = 'A51800099002',
        RERA_State__c = 'Maharashtra',
        CP_Tier__c = 'Preferred',
        CP_Status__c = 'Active',
        Empanelment_Date__c = Date.newInstance(2025, 4, 10),
        Approval_Date__c = Date.newInstance(2025, 4, 10),
        Portal_Access__c = true,
        BillingStreet = '5th Floor, Premier Plaza, Andheri East',
        BillingCity = 'Mumbai',
        BillingState = 'Maharashtra',
        BillingPostalCode = '400069',
        BillingCountry = 'India'
    ));
}

if (!existingByName.containsKey('Metro Realtors')) {
    cpsToInsert.add(new Account(
        Name = 'Metro Realtors',
        RecordTypeId = cpRt,
        Phone = '+91 98200 30002',
        PAN__c = 'AABCM3002F',
        RERA_Number__c = 'A51800099003',
        RERA_State__c = 'Maharashtra',
        CP_Tier__c = 'Standard',
        CP_Status__c = 'Active',
        Empanelment_Date__c = Date.newInstance(2025, 6, 20),
        Approval_Date__c = Date.newInstance(2025, 6, 20),
        Portal_Access__c = true,
        BillingStreet = '203, Metro House, Worli',
        BillingCity = 'Mumbai',
        BillingState = 'Maharashtra',
        BillingPostalCode = '400018',
        BillingCountry = 'India'
    ));
}

if (!existingByName.containsKey('New Prospect Realty')) {
    cpsToInsert.add(new Account(
        Name = 'New Prospect Realty',
        RecordTypeId = cpRt,
        Phone = '+91 98200 30003',
        PAN__c = 'AABCN3003G',
        RERA_Number__c = 'A51800099004',
        RERA_State__c = 'Maharashtra',
        CP_Tier__c = 'Standard',
        CP_Status__c = 'Pending Approval',
        Portal_Access__c = false,
        BillingStreet = 'Office 12, Prospect Tower, Goregaon',
        BillingCity = 'Mumbai',
        BillingState = 'Maharashtra',
        BillingPostalCode = '400062',
        BillingCountry = 'India'
    ));
}

if (!cpsToInsert.isEmpty()) {
    insert cpsToInsert;
    System.debug('Inserted ' + cpsToInsert.size() + ' Channel Partner accounts');
} else {
    System.debug('All 3 extended CPs already exist — skipped insert');
}

// ========================================================================
// COMMISSION RATE CARDS — 4 additional cards
// ========================================================================

Project__c prk = [SELECT Id FROM Project__c WHERE Project_Code__c = 'PRK' LIMIT 1];
Project__c gal = [SELECT Id FROM Project__c WHERE Project_Code__c = 'GAL' LIMIT 1];

Set<String> existingKeys = new Set<String>();
for (Commission_Rate_Card__c card : [
    SELECT Id, Project__c, CP_Tier__c FROM Commission_Rate_Card__c
    WHERE Project__c IN (:prk.Id, :gal.Id)
      AND CP_Tier__c IN ('Preferred', 'Standard')
]) {
    existingKeys.add(card.Project__c + '-' + card.CP_Tier__c);
}

List<Commission_Rate_Card__c> cardsToInsert = new List<Commission_Rate_Card__c>();

// PRK × Preferred
if (!existingKeys.contains(prk.Id + '-Preferred')) {
    cardsToInsert.add(new Commission_Rate_Card__c(
        Project__c = prk.Id,
        CP_Tier__c = 'Preferred',
        Booking_Pct__c = 1.5,
        Agreement_Pct__c = 0.75,
        Registration_Pct__c = 0.25,
        Effective_From__c = Date.newInstance(2025, 1, 1),
        Notes__c = 'Preferred rate card for Park Residences — 2.5% total'
    ));
}

// PRK × Standard
if (!existingKeys.contains(prk.Id + '-Standard')) {
    cardsToInsert.add(new Commission_Rate_Card__c(
        Project__c = prk.Id,
        CP_Tier__c = 'Standard',
        Booking_Pct__c = 1.0,
        Agreement_Pct__c = 0.5,
        Registration_Pct__c = 0.25,
        Effective_From__c = Date.newInstance(2025, 1, 1),
        Notes__c = 'Standard rate card for Park Residences — 1.75% total'
    ));
}

// GAL × Preferred
if (!existingKeys.contains(gal.Id + '-Preferred')) {
    cardsToInsert.add(new Commission_Rate_Card__c(
        Project__c = gal.Id,
        CP_Tier__c = 'Preferred',
        Booking_Pct__c = 1.5,
        Agreement_Pct__c = 0.75,
        Registration_Pct__c = 0.25,
        Effective_From__c = Date.newInstance(2025, 1, 1),
        Notes__c = 'Preferred rate card for Galleria Central — 2.5% total'
    ));
}

// GAL × Standard
if (!existingKeys.contains(gal.Id + '-Standard')) {
    cardsToInsert.add(new Commission_Rate_Card__c(
        Project__c = gal.Id,
        CP_Tier__c = 'Standard',
        Booking_Pct__c = 1.0,
        Agreement_Pct__c = 0.5,
        Registration_Pct__c = 0.25,
        Effective_From__c = Date.newInstance(2025, 1, 1),
        Notes__c = 'Standard rate card for Galleria Central — 1.75% total'
    ));
}

if (!cardsToInsert.isEmpty()) {
    insert cardsToInsert;
    System.debug('Inserted ' + cardsToInsert.size() + ' rate cards');
} else {
    System.debug('All 4 extended rate cards already exist — skipped insert');
}

System.debug('=== EXTENDED CP SEED COMPLETE ===');
Integer cpCount = [SELECT COUNT() FROM Account WHERE RecordTypeId = :cpRt];
Integer cardCount = [SELECT COUNT() FROM Commission_Rate_Card__c];
System.debug('Org now has ' + cpCount + ' Channel Partner accounts and ' + cardCount + ' rate cards');
