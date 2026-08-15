@IsTest(SeeAllData=false)
private class ScoreAndRouteLeadActionTest {

    private static ScoreAndRouteLeadAction.ScoreRequest req(Id leadId, Integer matchCount) {
        ScoreAndRouteLeadAction.ScoreRequest r = new ScoreAndRouteLeadAction.ScoreRequest();
        r.leadId = leadId;
        r.matchCount = matchCount;
        return r;
    }

    @IsTest
    static void testScoreLead_HotScore() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'HOT' });
        Lead l = new Lead(
            LastName='Hot', Company='Hot Co', Status='New',
            Project_Interest__c=proj.Id,
            Urgency__c='Immediate',          // +40
            Budget_Min__c=10000000, Budget_Max__c=20000000,  // +15
            Unit_Type_Preference__c='3BHK',  // +5
            NRI_Flag__c=true                 // +10
        );
        insert l;

        Test.startTest();
        List<ScoreAndRouteLeadAction.ScoreResponse> resps =
            ScoreAndRouteLeadAction.scoreAndRoute(new List<ScoreAndRouteLeadAction.ScoreRequest>{ req(l.Id, 3) });  // +30
        Test.stopTest();

        // 40 + 15 + 5 + 10 + 30 = 100 → Hot
        System.assertEquals('Hot', resps[0].score, 'Should be Hot');
        Lead refreshed = [SELECT Lead_Score__c, Lead_Score_Rationale__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals('Hot', refreshed.Lead_Score__c);
        System.assert(refreshed.Lead_Score_Rationale__c.contains('Hot'));
    }

    @IsTest
    static void testScoreLead_ColdScore() {
        Lead l = new Lead(
            LastName='Cold', Company='Cold Co', Status='New',
            Urgency__c='Exploring'  // +5 only
        );
        insert l;

        Test.startTest();
        List<ScoreAndRouteLeadAction.ScoreResponse> resps =
            ScoreAndRouteLeadAction.scoreAndRoute(new List<ScoreAndRouteLeadAction.ScoreRequest>{ req(l.Id, 0) });
        Test.stopTest();

        // 5 only → Cold
        System.assertEquals('Cold', resps[0].score);
    }

    @IsTest
    static void testScoreLead_WarmScore() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'WRM' });
        Lead l = new Lead(
            LastName='Warm', Company='Warm Co', Status='New',
            Project_Interest__c=proj.Id,
            Urgency__c='3 months',           // +25
            Budget_Min__c=10000000, Budget_Max__c=20000000  // +15
        );
        insert l;

        Test.startTest();
        List<ScoreAndRouteLeadAction.ScoreResponse> resps =
            ScoreAndRouteLeadAction.scoreAndRoute(new List<ScoreAndRouteLeadAction.ScoreRequest>{ req(l.Id, 1) });  // +10
        Test.stopTest();

        // 25 + 15 + 10 = 50 → Warm
        System.assertEquals('Warm', resps[0].score, 'Should be Warm');
    }

    @IsTest
    static void testScoreLead_NoProjectQueue_OwnerUnchanged() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'NPQ' });
        Lead l = new Lead(
            LastName='Q', Company='Q Co', Status='New',
            Project_Interest__c=proj.Id,
            Urgency__c='Immediate'
        );
        insert l;
        Id originalOwner = [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId;

        Test.startTest();
        List<ScoreAndRouteLeadAction.ScoreResponse> resps =
            ScoreAndRouteLeadAction.scoreAndRoute(new List<ScoreAndRouteLeadAction.ScoreRequest>{ req(l.Id, 0) });
        Test.stopTest();

        System.assertEquals(null, resps[0].assignedQueue, 'No matching queue expected');
        Lead refreshed = [SELECT OwnerId, Lead_Score_Rationale__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(originalOwner, refreshed.OwnerId, 'Owner should be unchanged');
        System.assert(refreshed.Lead_Score_Rationale__c.contains('owner unchanged'));
    }

    @IsTest
    static void testScoreLead_NoLeadId() {
        Test.startTest();
        List<ScoreAndRouteLeadAction.ScoreResponse> resps =
            ScoreAndRouteLeadAction.scoreAndRoute(new List<ScoreAndRouteLeadAction.ScoreRequest>{ req(null, 0) });
        Test.stopTest();
        System.assertEquals('Cold', resps[0].score);
    }
}