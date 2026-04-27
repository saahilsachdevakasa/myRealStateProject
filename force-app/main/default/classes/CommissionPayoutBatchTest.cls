@IsTest(SeeAllData=false)
private class CommissionPayoutBatchTest {

    @IsTest
    static void testPayoutBatch_GroupsByCp() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{
            'Project_Code__c' => 'PYT'
        });
        Tower__c tower = TestDataFactory.createTower(proj.Id, null);
        Account cp1 = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'PayoutCP1' });
        Account cp2 = TestDataFactory.createCPAccount(new Map<String, Object>{ 'Name' => 'PayoutCP2' });

        // Create 2 Bookings (one per CP) without going through Closed Won —
        // use TestDataFactory.createBooking directly with required fields.
        Account buyer = TestDataFactory.createAccount(null);

        // Booking for CP1 — block Unit, then create
        Unit__c u1 = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Status__c' => 'Blocked'
        });
        Opportunity o1 = TestDataFactory.createOpportunity(buyer.Id, new Map<String, Object>{
            'StageName' => 'Token Paid',
            'Project__c' => proj.Id, 'Primary_Unit__c' => u1.Id,
            'Quoted_Gross_Value__c' => 5000000
        });
        Booking__c b1 = TestDataFactory.createBooking(o1.Id, u1.Id, buyer.Id, null);

        Unit__c u2 = TestDataFactory.createUnit(tower.Id, new Map<String, Object>{
            'Unit_Status__c' => 'Blocked'
        });
        Opportunity o2 = TestDataFactory.createOpportunity(buyer.Id, new Map<String, Object>{
            'StageName' => 'Token Paid',
            'Project__c' => proj.Id, 'Primary_Unit__c' => u2.Id,
            'Quoted_Gross_Value__c' => 7000000
        });
        Booking__c b2 = TestDataFactory.createBooking(o2.Id, u2.Id, buyer.Id, null);

        // 3 ledger entries per CP (Accrued, no Payout)
        for (Integer i = 0; i < 3; i++) {
            TestDataFactory.createCommissionLedger(b1.Id, cp1.Id, new Map<String, Object>{
                'Agreement_Value_Basis__c' => 1000000, 'Rate_Pct__c' => 2,
                'GST_On_Commission__c' => 0, 'TDS_On_Commission__c' => 1000
            });
            TestDataFactory.createCommissionLedger(b2.Id, cp2.Id, new Map<String, Object>{
                'Agreement_Value_Basis__c' => 2000000, 'Rate_Pct__c' => 1,
                'GST_On_Commission__c' => 0, 'TDS_On_Commission__c' => 1000
            });
        }

        Test.startTest();
        Database.executeBatch(new CommissionPayoutBatch(), 200);
        Test.stopTest();

        List<Commission_Payout__c> payouts = [
            SELECT Id, Channel_Partner__c, Status__c, Payout_Month__c, Entry_Count__c,
                   Gross_Commission__c, GST_Total__c, TDS_Total__c, Net_Payable__c
            FROM Commission_Payout__c ORDER BY Channel_Partner__c
        ];
        System.assertEquals(2, payouts.size(), 'One Payout per CP');

        String expectedMonth = String.valueOf(Date.today().year()) + '-'
            + String.valueOf(Date.today().month()).leftPad(2, '0');

        for (Commission_Payout__c p : payouts) {
            System.assertEquals('Draft', p.Status__c);
            System.assertEquals(expectedMonth, p.Payout_Month__c);
            System.assertEquals(3, p.Entry_Count__c, 'Each CP had 3 entries');
        }

        // All 6 ledger entries linked to their respective Payouts
        Integer linked = [
            SELECT COUNT() FROM Commission_Ledger__c
            WHERE Channel_Partner__c IN (:cp1.Id, :cp2.Id) AND Payout__c != null
        ];
        System.assertEquals(6, linked, 'All ledger entries linked');
    }

    @IsTest
    static void testPayoutBatch_NoEligibleEntries() {
        // No ledger entries → batch runs cleanly with zero payouts
        Test.startTest();
        Database.executeBatch(new CommissionPayoutBatch(), 200);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Commission_Payout__c]);
    }

    @IsTest
    static void testSchedulable() {
        Test.startTest();
        String cron = '0 0 1 1 1 ? 2099';
        String jobId = System.schedule('TestPayoutBatch', cron, new CommissionPayoutBatch());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Schedulable interface accepted');
    }
}
