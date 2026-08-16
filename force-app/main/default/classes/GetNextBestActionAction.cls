/**
 * @description Recommends the next best action for an Opportunity based on stage,
 *              activity recency and key financial fields.
 *
 *              Bulkified: every Opportunity referenced across the request list is
 *              hydrated with a single `Id IN :ids` query; the recommendation itself
 *              is pure in-memory logic, so the whole invocation costs 1 SOQL and
 *              0 DML regardless of request count.
 */
public with sharing class GetNextBestActionAction {

    public class NBARequest {
        @InvocableVariable(required=true label='Opportunity Id')
        public Id opportunityId;
    }

    public class NBAResponse {
        @InvocableVariable public String recommendedAction;
        @InvocableVariable public String reasoning;
        @InvocableVariable public String urgency;
        @InvocableVariable public Integer daysSinceLastActivity;
    }

    /**
     * @description Produces a next-best-action recommendation per request.
     * @param requests One NBARequest per Opportunity.
     * @return One NBAResponse per request, in the same order as the input.
     */
    @InvocableMethod(label='Get Next Best Action' description='Recommends the next action for an Opportunity based on stage, activity, and key fields.')
    public static List<NBAResponse> getNBA(List<NBARequest> requests) {
        List<NBAResponse> results = new List<NBAResponse>();
        if (requests == null || requests.isEmpty()) return results;

        // ---- PASS 1: harvest Opportunity Ids across the whole batch ----
        Set<Id> opportunityIds = new Set<Id>();
        for (NBARequest req : requests) {
            if (req != null && req.opportunityId != null) opportunityIds.add(req.opportunityId);
        }

        // ---- PASS 2: one query for the whole batch ----
        Map<Id, Opportunity> oppsById = new Map<Id, Opportunity>();
        if (!opportunityIds.isEmpty()) {
            oppsById = new Map<Id, Opportunity>([
                SELECT Id, StageName, Primary_Unit__c, LastActivityDate, CloseDate, CreatedDate,
                       EOI_Amount__c, Token_Amount__c, Quoted_Gross_Value__c, Booking__c
                FROM Opportunity WHERE Id IN :opportunityIds
                WITH SECURITY_ENFORCED
            ]);
        }

        // ---- PASS 3: score in memory, preserving 1:1 request→result ordering ----
        for (NBARequest req : requests) {
            results.add(getOne(req, oppsById));
        }
        return results;
    }

    private static NBAResponse getOne(NBARequest req, Map<Id, Opportunity> oppsById) {
        NBAResponse resp = new NBAResponse();
        if (req == null || req.opportunityId == null) {
            resp.recommendedAction = 'Provide an Opportunity Id.';
            resp.urgency = 'Low';
            return resp;
        }

        Opportunity o = oppsById.get(req.opportunityId);
        if (o == null) {
            resp.recommendedAction = 'Opportunity not found.';
            resp.urgency = 'Low';
            return resp;
        }

        Date referenceDate = (o.LastActivityDate != null) ? o.LastActivityDate : o.CreatedDate.date();
        Integer days = referenceDate.daysBetween(Date.today());
        resp.daysSinceLastActivity = days;

        String stage = o.StageName;

        if (stage == 'Qualification' || stage == 'Discovery' || stage == 'New') {
            if (days >= 2) {
                resp.recommendedAction = 'Send introductory message. Lead is going cold.';
                resp.urgency = 'High';
            } else {
                resp.recommendedAction = 'Schedule qualification call.';
                resp.urgency = 'Medium';
            }
        } else if (stage == 'Qualified') {
            resp.recommendedAction = 'Schedule a site visit for this weekend.';
            resp.urgency = 'Medium';
        } else if (stage == 'Site Visit Scheduled') {
            if (o.CloseDate != null && o.CloseDate < Date.today()) {
                resp.recommendedAction = 'Update visit outcome and advance stage.';
                resp.urgency = 'High';
            } else {
                resp.recommendedAction = 'Confirm visit with buyer. Send directions.';
                resp.urgency = 'Low';
            }
        } else if (stage == 'Site Visit Done') {
            resp.recommendedAction = 'Follow up on visit feedback. Move to Negotiation if interested.';
            resp.urgency = 'High';
        } else if (stage == 'Negotiation') {
            if (o.Primary_Unit__c == null) {
                resp.recommendedAction = 'Block a unit for the buyer.';
                resp.urgency = 'High';
            } else if (days >= 3) {
                resp.recommendedAction = 'Send revised quotation.';
                resp.urgency = 'High';
            } else {
                resp.recommendedAction = 'Discuss payment plan options. Address buyer objections.';
                resp.urgency = 'Medium';
            }
        } else if (stage == 'EOI') {
            if (o.EOI_Amount__c == null || o.EOI_Amount__c == 0) {
                resp.recommendedAction = 'Collect EOI amount.';
                resp.urgency = 'High';
            } else {
                resp.recommendedAction = 'Convert EOI to token. Push for booking commitment.';
                resp.urgency = 'Medium';
            }
        } else if (stage == 'Token Paid') {
            resp.recommendedAction = 'Complete documentation. Process booking.';
            resp.urgency = 'High';
        } else if (stage == 'Closed Won (Booked)' || stage == 'Closed Won') {
            resp.recommendedAction = 'Booking confirmed. Hand over to post-sales team.';
            resp.urgency = 'Low';
        } else if (stage == 'Closed Lost') {
            resp.recommendedAction = 'No action needed. Opportunity is closed.';
            resp.urgency = 'Low';
        } else {
            resp.recommendedAction = 'Review opportunity and determine next step.';
            resp.urgency = 'Medium';
        }

        resp.reasoning = 'Stage: ' + stage + '. Days since last activity: ' + days + '.';
        return resp;
    }
}
