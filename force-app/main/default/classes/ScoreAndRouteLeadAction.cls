public with sharing class ScoreAndRouteLeadAction {

    public class ScoreRequest {
        @InvocableVariable(required=true label='Lead Id')
        public Id leadId;
        @InvocableVariable(label='Match Count')
        public Integer matchCount;
    }

    public class ScoreResponse {
        @InvocableVariable public String score;
        @InvocableVariable public String rationale;
        @InvocableVariable public String assignedQueue;
    }

    @InvocableMethod(label='Score and Route Lead' description='Scores lead Hot/Warm/Cold and routes to a matching project queue (if any).')
    public static List<ScoreResponse> scoreAndRoute(List<ScoreRequest> requests) {
        List<ScoreResponse> results = new List<ScoreResponse>();
        for (ScoreRequest req : requests) {
            results.add(scoreOne(req));
        }
        return results;
    }

    private static ScoreResponse scoreOne(ScoreRequest req) {
        ScoreResponse resp = new ScoreResponse();
        if (req == null || req.leadId == null) {
            resp.score = 'Cold';
            resp.rationale = 'No Lead Id provided.';
            return resp;
        }

        List<Lead> leads = [
            SELECT Id, Urgency__c, Budget_Min__c, Budget_Max__c,
                   Unit_Type_Preference__c, Project_Interest__c, NRI_Flag__c,
                   Project_Interest__r.Name
            FROM Lead WHERE Id = :req.leadId
            WITH SECURITY_ENFORCED LIMIT 1
        ];
        if (leads.isEmpty()) {
            resp.score = 'Cold';
            resp.rationale = 'Lead not found.';
            return resp;
        }
        Lead l = leads[0];

        Integer score = 0;
        List<String> parts = new List<String>();

        if (l.Urgency__c == 'Immediate') { score += 40; parts.add('Urgency: Immediate (+40)'); }
        else if (l.Urgency__c == '3 months') { score += 25; parts.add('Urgency: 3 months (+25)'); }
        else if (l.Urgency__c == '6 months') { score += 15; parts.add('Urgency: 6 months (+15)'); }
        else if (l.Urgency__c == 'Exploring') { score += 5; parts.add('Urgency: Exploring (+5)'); }

        if (l.Budget_Min__c != null && l.Budget_Max__c != null) {
            score += 15; parts.add('Budget defined (+15)');
        } else if (l.Budget_Min__c != null || l.Budget_Max__c != null) {
            score += 5; parts.add('Partial budget (+5)');
        }

        Integer mc = (req.matchCount == null) ? 0 : req.matchCount;
        if (mc >= 3) { score += 30; parts.add('3+ inventory matches (+30)'); }
        else if (mc == 2) { score += 20; parts.add('2 matches (+20)'); }
        else if (mc == 1) { score += 10; parts.add('1 match (+10)'); }

        if (l.NRI_Flag__c == true) { score += 10; parts.add('NRI buyer (+10)'); }
        if (String.isNotBlank(l.Unit_Type_Preference__c)) { score += 5; parts.add('Specific config preference (+5)'); }

        String category;
        if (score >= 70) category = 'Hot';
        else if (score >= 40) category = 'Warm';
        else category = 'Cold';

        // Best-effort queue routing (no project queues exist in SDO today;
        // documented as acceptable per spec D3)
        Group matchedQueue = null;
        if (l.Project_Interest__c != null && String.isNotBlank(l.Project_Interest__r.Name)) {
            String pattern = '%' + l.Project_Interest__r.Name + '%';
            List<Group> queues = [
                SELECT Id, Name FROM Group
                WHERE Type = 'Queue' AND Name LIKE :pattern
                LIMIT 1
            ];
            if (!queues.isEmpty()) matchedQueue = queues[0];
        }

        String rationale = 'Score: ' + score + '/100 → ' + category + '. '
            + String.join(parts, ', ') + '.';
        if (matchedQueue != null) {
            rationale += ' Routed to: ' + matchedQueue.Name + '.';
        } else {
            rationale += ' No project-specific queue found — owner unchanged.';
        }

        Lead toUpdate = new Lead(
            Id = l.Id,
            Lead_Score__c = category,
            Lead_Score_Rationale__c = rationale
        );
        if (matchedQueue != null) toUpdate.OwnerId = matchedQueue.Id;
        update toUpdate;

        resp.score = category;
        resp.rationale = rationale;
        resp.assignedQueue = (matchedQueue != null) ? matchedQueue.Name : null;
        return resp;
    }
}