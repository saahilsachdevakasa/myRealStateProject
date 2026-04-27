@IsTest(SeeAllData=false)
private class CommissionServiceTest {

    private class Seed {
        Project__c project;
        Tower__c tower;
        Unit__c unit;
        Account cp;
        Account buyer;
        Commission_Rate_Card__c rateCard;
        Opportunity opp;
        Booking__c booking;
    }

    // Builds full Booking lifecycle scaffold including the Booking itself
    // (created via Opp Closed Won so BookingTrigger AFTER_INSERT fires).
    private static Seed seedBookingWithCP(String projectCode, String tier, String gstin) {
        Seed s = new Seed();
        s.project = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => projectCode,
            'Name' => 'Project ' + projectCode
        });
        s.tower = TestDataFactory.createTower(s.project.Id, null);
        s.unit = TestDataFactory.createUnit(s.tower.Id, new Map<String, Object>{
            'Unit_Status__c' => 'Blocked'
        });
        Map<String, Object> cpOverrides = new Map<String, Object>{
            'Name' => 'CP ' + projectCode,
            'CP_Tier__c' => tier,
            'CP_Status__c' => 'Active'
        };
        if (gstin != null) cpOverrides.put('GSTIN__c', gstin);
        s.cp = TestDataFactory.createCPAccount(cpOverrides);

        s.rateCard = TestDataFactory.createRateCard(s.project.Id, new Map<String, Object>{
            'CP_Tier__c' => tier,
            'Booking_Pct__c' => 2,
            'Agreement_Pct__c' => 1,
            'Registration_Pct__c' => 0.5,
            'Effective_From__c' => Date.today().addMonths(-3)
        });

        s.buyer = TestDataFactory.createAccount(new Map<String, Object>{
            'Name' => 'Buyer ' + projectCode
        });
        s.opp = TestDataFactory.createOpportunity(s.buyer.Id, new Map<String, Object>{
            'StageName' => 'Token Paid',
            'Project__c' => s.project.Id,
            'Primary_Unit__c' => s.unit.Id,
            'EOI_Amount__c' => 100000,
            'Token_Amount__c' => 200000,
            'Quoted_Gross_Value__c' => 5000000,
            'Source_Channel__c' => 'CP',
            'Source_CP__c' => s.cp.Id
        });

        s.opp.StageName = 'Closed Won (Booked)';
        update s.opp;

        Opportunity refreshed = [SELECT Id, Booking__c FROM Opportunity WHERE Id = :s.opp.Id];
        s.booking = [
            SELECT Id, Name, Source_CP__c, Agreement_Value__c, Booking_Status__c
            FROM Booking__c WHERE Id = :refreshed.Booking__c
        ];
        // Clear all guards so subsequent DMLs in the same test transaction
        // re-fire trigger handlers (clawback, sequential Agreement updates,
        // bulk multi-seed cases, etc.).
        RecursionGuard.resetAll();
        return s;
    }

    @IsTest
    static void testAccrueOnBooking_HappyPath() {
        Test.startTest();
        Seed s = seedBookingWithCP('AAA', 'Platinum', '27ABCDE1234F1Z5');
        Test.stopTest();

        List<Commission_Ledger__c> ledgers = [
            SELECT Id, Name, Milestone__c, Status__c, Channel_Partner__c, Rate_Card__c,
                   Agreement_Value_Basis__c, Rate_Pct__c, Gross_Commission__c,
                   GST_On_Commission__c, TDS_On_Commission__c, Net_Payable__c
            FROM Commission_Ledger__c WHERE Booking__c = :s.booking.Id
        ];
        System.assertEquals(1, ledgers.size(), 'Expected 1 Booking-milestone ledger entry');
        Commission_Ledger__c c = ledgers[0];
        System.assertEquals('Booking', c.Milestone__c);
        System.assertEquals('Accrued', c.Status__c);
        System.assertEquals(s.cp.Id, c.Channel_Partner__c);
        System.assertEquals(s.rateCard.Id, c.Rate_Card__c);
        System.assertEquals(s.booking.Agreement_Value__c, c.Agreement_Value_Basis__c);
        System.assertEquals(2, c.Rate_Pct__c);
        // Gross = basis * 2% (Salesforce Currency*Percent decimal coercion)
        Decimal expectedGross = (s.booking.Agreement_Value__c * 0.02).setScale(2);
        System.assertEquals(expectedGross, c.Gross_Commission__c);
        // CP has GSTIN → no reverse-charge GST
        System.assertEquals(0, c.GST_On_Commission__c);
        // TDS = gross * 5%
        System.assertEquals((expectedGross * 0.05).setScale(2), c.TDS_On_Commission__c);
        System.assert(c.Name.startsWith('CL-BKG-'), 'Name should follow CL-BKG-... pattern: ' + c.Name);
        System.assert(c.Name.endsWith('-01'), 'First entry should be -01: ' + c.Name);
    }

    @IsTest
    static void testAccrueOnBooking_NoCP() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => 'NCP'
        });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        Unit__c unit = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Status__c' => 'Blocked'
        });
        Account buyer = TestDataFactory.createAccount(null);
        Opportunity opp = TestDataFactory.createOpportunity(buyer.Id, new Map<String, Object>{
            'StageName' => 'Token Paid',
            'Project__c' => proj.Id,
            'Primary_Unit__c' => unit.Id,
            'EOI_Amount__c' => 100000,
            'Token_Amount__c' => 200000,
            'Quoted_Gross_Value__c' => 5000000,
            'Source_Channel__c' => 'Walk-in'
        });

        Test.startTest();
        opp.StageName = 'Closed Won (Booked)';
        update opp;
        Test.stopTest();

        Opportunity refreshed = [SELECT Booking__c FROM Opportunity WHERE Id = :opp.Id];
        Integer count = [SELECT COUNT() FROM Commission_Ledger__c WHERE Booking__c = :refreshed.Booking__c];
        System.assertEquals(0, count, 'No CP → no commission ledger entries');
    }

    @IsTest
    static void testAccrueOnBooking_CPWithoutGSTIN() {
        Test.startTest();
        Seed s = seedBookingWithCP('NGS', 'Standard', null);
        Test.stopTest();

        Commission_Ledger__c c = [
            SELECT GST_On_Commission__c, Gross_Commission__c
            FROM Commission_Ledger__c WHERE Booking__c = :s.booking.Id LIMIT 1
        ];
        // CP has no GSTIN → 18% reverse-charge GST
        Decimal expectedGst = (c.Gross_Commission__c * 0.18).setScale(2);
        System.assertEquals(expectedGst, c.GST_On_Commission__c);
    }

    @IsTest
    static void testAccrueOnBooking_RateCardNotFound() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => 'NRC'
        });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        Unit__c unit = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Status__c' => 'Blocked'
        });
        // CP exists but NO rate card for this Project x Tier
        Account cp = TestDataFactory.createCPAccount(new Map<String, Object>{
            'Name' => 'Orphan CP', 'CP_Tier__c' => 'Platinum'
        });
        Account buyer = TestDataFactory.createAccount(null);
        Opportunity opp = TestDataFactory.createOpportunity(buyer.Id, new Map<String, Object>{
            'StageName' => 'Token Paid',
            'Project__c' => proj.Id,
            'Primary_Unit__c' => unit.Id,
            'EOI_Amount__c' => 100000, 'Token_Amount__c' => 200000,
            'Quoted_Gross_Value__c' => 5000000,
            'Source_Channel__c' => 'CP', 'Source_CP__c' => cp.Id
        });

        Test.startTest();
        opp.StageName = 'Closed Won (Booked)';
        update opp;
        Test.stopTest();

        Opportunity refreshed = [SELECT Booking__c FROM Opportunity WHERE Id = :opp.Id];
        Integer count = [SELECT COUNT() FROM Commission_Ledger__c WHERE Booking__c = :refreshed.Booking__c];
        System.assertEquals(0, count, 'No rate card → service skips silently, no DML');

        Booking__c booking = [SELECT Booking_Status__c FROM Booking__c WHERE Id = :refreshed.Booking__c];
        System.assertEquals('Confirmed', booking.Booking_Status__c, 'Booking is not blocked');
    }

    @IsTest
    static void testAccrueOnAgreementSigned() {
        Seed s = seedBookingWithCP('AGS', 'Platinum', '27ABCDE1234F1Z5');

        Test.startTest();
        Agreement__c ag = TestDataFactory.createAgreement(s.booking.Id, new Map<String, Object>{
            'Status__c' => 'Draft Generated'
        });
        ag.Status__c = 'Signed';
        update ag;
        Test.stopTest();

        List<Commission_Ledger__c> ledgers = [
            SELECT Milestone__c, Rate_Pct__c FROM Commission_Ledger__c
            WHERE Booking__c = :s.booking.Id ORDER BY CreatedDate
        ];
        System.assertEquals(2, ledgers.size(), '1 Booking + 1 Agreement entry');
        System.assertEquals('Booking', ledgers[0].Milestone__c);
        System.assertEquals('Agreement', ledgers[1].Milestone__c);
        System.assertEquals(1, ledgers[1].Rate_Pct__c);
    }

    @IsTest
    static void testAccrueOnRegistration() {
        Seed s = seedBookingWithCP('REG', 'Platinum', '27ABCDE1234F1Z5');

        Test.startTest();
        Agreement__c ag = TestDataFactory.createAgreement(s.booking.Id, new Map<String, Object>{
            'Status__c' => 'Draft Generated'
        });
        ag.Status__c = 'Signed';
        update ag;
        // Now register
        RecursionGuard.resetAll();
        ag.Status__c = 'Executed';
        ag.Registration_Date__c = Date.today();
        update ag;
        Test.stopTest();

        List<Commission_Ledger__c> ledgers = [
            SELECT Milestone__c, Rate_Pct__c FROM Commission_Ledger__c
            WHERE Booking__c = :s.booking.Id ORDER BY CreatedDate
        ];
        System.assertEquals(3, ledgers.size(), 'Booking + Agreement + Registration entries');
        System.assertEquals('Registration', ledgers[2].Milestone__c);
        System.assertEquals(0.5, ledgers[2].Rate_Pct__c);
    }

    @IsTest
    static void testFullLifecycle_RatesAndNaming() {
        Seed s = seedBookingWithCP('FUL', 'Platinum', '27ABCDE1234F1Z5');

        Test.startTest();
        Agreement__c ag = TestDataFactory.createAgreement(s.booking.Id, new Map<String, Object>{
            'Status__c' => 'Draft Generated'
        });
        ag.Status__c = 'Signed';
        update ag;
        RecursionGuard.resetAll();
        ag.Status__c = 'Executed';
        ag.Registration_Date__c = Date.today();
        update ag;
        Test.stopTest();

        List<Commission_Ledger__c> ledgers = [
            SELECT Name, Milestone__c, Rate_Pct__c, Agreement_Value_Basis__c, Gross_Commission__c
            FROM Commission_Ledger__c WHERE Booking__c = :s.booking.Id
            ORDER BY CreatedDate
        ];
        System.assertEquals(3, ledgers.size());

        // Sequential naming
        System.assert(ledgers[0].Name.endsWith('-01'), 'First entry: -01');
        System.assert(ledgers[1].Name.endsWith('-02'), 'Second entry: -02');
        System.assert(ledgers[2].Name.endsWith('-03'), 'Third entry: -03');

        // Same basis snapshotted across all 3 milestones
        for (Commission_Ledger__c c : ledgers) {
            System.assertEquals(s.booking.Agreement_Value__c, c.Agreement_Value_Basis__c);
        }

        // Rates per milestone
        Map<String, Decimal> rateByMilestone = new Map<String, Decimal>();
        for (Commission_Ledger__c c : ledgers) rateByMilestone.put(c.Milestone__c, c.Rate_Pct__c);
        System.assertEquals(2, rateByMilestone.get('Booking'));
        System.assertEquals(1, rateByMilestone.get('Agreement'));
        System.assertEquals(0.5, rateByMilestone.get('Registration'));
    }

    @IsTest
    static void testClawback_AccruedEntries() {
        Seed s = seedBookingWithCP('CLA', 'Platinum', '27ABCDE1234F1Z5');
        // Verify the Booking entry was accrued
        List<Commission_Ledger__c> before = [
            SELECT Status__c FROM Commission_Ledger__c WHERE Booking__c = :s.booking.Id
        ];
        System.assertEquals(1, before.size());
        System.assertEquals('Accrued', before[0].Status__c);

        Test.startTest();
        s.booking.Booking_Status__c = 'Cancelled';
        update s.booking;
        Test.stopTest();

        List<Commission_Ledger__c> afterEntries = [
            SELECT Status__c, Milestone__c FROM Commission_Ledger__c
            WHERE Booking__c = :s.booking.Id
        ];
        System.assertEquals(1, afterEntries.size(), 'Status update only — no new entry for Accrued clawback');
        System.assertEquals('Clawed Back', afterEntries[0].Status__c);
        System.assertEquals('Booking', afterEntries[0].Milestone__c, 'Original milestone preserved');
    }

    @IsTest
    static void testClawback_PaidEntries() {
        Seed s = seedBookingWithCP('CLP', 'Platinum', '27ABCDE1234F1Z5');
        // Mark the existing Accrued entry as Paid
        Commission_Ledger__c existing = [
            SELECT Id, Name, Agreement_Value_Basis__c, GST_On_Commission__c, TDS_On_Commission__c
            FROM Commission_Ledger__c WHERE Booking__c = :s.booking.Id LIMIT 1
        ];
        existing.Status__c = 'Paid';
        update existing;

        Test.startTest();
        s.booking.Booking_Status__c = 'Cancelled';
        update s.booking;
        Test.stopTest();

        List<Commission_Ledger__c> allEntries = [
            SELECT Status__c, Milestone__c, Agreement_Value_Basis__c, GST_On_Commission__c,
                   TDS_On_Commission__c, Hold_Reason__c
            FROM Commission_Ledger__c WHERE Booking__c = :s.booking.Id
            ORDER BY CreatedDate
        ];
        System.assertEquals(2, allEntries.size(), 'Paid entry untouched + new Clawback entry');
        // Original Paid entry unchanged
        System.assertEquals('Paid', allEntries[0].Status__c);
        System.assertEquals('Booking', allEntries[0].Milestone__c);
        // New offset entry: Accrued, Milestone='Clawback', negative basis/GST/TDS
        Commission_Ledger__c offset = allEntries[1];
        System.assertEquals('Accrued', offset.Status__c);
        System.assertEquals('Clawback', offset.Milestone__c);
        System.assertEquals(-existing.Agreement_Value_Basis__c, offset.Agreement_Value_Basis__c);
        System.assertEquals(-existing.GST_On_Commission__c, offset.GST_On_Commission__c);
        System.assertEquals(-existing.TDS_On_Commission__c, offset.TDS_On_Commission__c);
        System.assert(offset.Hold_Reason__c.contains(existing.Name),
            'Hold_Reason should reference original entry: ' + offset.Hold_Reason__c);
    }

    @IsTest
    static void testAccrueOnBooking_BulkOperation() {
        // Build 3 Bookings with 3 different CPs/tiers/projects
        Seed s1 = seedBookingWithCP('BUA', 'Platinum', '27ABCDE0001F1Z5');
        Seed s2 = seedBookingWithCP('BUB', 'Preferred', '27ABCDE0002F1Z5');
        Seed s3 = seedBookingWithCP('BUC', 'Standard', null);

        // Each had Booking-milestone accrued at seed time.
        Map<String, Decimal> expectedByTier = new Map<String, Decimal>{
            'Platinum' => 2, 'Preferred' => 2, 'Standard' => 2
        };
        // (We seeded all 3 rate cards with Booking_Pct=2 inside seedBookingWithCP.)

        for (Seed s : new List<Seed>{ s1, s2, s3 }) {
            List<Commission_Ledger__c> ledgers = [
                SELECT Rate_Pct__c FROM Commission_Ledger__c WHERE Booking__c = :s.booking.Id
            ];
            System.assertEquals(1, ledgers.size(), 'Each booking → 1 ledger entry');
            System.assertEquals(2, ledgers[0].Rate_Pct__c);
        }
    }
}
