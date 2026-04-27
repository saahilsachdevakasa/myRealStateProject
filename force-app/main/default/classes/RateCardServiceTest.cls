@IsTest(SeeAllData=false)
private class RateCardServiceTest {

    @IsTest
    static void testGetActiveRateCard_Found() {
        Project__c proj = TestDataFactory.createProject(null);
        Commission_Rate_Card__c card = TestDataFactory.createRateCard(proj.Id, new Map<String, Object>{
            'CP_Tier__c' => 'Platinum',
            'Booking_Pct__c' => 0.02,
            'Agreement_Pct__c' => 0.01,
            'Registration_Pct__c' => 0.005,
            'Effective_From__c' => Date.today().addMonths(-3)
        });

        Test.startTest();
        Commission_Rate_Card__c result = RateCardService.getActiveRateCard(proj.Id, 'Platinum');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Active rate card should be found');
        System.assertEquals(card.Id, result.Id, 'Returned card Id should match');
        System.assertEquals('Platinum', result.CP_Tier__c, 'Tier should match');
    }

    @IsTest
    static void testGetActiveRateCard_NotFound_WrongTier() {
        Project__c proj = TestDataFactory.createProject(null);
        TestDataFactory.createRateCard(proj.Id, new Map<String, Object>{
            'CP_Tier__c' => 'Platinum',
            'Effective_From__c' => Date.today().addMonths(-3)
        });

        Test.startTest();
        Commission_Rate_Card__c result = RateCardService.getActiveRateCard(proj.Id, 'Standard');
        Test.stopTest();

        System.assertEquals(null, result, 'No card should match Standard tier');
    }

    @IsTest
    static void testGetActiveRateCard_NotFound_Expired() {
        Project__c proj = TestDataFactory.createProject(null);
        TestDataFactory.createRateCard(proj.Id, new Map<String, Object>{
            'CP_Tier__c' => 'Platinum',
            'Effective_From__c' => Date.today().addMonths(-12),
            'Effective_To__c' => Date.today().addDays(-1)
        });

        Test.startTest();
        Commission_Rate_Card__c result = RateCardService.getActiveRateCard(proj.Id, 'Platinum');
        Test.stopTest();

        System.assertEquals(null, result, 'Expired card should not match Active__c filter');
    }

    @IsTest
    static void testGetActiveRateCards_Bulk() {
        List<String> codes = new List<String>{'BLA', 'BLB', 'BLC'};
        List<Project__c> projects = new List<Project__c>();
        for (Integer i = 0; i < 3; i++) {
            projects.add(TestDataFactory.createProject(new Map<String, Object>{
                'Project_Code__c' => codes[i],
                'Name' => 'Bulk Project ' + codes[i]
            }));
        }
        List<String> tiers = new List<String>{'Standard', 'Preferred', 'Platinum'};
        for (Project__c p : projects) {
            for (String tier : tiers) {
                TestDataFactory.createRateCard(p.Id, new Map<String, Object>{
                    'CP_Tier__c' => tier,
                    'Effective_From__c' => Date.today().addMonths(-1)
                });
            }
        }

        Set<Id> projectIds = new Set<Id>();
        for (Project__c p : projects) projectIds.add(p.Id);
        Set<String> tierSet = new Set<String>{'Standard', 'Preferred', 'Platinum'};

        Test.startTest();
        Map<String, Commission_Rate_Card__c> result = RateCardService.getActiveRateCards(projectIds, tierSet);
        Test.stopTest();

        System.assertEquals(9, result.size(), 'Expected 9 cards (3 projects x 3 tiers)');
        for (Project__c p : projects) {
            for (String tier : tiers) {
                String key = RateCardService.buildKey(p.Id, tier);
                System.assert(result.containsKey(key), 'Map should contain key ' + key);
                System.assertEquals(p.Id, result.get(key).Project__c, 'Project Id mismatch');
                System.assertEquals(tier, result.get(key).CP_Tier__c, 'Tier mismatch');
            }
        }
    }

    @IsTest
    static void testGetActiveRateCard_MostRecentWins() {
        Project__c proj = TestDataFactory.createProject(null);
        TestDataFactory.createRateCard(proj.Id, new Map<String, Object>{
            'CP_Tier__c' => 'Platinum',
            'Booking_Pct__c' => 0.01,
            'Effective_From__c' => Date.today().addMonths(-12)
        });
        Commission_Rate_Card__c newer = TestDataFactory.createRateCard(proj.Id, new Map<String, Object>{
            'CP_Tier__c' => 'Platinum',
            'Booking_Pct__c' => 0.02,
            'Effective_From__c' => Date.today().addMonths(-1)
        });

        Test.startTest();
        Commission_Rate_Card__c result = RateCardService.getActiveRateCard(proj.Id, 'Platinum');
        Test.stopTest();

        System.assertEquals(newer.Id, result.Id, 'Most recent Effective_From card should win');
        System.assertEquals(0.02, result.Booking_Pct__c, 'Newer rate should be returned');
    }

    @IsTest
    static void testGetActiveRateCard_NullInputs() {
        Test.startTest();
        System.assertEquals(null, RateCardService.getActiveRateCard(null, 'Platinum'), 'Null project returns null');
        System.assertEquals(null, RateCardService.getActiveRateCard(null, null), 'Null inputs return null');
        Map<String, Commission_Rate_Card__c> emptyResult = RateCardService.getActiveRateCards(null, null);
        System.assertEquals(0, emptyResult.size(), 'Null inputs return empty map');
        Test.stopTest();
    }
}
