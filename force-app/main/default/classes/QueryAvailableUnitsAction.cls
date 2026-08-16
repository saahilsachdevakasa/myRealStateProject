/**
 * @description Searches available Units by project, configuration, price, facing, floor
 *              and amenity filters. Backs the Agentforce inventory-lookup topic.
 *
 *              Bulkified: every project reference across the whole `queries` list — Id,
 *              Name (fuzzy) or Project_Code__c (exact) — is resolved in a single query
 *              up front, replacing the up-to-2 project lookups the old code issued per
 *              query object. The unit search itself stays per query object because each
 *              carries its own arbitrary filter combination and row limit; batching it
 *              would mean pulling the whole Unit table into heap for an unfiltered
 *              request. Instead the remaining SOQL allowance is checked before the loop
 *              so an over-large batch fails with an actionable message rather than an
 *              uncatchable governor exception. Cost: 1 SOQL for project resolution + 1
 *              per query object (was up to 3 per query object).
 */
public with sharing class QueryAvailableUnitsAction {

    public class UnitQuery {
        @InvocableVariable(label='Project Id') public Id projectId;
        @InvocableVariable(label='Project Name') public String projectName;
        @InvocableVariable(label='Project Code') public String projectCode;
        @InvocableVariable(label='Configuration') public String configuration;
        @InvocableVariable(label='Max Price') public Decimal maxPrice;
        @InvocableVariable(label='Min Price') public Decimal minPrice;
        @InvocableVariable(label='Facing') public String facing;
        @InvocableVariable(label='Min Floor') public Integer minFloor;
        @InvocableVariable(label='Corner Only') public Boolean cornerOnly;
        @InvocableVariable(label='Park Facing Only') public Boolean parkFacingOnly;
        @InvocableVariable(label='Max Results') public Integer maxResults;
    }

    public class UnitResult {
        @InvocableVariable public String unitCode;
        @InvocableVariable public String unitId;
        @InvocableVariable public String configuration;
        @InvocableVariable public Decimal basePrice;
        @InvocableVariable public Decimal carpetArea;
        @InvocableVariable public Decimal superBuiltUpArea;
        @InvocableVariable public String facing;
        @InvocableVariable public Boolean cornerUnit;
        @InvocableVariable public Boolean parkFacing;
        @InvocableVariable public Integer floor;
        @InvocableVariable public String projectName;
        @InvocableVariable public String towerName;
    }

    public class QueryResponse {
        @InvocableVariable public List<UnitResult> units;
        @InvocableVariable public Integer count;
    }

    /**
     * @description Runs one unit search per query object.
     * @param queries One UnitQuery per search.
     * @return One QueryResponse per query, in the same order as the input.
     */
    @InvocableMethod(label='Query Available Units' description='Search available units by project, configuration, price, facing, floor, and amenity filters.')
    public static List<QueryResponse> queryUnits(List<UnitQuery> queries) {
        List<QueryResponse> results = new List<QueryResponse>();
        if (queries == null || queries.isEmpty()) return results;

        // ---- PASS 1: resolve every project reference in the batch with one query ----
        Map<Integer, Id> resolvedProjectIdByIndex = resolveProjectReferences(queries);

        // ---- PASS 2: one selective, indexed unit search per query object ----
        assertQueryCapacity(queries.size());
        for (Integer i = 0; i < queries.size(); i++) {
            results.add(queryOne(queries[i], resolvedProjectIdByIndex.get(i)));
        }
        return results;
    }

    /**
     * @description Resolves the project reference for every query object in one SOQL.
     *              Preserves the original precedence: explicit Id wins, then a fuzzy
     *              Name match, then an exact Project_Code__c match. Lets Agentforce
     *              agents pass the names/codes they see in conversation without first
     *              resolving them to Ids.
     * @return Map of query-list index → resolved Project Id (absent when unresolved).
     */
    private static Map<Integer, Id> resolveProjectReferences(List<UnitQuery> queries) {
        Map<Integer, Id> byIndex = new Map<Integer, Id>();

        Set<String> names = new Set<String>();
        Set<String> codes = new Set<String>();
        for (UnitQuery q : queries) {
            if (q == null || q.projectId != null) continue;
            if (String.isNotBlank(q.projectName)) names.add(q.projectName);
            // A code is still collected when a name is present: the name match may miss,
            // in which case the original code fell through to the code lookup.
            if (String.isNotBlank(q.projectCode)) codes.add(q.projectCode);
        }

        List<Project__c> candidates = new List<Project__c>();
        if (!names.isEmpty() || !codes.isEmpty()) {
            List<String> clauses = new List<String>();
            Map<String, Object> binds = new Map<String, Object>();
            Integer n = 0;
            for (String nm : names) {
                String key = 'name' + n++;
                binds.put(key, '%' + nm + '%');
                clauses.add('Name LIKE :' + key);
            }
            if (!codes.isEmpty()) {
                binds.put('codes', codes);
                clauses.add('Project_Code__c IN :codes');
            }
            String soql = 'SELECT Id, Name, Project_Code__c FROM Project__c WHERE ' +
                String.join(clauses, ' OR ') + ' ORDER BY Name ASC';
            candidates = (List<Project__c>) Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        }

        for (Integer i = 0; i < queries.size(); i++) {
            UnitQuery q = queries[i];
            if (q == null) continue;

            Id resolved = q.projectId;
            if (resolved == null && String.isNotBlank(q.projectName)) {
                for (Project__c p : candidates) {
                    if (String.isNotBlank(p.Name) && p.Name.containsIgnoreCase(q.projectName)) {
                        resolved = p.Id;
                        break;
                    }
                }
            }
            if (resolved == null && String.isNotBlank(q.projectCode)) {
                for (Project__c p : candidates) {
                    if (q.projectCode.equalsIgnoreCase(p.Project_Code__c)) {
                        resolved = p.Id;
                        break;
                    }
                }
            }
            if (resolved != null) byIndex.put(i, resolved);
        }
        return byIndex;
    }

    /**
     * @description Fails fast with an actionable message when the batch is larger than
     *              the transaction's remaining SOQL allowance, instead of letting an
     *              uncatchable `System.LimitException` surface mid-loop.
     */
    private static void assertQueryCapacity(Integer itemCount) {
        Integer remaining = Limits.getLimitQueries() - Limits.getQueries();
        if (itemCount > remaining) {
            throw new AuraHandledException(
                'Too many unit searches in one invocation: ' + itemCount + ' requested but only ' +
                remaining + ' SOQL queries remain in this transaction. Split the request into smaller batches.'
            );
        }
    }

    private static QueryResponse queryOne(UnitQuery q, Id resolvedProjectId) {
        QueryResponse resp = new QueryResponse();
        resp.units = new List<UnitResult>();
        if (q == null) {
            resp.count = 0;
            return resp;
        }

        Integer lim = (q.maxResults != null && q.maxResults > 0) ? q.maxResults : 10;
        if (lim > 100) lim = 100;

        String soql = 'SELECT Id, Name, Unit_Code__c, Configuration__c, Base_Price__c, ' +
            'Carpet_Area_sqft__c, Super_BuiltUp_Area_sqft__c, BSP_Per_Sqft__c, ' +
            'Facing__c, Corner_Unit__c, Park_Facing__c, Floor__c, ' +
            'Tower__r.Name, Tower__r.Project__r.Name ' +
            'FROM Unit__c WHERE Unit_Status__c = \'Available\'';

        Map<String, Object> binds = new Map<String, Object>();
        if (resolvedProjectId != null) { soql += ' AND Tower__r.Project__c = :projectId';     binds.put('projectId', resolvedProjectId); }
        if (q.configuration != null) { soql += ' AND Configuration__c = :configuration';    binds.put('configuration', q.configuration); }
        if (q.maxPrice != null)      { soql += ' AND Base_Price__c <= :maxPrice';           binds.put('maxPrice', q.maxPrice); }
        if (q.minPrice != null)      { soql += ' AND Base_Price__c >= :minPrice';           binds.put('minPrice', q.minPrice); }
        if (q.facing != null)        { soql += ' AND Facing__c = :facing';                  binds.put('facing', q.facing); }
        if (q.minFloor != null)      { soql += ' AND Floor__c >= :minFloor';                binds.put('minFloor', q.minFloor); }
        if (q.cornerOnly == true)      soql += ' AND Corner_Unit__c = true';
        if (q.parkFacingOnly == true)  soql += ' AND Park_Facing__c = true';

        soql += ' ORDER BY Base_Price__c ASC LIMIT ' + lim;

        List<Unit__c> units = (List<Unit__c>) Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        for (Unit__c u : units) {
            UnitResult r = new UnitResult();
            r.unitId = u.Id;
            r.unitCode = u.Unit_Code__c;
            r.configuration = u.Configuration__c;
            r.basePrice = u.Base_Price__c;
            r.carpetArea = u.Carpet_Area_sqft__c;
            r.superBuiltUpArea = u.Super_BuiltUp_Area_sqft__c;
            r.facing = u.Facing__c;
            r.cornerUnit = u.Corner_Unit__c;
            r.parkFacing = u.Park_Facing__c;
            r.floor = (u.Floor__c == null) ? null : u.Floor__c.intValue();
            r.projectName = (u.Tower__r != null && u.Tower__r.Project__r != null) ? u.Tower__r.Project__r.Name : null;
            r.towerName = (u.Tower__r != null) ? u.Tower__r.Name : null;
            resp.units.add(r);
        }
        resp.count = resp.units.size();
        return resp;
    }
}
