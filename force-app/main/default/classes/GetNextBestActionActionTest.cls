@IsTest(SeeAllData=false)
private class GetNextBestActionActionTest {

    private static GetNextBestActionAction.NBARequest req(Id oppId) {
        GetNextBestActionAction.NBARequest r = new GetNextBestActionAction.NBARequest();
        r.opportunityId = oppId;
        return r;
    }

    private static Opportunity oppFor(Project__c proj, String stage) {
        Account buyer = TestDataFactory.createAccount(new Map<String, Object>{ 'Name' => 'NBA Buyer ' + stage });
        return TestDataFactory.createOpportunity(buyer.Id, new Map<String, Object>{
            'StageName' => stage, 'Project__c' => proj.Id,
            'EOI_Amount__c' => 100000, 'Token_Amount__c' => 200000,
            'Quoted_Gross_Value__c' => 5000000, 'Source_Channel__c' => 'Walk-in'
        });
    }

    @IsTest
    static void testNBA_QualificationStage() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'NQA' });
        Opportunity o = oppFor(proj, 'Qualification');

        Test.startTest();
        List<GetNextBestActionAction.NBAResponse> resps =
            GetNextBestActionAction.getNBA(new List<GetNextBestActionAction.NBARequest>{ req(o.Id) });
        Test.stopTest();

        System.assert(resps[0].recommendedAction != null);
        System.assert(resps[0].recommendedAction.toLowerCase().contains('call') || resps[0].recommendedAction.toLowerCase().contains('introductory'));
    }

    @IsTest
    static void testNBA_NegotiationStage_NoPrimaryUnit() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'NNS' });
        Account buyer = TestDataFactory.createAccount(new Map<String, Object>{ 'Name' => 'NBA Negot' });
        Opportunity o = TestDataFactory.createOpportunity(buyer.Id, new Map<String, Object>{
            'StageName' => 'Negotiation', 'Project__c' => proj.Id,
            'Quoted_Gross_Value__c' => 5000000, 'Source_Channel__c' => 'Walk-in'
            // No Primary_Unit__c
        });

        Test.startTest();
        List<GetNextBestActionAction.NBAResponse> resps =
            GetNextBestActionAction.getNBA(new List<GetNextBestActionAction.NBARequest>{ req(o.Id) });
        Test.stopTest();

        System.assert(resps[0].recommendedAction.toLowerCase().contains('block'),
            'Expected blocking recommendation, got: ' + resps[0].recommendedAction);
        System.assertEquals('High', resps[0].urgency);
    }

    @IsTest
    static void testNBA_ClosedWon() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'NCW' });
        Opportunity o = oppFor(proj, 'Closed Won (Booked)');

        Test.startTest();
        List<GetNextBestActionAction.NBAResponse> resps =
            GetNextBestActionAction.getNBA(new List<GetNextBestActionAction.NBARequest>{ req(o.Id) });
        Test.stopTest();

        System.assert(resps[0].recommendedAction.toLowerCase().contains('post-sales'),
            'Expected post-sales handover, got: ' + resps[0].recommendedAction);
        System.assertEquals('Low', resps[0].urgency);
    }

    @IsTest
    static void testNBA_EOIStage_NoEOIAmount() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'NEO' });
        Account buyer = TestDataFactory.createAccount(new Map<String, Object>{ 'Name' => 'NBA EOI' });
        Opportunity o = TestDataFactory.createOpportunity(buyer.Id, new Map<String, Object>{
            'StageName' => 'EOI', 'Project__c' => proj.Id,
            'EOI_Amount__c' => 0,
            'Quoted_Gross_Value__c' => 5000000, 'Source_Channel__c' => 'Walk-in'
        });

        Test.startTest();
        List<GetNextBestActionAction.NBAResponse> resps =
            GetNextBestActionAction.getNBA(new List<GetNextBestActionAction.NBARequest>{ req(o.Id) });
        Test.stopTest();

        System.assert(resps[0].recommendedAction.toLowerCase().contains('eoi'),
            'Expected EOI collection prompt, got: ' + resps[0].recommendedAction);
    }

    @IsTest
    static void testNBA_UnmappedStage_DefaultBranch() {
        Project__c proj = TestDataFactory.createProject(new Map<String, Object>{ 'Project_Code__c' => 'NDF' });
        Opportunity o = oppFor(proj, 'Proposal/Quote');

        Test.startTest();
        List<GetNextBestActionAction.NBAResponse> resps =
            GetNextBestActionAction.getNBA(new List<GetNextBestActionAction.NBARequest>{ req(o.Id) });
        Test.stopTest();

        System.assert(resps[0].recommendedAction.toLowerCase().contains('review'),
            'Default branch should ask the user to review');
    }

    @IsTest
    static void testNBA_OppNotFound() {
        Test.startTest();
        Id fakeId = '006000000000000AAA';
        List<GetNextBestActionAction.NBAResponse> resps =
            GetNextBestActionAction.getNBA(new List<GetNextBestActionAction.NBARequest>{ req(fakeId) });
        Test.stopTest();
        System.assert(resps[0].recommendedAction.contains('not found'));
    }

    @IsTest
    static void testNBA_NoOppId() {
        Test.startTest();
        List<GetNextBestActionAction.NBAResponse> resps =
            GetNextBestActionAction.getNBA(new List<GetNextBestActionAction.NBARequest>{ req(null) });
        Test.stopTest();
        System.assert(resps[0].recommendedAction.contains('Opportunity Id'));
    }
}