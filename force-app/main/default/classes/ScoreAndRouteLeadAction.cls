/**
 * @description Scores a Lead Hot/Warm/Cold from urgency, budget, inventory-match count,
 *              NRI status and configuration preference, then best-effort routes it to a
 *              project-specific queue.
 *
 *              Bulkified: Leads are hydrated with one `Id IN :ids` query and the queue
 *              lookup is resolved once for the whole batch (queue names do not change
 *              within a transaction), replacing the 2 SOQL + 1 DML the old code issued
 *              per request. Scoring runs in memory and the Lead writes are batched into
 *              a single `update`. Cost: 2 SOQL + 1 DML for the whole invocation.
 */
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

    /**
     * @description Scores and routes every Lead in the request list.
     * @param requests One ScoreRequest per Lead.
     * @return One ScoreResponse per request, in the same order as the input.
     */
    @InvocableMethod(label='Score and Route Lead' description='Scores lead Hot/Warm/Cold and routes to a matching project queue (if any).')
    public static List<ScoreResponse> scoreAndRoute(List<ScoreRequest> requests) {
        List<ScoreResponse> results = new List<ScoreResponse>();
        if (requests == null || requests.isEmpty()) return results;

        // ---- PASS 1: harvest Lead Ids across the whole batch ----
        Set<Id> leadIds = new Set<Id>();
        for (ScoreRequest req : requests) {
            if (req != null && req.leadId != null) leadIds.add(req.leadId);
        }

        Map<Id, Lead> leadsById = new Map<Id, Lead>();
        if (!leadIds.isEmpty()) {
            leadsById = new Map<Id, Lead>([
                SELECT Id, Urgency__c, Budget_Min__c, Budget_Max__c,
                       Unit_Type_Preference__c, Project_Interest__c, NRI_Flag__c,
                       Project_Interest__r.Name
                FROM Lead WHERE Id IN :leadIds
                WITH SECURITY_ENFORCED
            ]);
        }

        // ---- PASS 2: resolve queue routing once for the whole batch ----
        Map<String, Group> queueByProjectName = resolveQueuesByProjectName(leadsById.values());

        // ---- PASS 3: score in memory, staging the Lead writes ----
        Map<Id, Lead> leadsToUpdate = new Map<Id, Lead>();
        for (ScoreRequest req : requests) {
            results.add(scoreOne(req, leadsById, queueByProjectName, leadsToUpdate));
        }

        // ---- PASS 4: one DML for the whole batch ----
        if (!leadsToUpdate.isEmpty()) update leadsToUpdate.values();

        return results;
    }

    /**
     * @description Resolves a project-name → Queue map for every Project referenced by
     *              the batch. Queues are a small, slow-changing set (tens per org), so
     *              one unfiltered read serves any number of Leads; the '%Project Name%'
     *              match is then applied in memory, mirroring the original LIKE.
     */
    private static Map<String, Group> resolveQueuesByProjectName(List<Lead> leads) {
        Map<String, Group> byProjectName = new Map<String, Group>();

        Set<String> projectNames = new Set<String>();
        for (Lead l : leads) {
            if (l.Project_Interest__c != null && l.Project_Interest__r != null
                && String.isNotBlank(l.Project_Interest__r.Name)) {
                projectNames.add(l.Project_Interest__r.Name);
            }
        }
        if (projectNames.isEmpty()) return byProjectName;

        List<Group> queues = [SELECT Id, Name FROM Group WHERE Type = 'Queue' ORDER BY Name ASC];
        for (String projectName : projectNames) {
            for (Group g : queues) {
                if (String.isNotBlank(g.Name) && g.Name.containsIgnoreCase(projectName)) {
                    byProjectName.put(projectName, g);
                    break;
                }
            }
        }
        return byProjectName;
    }

    private static ScoreResponse scoreOne(
        ScoreRequest req,
        Map<Id, Lead> leadsById,
        Map<String, Group> queueByProjectName,
        Map<Id, Lead> leadsToUpdate
    ) {
        ScoreResponse resp = new ScoreResponse();
        if (req == null || req.leadId == null) {
            resp.score = 'Cold';
            resp.rationale = 'No Lead Id provided.';
            return resp;
        }

        Lead l = leadsById.get(req.leadId);
        if (l == null) {
            resp.score = 'Cold';
            resp.rationale = 'Lead not found.';
            return resp;
        }

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
        if (l.Project_Interest__c != null && l.Project_Interest__r != null
            && String.isNotBlank(l.Project_Interest__r.Name)) {
            matchedQueue = queueByProjectName.get(l.Project_Interest__r.Name);
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
        leadsToUpdate.put(l.Id, toUpdate);

        resp.score = category;
        resp.rationale = rationale;
        resp.assignedQueue = (matchedQueue != null) ? matchedQueue.Name : null;
        return resp;
    }
}
