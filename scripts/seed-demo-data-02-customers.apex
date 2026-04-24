/**
 * Demo Data Seed — Part 2: Customers, Contacts, CP Rate Cards
 *
 * Creates:
 *   - 3 Buyer Accounts (Rajesh, Priya, Vikram Enterprises-corporate)
 *   - 1 Channel Partner Account (Acme Realty)
 *   - 3 Contacts linked to buyer accounts
 *   - 2 Commission Rate Cards (PRK + GAL, Platinum tier)
 *
 * Idempotent: identifies existing records by PAN / Name + RecordType
 * and deletes before recreating. Leaves Plans, Projects, Units intact.
 *
 * Run order: 01 → 02 → 03.
 * Run: sf apex run --file scripts/seed-demo-data-02-customers.apex --target-org re-crm-sdo
 */

System.debug('=== STARTING CUSTOMER SEED ===');

// ========================================================================
// CLEANUP — wipe our seed accounts by PAN, seed rate cards by Project + Tier.
// Opps/Leads referencing these accounts are handled by the scenarios script.
// ========================================================================

Set<String> seedPANs = new Set<String>{
    'ABCPK1234A', 'ABCPS5678B', 'AABCV9876D', 'AABCA1234E'
};

List<Account> existingAccounts = [
    SELECT Id FROM Account WHERE PAN__c IN :seedPANs
];
if (!existingAccounts.isEmpty()) {
    // Wipe dependent Opps/Leads first (if scenarios ran before this)
    Set<Id> accIds = new Map<Id, Account>(existingAccounts).keySet();
    List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE AccountId IN :accIds];
    if (!opps.isEmpty()) {
        System.debug('Deleting ' + opps.size() + ' opps linked to seed accounts');
        delete opps;
    }
    System.debug('Deleting ' + existingAccounts.size() + ' existing seed accounts');
    delete existingAccounts;
}

List<Project__c> seedProjects = [SELECT Id FROM Project__c WHERE Project_Code__c IN ('PRK', 'GAL')];
if (!seedProjects.isEmpty()) {
    Set<Id> seedProjIds = new Map<Id, Project__c>(seedProjects).keySet();
    List<Commission_Rate_Card__c> existingCards = [
        SELECT Id FROM Commission_Rate_Card__c
        WHERE Project__c IN :seedProjIds AND CP_Tier__c = 'Platinum'
    ];
    if (!existingCards.isEmpty()) {
        System.debug('Deleting ' + existingCards.size() + ' existing rate cards');
        delete existingCards;
    }
}

// ========================================================================
// RECORD TYPE LOOKUPS
// ========================================================================

Id buyerRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Buyer').getRecordTypeId();
Id corpBuyerRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Corporate_Buyer').getRecordTypeId();
Id cpRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Channel_Partner').getRecordTypeId();

// ========================================================================
// BUYER ACCOUNT 1 — Rajesh Kumar (Self-Use)
// ========================================================================

Account rajesh = new Account(
    Name = 'Rajesh Kumar',
    RecordTypeId = buyerRt,
    Phone = '+91 98200 10001',
    PAN__c = 'ABCPK1234A',
    DOB__c = Date.newInstance(1985, 3, 15),
    Buyer_Type__c = 'Self-Use',
    KYC_Status__c = 'Verified',
    KYC_Verified_Date__c = Date.today().addDays(-30),
    BillingStreet = '12 Carmichael Road',
    BillingCity = 'Mumbai',
    BillingState = 'Maharashtra',
    BillingPostalCode = '400026',
    BillingCountry = 'India'
);
insert rajesh;
System.debug('Created Buyer: Rajesh Kumar');

// ========================================================================
// BUYER ACCOUNT 2 — Priya Sharma (Investor)
// ========================================================================

Account priya = new Account(
    Name = 'Priya Sharma',
    RecordTypeId = buyerRt,
    Phone = '+91 98200 10002',
    PAN__c = 'ABCPS5678B',
    DOB__c = Date.newInstance(1990, 7, 22),
    Buyer_Type__c = 'Investor',
    KYC_Status__c = 'Pending',
    BillingStreet = '45 Koregaon Park',
    BillingCity = 'Pune',
    BillingState = 'Maharashtra',
    BillingPostalCode = '411001',
    BillingCountry = 'India'
);
insert priya;
System.debug('Created Buyer: Priya Sharma');

// ========================================================================
// BUYER ACCOUNT 3 — Vikram Enterprises (Corporate)
// ========================================================================

