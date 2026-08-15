public with sharing class MatchInventoryAction {

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

    @InvocableMethod(label='Match Inventory for Lead' description='Finds up to 3 available units matching the lead preferences and updates Lead.Suggested_Units__c.')
    public static List<MatchResponse> matchInventory(List<MatchRequest> requests) {
        List<MatchResponse> results = new List<MatchResponse>();
        for (MatchRequest req : requests) {
            results.add(matchOne(req));
        }
        return results;
    }

    private static MatchResponse matchOne(MatchRequest req) {
        MatchResponse resp = new MatchResponse();
        resp.matches = new List<UnitMatch>();
        resp.matchCount = 0;

        if (req == null || req.leadId == null) {
            resp.summary = 'No Lead Id provided.';
            return resp;
        }

        List<Lead> leads = [
            SELECT Id, Project_Interest__c, Budget_Min__c, Budget_Max__c,
                   Unit_Type_Preference__c, Location_Preference__c,
                   Project_Interest__r.Name
            FROM Lead WHERE Id = :req.leadId
            WITH SECURITY_ENFORCED LIMIT 1
        ];
        if (leads.isEmpty()) {
            resp.summary = 'Lead not found.';
            return resp;
        }
        Lead lead = leads[0];
        if (lead.Project_Interest__c == null) {
            resp.summary = 'Lead has no Project of Interest. Set Project_Interest__c before matching inventory.';
            return resp;
        }

        List<Unit__c> units = queryAvailableUnits(lead);

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
        update new Lead(Id = lead.Id, Suggested_Units__c = (suggested.length() > 0 ? suggested : null));

        return resp;
    }

    private static List<Unit__c> queryAvailableUnits(Lead lead) {
        Decimal minB = lead.Budget_Min__c;
        Decimal maxB = lead.Budget_Max__c;
        String soql = 'SELECT Id, Name, Unit_Code__c, Configuration__c, Base_Price__c, ' +
            'Carpet_Area_sqft__c, Super_BuiltUp_Area_sqft__c, BSP_Per_Sqft__c, ' +
            'Facing__c, Corner_Unit__c, Park_Facing__c, Floor__c, Unit_Number__c, ' +
            'Tower__r.Name, Tower__r.Project__r.Name, Tower__r.Project__r.Project_Code__c ' +
            'FROM Unit__c WHERE Tower__r.Project__c = :pid AND Unit_Status__c = \'Available\'';
        if (minB != null) soql += ' AND Base_Price__c >= :minB';
        if (maxB != null) soql += ' AND Base_Price__c <= :maxB';
        soql += ' ORDER BY Base_Price__c ASC LIMIT 50';

        Map<String, Object> binds = new Map<String, Object>{
            'pid' => lead.Project_Interest__c,
            'minB' => minB,
            'maxB' => maxB
        };
        return (List<Unit__c>) Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
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