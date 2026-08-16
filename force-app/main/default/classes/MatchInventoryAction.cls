/**
 * @description Finds the best-matching available Units for a Lead's stated preferences
 *              and stamps a human-readable summary onto `Lead.Suggested_Units__c`.
 *
 *              Bulkified: Leads are hydrated with one `Id IN :ids` query, and the unit
 *              search is issued once for every distinct Project referenced across the
 *              batch (`Tower__r.Project__c IN :pids`) rather than once per Lead. Budget
 *              filtering, the per-Lead 50-unit cap, preference filtering and scoring all
 *              run in memory. The `Suggested_Units__c` writes are batched into a single
 *              `update`. Total cost: 2 SOQL + 1 DML for the whole invocation.
 */
public with sharing class MatchInventoryAction {

    /** Per-Lead cap on candidate units considered — was the `LIMIT 50` on the old per-Lead query. */
    private static final Integer MAX_UNITS_PER_LEAD = 50;

    /**
     * Ceiling on rows pulled by the single batched unit query. The full demo portfolio is
     * 720 units, so this covers every Project in one pass with headroom. Rows are ordered
     * by Base_Price ASC, so if a far larger org ever hits this ceiling it is the most
     * expensive units that drop out — the same end of the range the old per-Lead
     * `LIMIT 50` discarded first.
     */
    private static final Integer MAX_UNITS_SCANNED = 2000;

    public class MatchRequest {
        @InvocableVariable(required=true label='Lead Id')
        public Id leadId;
    }

    public class UnitMatch {
        @InvocableVariable public String unitCode;
        @InvocableVariable public String unitId;
        @InvocableVariable public String configuration;
        @InvocableVariable public Decimal basePrice;
        @InvocableVariable public Decimal carpetArea;
        @InvocableVariable public String facing;
        @InvocableVariable public Boolean cornerUnit;
        @InvocableVariable public Boolean parkFacing;
        @InvocableVariable public String projectName;
        @InvocableVariable public String rationale;
        @InvocableVariable public Integer matchScore;
    }

    public class MatchResponse {
        @InvocableVariable public List<UnitMatch> matches;
        @InvocableVariable public Integer matchCount;
        @InvocableVariable public String summary;
    }

    /**
     * @description Matches inventory for every Lead in the request list.
     * @param requests One MatchRequest per Lead.
     * @return One MatchResponse per request, in the same order as the input.
     */
    @InvocableMethod(label='Match Inventory for Lead' description='Finds up to 3 available units matching the lead preferences and updates Lead.Suggested_Units__c.')
    public static List<MatchResponse> matchInventory(List<MatchRequest> requests) {
        List<MatchResponse> results = new List<MatchResponse>();
        if (requests == null || requests.isEmpty()) return results;

        // ---- PASS 1: harvest Lead Ids across the whole batch ----
        Set<Id> leadIds = new Set<Id>();
        for (MatchRequest req : requests) {
            if (req != null && req.leadId != null) leadIds.add(req.leadId);
        }

        Map<Id, Lead> leadsById = new Map<Id, Lead>();
        if (!leadIds.isEmpty()) {
            leadsById = new Map<Id, Lead>([
                SELECT Id, Project_Interest__c, Budget_Min__c, Budget_Max__c,
                       Unit_Type_Preference__c, Location_Preference__c,
                       Project_Interest__r.Name
                FROM Lead WHERE Id IN :leadIds
                WITH SECURITY_ENFORCED
            ]);
        }

        // ---- PASS 2: one unit query covering every Project referenced by the batch ----
        Set<Id> projectIds = new Set<Id>();
        for (Lead l : leadsById.values()) {
            if (l.Project_Interest__c != null) projectIds.add(l.Project_Interest__c);
        }
        Map<Id, List<Unit__c>> availableUnitsByProject = queryAvailableUnitsByProject(projectIds);

        // ---- PASS 3: match and score in memory, staging the Lead writes ----
        Map<Id, Lead> leadsToUpdate = new Map<Id, Lead>();
        for (MatchRequest req : requests) {
            results.add(matchOne(req, leadsById, availableUnitsByProject, leadsToUpdate));
        }

        // ---- PASS 4: one DML for the whole batch ----
        if (!leadsToUpdate.isEmpty()) update leadsToUpdate.values();

        return results;
    }

    private static MatchResponse matchOne(
        MatchRequest req,
        Map<Id, Lead> leadsById,
        Map<Id, List<Unit__c>> availableUnitsByProject,
        Map<Id, Lead> leadsToUpdate
    ) {
        MatchResponse resp = new MatchResponse();
        resp.matches = new List<UnitMatch>();
        resp.matchCount = 0;

        if (req == null || req.leadId == null) {
            resp.summary = 'No Lead Id provided.';
            return resp;
        }

        Lead lead = leadsById.get(req.leadId);
        if (lead == null) {
            resp.summary = 'Lead not found.';
            return resp;
        }
        if (lead.Project_Interest__c == null) {
            resp.summary = 'Lead has no Project of Interest. Set Project_Interest__c before matching inventory.';
            return resp;
        }

        List<Unit__c> units = unitsInBudget(lead, availableUnitsByProject.get(lead.Project_Interest__c));

        Set<String> prefs = parsePreferences(lead.Unit_Type_Preference__c);
        List<UnitMatch> scored = new List<UnitMatch>();
        for (Unit__c u : units) {
            if (!prefs.isEmpty() && !prefs.contains(u.Configuration__c)) continue;
            scored.add(buildMatch(u, lead, prefs));
        }
        scored.sort(new ScoreComparator());

        Integer top = Math.min(3, scored.size());
        for (Integer i = 0; i < top; i++) resp.matches.add(scored[i]);
        resp.matchCount = resp.matches.size();

        if (resp.matches.isEmpty()) {
            resp.summary = 'No matching available units in ' + lead.Project_Interest__r.Name + '.';
        } else {
            resp.summary = 'Found ' + resp.matchCount + ' matching unit(s) in ' + lead.Project_Interest__r.Name + '.';
        }

        String suggested = '';
        for (UnitMatch m : resp.matches) {
            if (suggested.length() > 0) suggested += '\n\n';
            suggested += m.unitCode + ' — ' + m.rationale;
        }
        leadsToUpdate.put(
            lead.Id,
            new Lead(Id = lead.Id, Suggested_Units__c = (suggested.length() > 0 ? suggested : null))
        );

        return resp;
    }

    /**
     * @description One query for every Project in the batch, partitioned in memory.
     *              Ordered by Base_Price ASC so each partition preserves the price
     *              ordering the per-Lead budget filter and 50-row cap rely on.
     */
    private static Map<Id, List<Unit__c>> queryAvailableUnitsByProject(Set<Id> projectIds) {
        Map<Id, List<Unit__c>> byProject = new Map<Id, List<Unit__c>>();
        if (projectIds == null || projectIds.isEmpty()) return byProject;

        String soql = 'SELECT Id, Name, Unit_Code__c, Configuration__c, Base_Price__c, ' +
            'Carpet_Area_sqft__c, Super_BuiltUp_Area_sqft__c, BSP_Per_Sqft__c, ' +
            'Facing__c, Corner_Unit__c, Park_Facing__c, Floor__c, Unit_Number__c, ' +
            'Tower__r.Name, Tower__r.Project__c, Tower__r.Project__r.Name, Tower__r.Project__r.Project_Code__c ' +
            'FROM Unit__c WHERE Tower__r.Project__c IN :pids AND Unit_Status__c = \'Available\' ' +
            'ORDER BY Base_Price__c ASC LIMIT ' + MAX_UNITS_SCANNED;

        Map<String, Object> binds = new Map<String, Object>{ 'pids' => projectIds };
        for (Unit__c u : (List<Unit__c>) Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
            if (u.Tower__r == null || u.Tower__r.Project__c == null) continue;
            Id pid = u.Tower__r.Project__c;
            if (!byProject.containsKey(pid)) byProject.put(pid, new List<Unit__c>());
            byProject.get(pid).add(u);
        }
        return byProject;
    }

    /**
     * @description Applies the Lead's budget window in memory, mirroring the SOQL
     *              semantics of the old per-Lead query: a null Base_Price is excluded
     *              whenever a bound is supplied, and at most MAX_UNITS_PER_LEAD of the
     *              cheapest qualifying units are returned.
     */
    private static List<Unit__c> unitsInBudget(Lead lead, List<Unit__c> projectUnits) {
        List<Unit__c> inBudget = new List<Unit__c>();
        if (projectUnits == null || projectUnits.isEmpty()) return inBudget;

        Decimal minB = lead.Budget_Min__c;
        Decimal maxB = lead.Budget_Max__c;
        for (Unit__c u : projectUnits) {
            if (minB != null && (u.Base_Price__c == null || u.Base_Price__c < minB)) continue;
            if (maxB != null && (u.Base_Price__c == null || u.Base_Price__c > maxB)) continue;
            inBudget.add(u);
            if (inBudget.size() == MAX_UNITS_PER_LEAD) break;
        }
        return inBudget;
    }

    private static Set<String> parsePreferences(String prefField) {
        Set<String> result = new Set<String>();
        if (String.isBlank(prefField)) return result;
        for (String p : prefField.split(';')) {
            if (String.isNotBlank(p)) result.add(p.trim());
        }
        return result;
    }

    private static UnitMatch buildMatch(Unit__c u, Lead lead, Set<String> prefs) {
        UnitMatch m = new UnitMatch();
        m.unitId = u.Id;
        m.unitCode = u.Unit_Code__c;
        m.configuration = u.Configuration__c;
        m.basePrice = u.Base_Price__c;
        m.carpetArea = u.Carpet_Area_sqft__c;
        m.facing = u.Facing__c;
        m.cornerUnit = u.Corner_Unit__c;
        m.parkFacing = u.Park_Facing__c;
        m.projectName = (u.Tower__r != null && u.Tower__r.Project__r != null) ? u.Tower__r.Project__r.Name : null;

        Integer score = 0;
        List<String> reasons = new List<String>();

        if (!prefs.isEmpty() && prefs.contains(u.Configuration__c)) {
            score += 30; reasons.add('config matches');
        }
        if (lead.Budget_Min__c != null && lead.Budget_Max__c != null && u.Base_Price__c != null) {
            Decimal range = lead.Budget_Max__c - lead.Budget_Min__c;
            Decimal lower = lead.Budget_Min__c + range * 0.25;
            Decimal upper = lead.Budget_Min__c + range * 0.75;
            if (u.Base_Price__c >= lower && u.Base_Price__c <= upper) {
                score += 25; reasons.add('price in middle of budget');
            }
        }
        if (u.Corner_Unit__c == true) { score += 15; reasons.add('corner unit'); }
        if (u.Park_Facing__c == true) { score += 15; reasons.add('park facing'); }
        if (u.Floor__c != null && u.Floor__c > 2) { score += 10; reasons.add('higher floor'); }
        if (u.Facing__c == 'East' || u.Facing__c == 'North') {
            score += 5; reasons.add(u.Facing__c + '-facing');
        }
        m.matchScore = score;

        m.rationale = u.Configuration__c
            + (u.Carpet_Area_sqft__c != null ? ', ' + u.Carpet_Area_sqft__c.intValue() + ' sqft' : '')
            + (u.Floor__c != null ? ', Floor ' + u.Floor__c.intValue() : '')
            + (String.isNotBlank(u.Facing__c) ? ', ' + u.Facing__c + '-facing' : '')
            + (u.Corner_Unit__c == true ? ', Corner' : '')
            + (u.Park_Facing__c == true ? ', Park-facing' : '')
            + '. Price ' + fmtCurrency(u.Base_Price__c)
            + (reasons.isEmpty() ? '' : '. ' + String.join(reasons, ', '))
            + '. Score: ' + score + '/100.';
        return m;
    }

    private static String fmtCurrency(Decimal v) {
        if (v == null) return 'n/a';
        if (v >= 10000000) return '₹' + (v / 10000000).setScale(2) + 'Cr';
        if (v >= 100000) return '₹' + (v / 100000).setScale(2) + 'L';
        return '₹' + v.intValue();
    }

    private class ScoreComparator implements Comparator<UnitMatch> {
        public Integer compare(UnitMatch a, UnitMatch b) {
            Integer aScore = (a.matchScore == null) ? 0 : a.matchScore;
            Integer bScore = (b.matchScore == null) ? 0 : b.matchScore;
            if (bScore > aScore) return 1;
            if (bScore < aScore) return -1;
            return 0;
        }
    }
}