Account vikram = new Account(
    Name = 'Vikram Enterprises Pvt Ltd',
    RecordTypeId = corpBuyerRt,
    Phone = '+91 22 4000 1234',
    PAN__c = 'AABCV9876D',
    GSTIN__c = '27AABCV9876D1ZP',
    KYC_Status__c = 'Verified',
    KYC_Verified_Date__c = Date.today().addDays(-60),
    BillingStreet = 'Office 503, Tower C, Lower Parel',
    BillingCity = 'Mumbai',
    BillingState = 'Maharashtra',
    BillingPostalCode = '400013',
    BillingCountry = 'India'
);
insert vikram;
System.debug('Created Corporate Buyer: Vikram Enterprises');

// ========================================================================
// CHANNEL PARTNER — Acme Realty Advisors
// ========================================================================

Account acme = new Account(
    Name = 'Acme Realty Advisors',
    RecordTypeId = cpRt,
    Phone = '+91 98200 20001',
    PAN__c = 'AABCA1234E',
    RERA_Number__c = 'A51800099001',
    RERA_State__c = 'Maharashtra',
    CP_Tier__c = 'Platinum',
    CP_Status__c = 'Active',
    Empanelment_Date__c = Date.newInstance(2025, 1, 15),
    Portal_Access__c = true,
    BillingStreet = '8th Floor, Realty Tower, Bandra Kurla Complex',
    BillingCity = 'Mumbai',
    BillingState = 'Maharashtra',
    BillingPostalCode = '400051',
    BillingCountry = 'India'
);
insert acme;
System.debug('Created Channel Partner: Acme Realty Advisors');

// ========================================================================
// CONTACTS — one per buyer account. Account RT drives contact visibility
// via CBP sharing. These surface in the standard Contact tab.
// ========================================================================

List<Contact> contacts = new List<Contact>{
    new Contact(
        FirstName = 'Rajesh',
        LastName = 'Kumar',
        AccountId = rajesh.Id,
        Phone = '+91 98200 10001',
        Email = 'rajesh.kumar+demo@example.in',
        PAN__c = 'ABCPK1234A',
        DOB__c = Date.newInstance(1985, 3, 15),
        Occupation__c = 'Senior Software Engineer'
    ),
    new Contact(
        FirstName = 'Priya',
        LastName = 'Sharma',
        AccountId = priya.Id,
        Phone = '+91 98200 10002',
        Email = 'priya.sharma+demo@example.in',
        PAN__c = 'ABCPS5678B',
        DOB__c = Date.newInstance(1990, 7, 22),
        Occupation__c = 'Investment Banker'
    ),
    new Contact(
        FirstName = 'Amit',
        LastName = 'Patel',
        AccountId = vikram.Id,
        Phone = '+91 98200 10003',
        Email = 'amit.patel+demo@example.in',
        PAN__c = 'AABCP7890F',
        Occupation__c = 'Director - Real Estate'
    )
};
insert contacts;
System.debug('Created ' + contacts.size() + ' contacts');

// ========================================================================
// COMMISSION RATE CARDS — PRK and GAL × Platinum tier
// ========================================================================

Project__c prk = [SELECT Id FROM Project__c WHERE Project_Code__c = 'PRK' LIMIT 1];
Project__c gal = [SELECT Id FROM Project__c WHERE Project_Code__c = 'GAL' LIMIT 1];

List<Commission_Rate_Card__c> cards = new List<Commission_Rate_Card__c>{
    new Commission_Rate_Card__c(
        Project__c = prk.Id,
        CP_Tier__c = 'Platinum',
        Booking_Pct__c = 2.0,
        Agreement_Pct__c = 1.0,
        Registration_Pct__c = 0.5,
        Effective_From__c = Date.newInstance(2025, 1, 1),
        Notes__c = 'Platinum rate card for Park Residences — 3.5% total'
    ),
    new Commission_Rate_Card__c(
        Project__c = gal.Id,
        CP_Tier__c = 'Platinum',
        Booking_Pct__c = 1.5,
        Agreement_Pct__c = 1.0,
        Registration_Pct__c = 0.5,
        Effective_From__c = Date.newInstance(2025, 1, 1),
        Notes__c = 'Platinum rate card for Galleria Central — 3.0% total'
    )
};
insert cards;
System.debug('Created ' + cards.size() + ' rate cards');

System.debug('=== CUSTOMER SEED COMPLETE ===');
System.debug('Summary: 4 accounts (3 buyers + 1 CP), 3 contacts, 2 rate cards');
