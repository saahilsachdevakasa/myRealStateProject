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

    @InvocableMethod(label='Query Available Units' description='Search available units by project, configuration, price, facing, floor, and amenity filters.')
    public static List<QueryResponse> queryUnits(List<UnitQuery> queries) {
        List<QueryResponse> results = new List<QueryResponse>();
        for (UnitQuery q : queries) {
            results.add(queryOne(q));
        }
        return results;
    }

    private static QueryResponse queryOne(UnitQuery q) {
        QueryResponse resp = new QueryResponse();
        resp.units = new List<UnitResult>();

        Integer lim = (q.maxResults != null && q.maxResults > 0) ? q.maxResults : 10;
        if (lim > 100) lim = 100;

        // Resolve a project reference: prefer the Id, fall back to a Name LIKE match,
        // then to an exact Project_Code__c match. Lets Agentforce agents pass the
        // names/codes they see in conversation without first resolving them to Ids.
        Id resolvedProjectId = q.projectId;
        if (resolvedProjectId == null && String.isNotBlank(q.projectName)) {
            String pattern = '%' + q.projectName + '%';
            List<Project__c> projects = [
                SELECT Id FROM Project__c
                WHERE Name LIKE :pattern
                WITH SECURITY_ENFORCED LIMIT 1
            ];
            if (!projects.isEmpty()) resolvedProjectId = projects[0].Id;
        }
        if (resolvedProjectId == null && String.isNotBlank(q.projectCode)) {
            List<Project__c> projects = [
                SELECT Id FROM Project__c
                WHERE Project_Code__c = :q.projectCode
                WITH SECURITY_ENFORCED LIMIT 1
            ];
            if (!projects.isEmpty()) resolvedProjectId = projects[0].Id;
        }

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