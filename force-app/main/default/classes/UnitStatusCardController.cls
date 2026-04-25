public with sharing class UnitStatusCardController {

    @AuraEnabled(cacheable=true)
    public static UnitCardData getUnitData(Id unitId) {
        if (unitId == null) return null;

        List<Unit__c> units = [
            SELECT Id, Name, Unit_Code__c, Unit_Status__c, Configuration__c, Facing__c,
                   Corner_Unit__c, Park_Facing__c,
                   Carpet_Area_sqft__c, BuiltUp_Area_sqft__c, Super_BuiltUp_Area_sqft__c,
                   BSP_Per_Sqft__c, Base_Price__c,
                   Blocked_By__c, Blocked_By__r.Name, Blocked_Until__c,
                   Active_Booking__c, Active_Booking__r.Name,
                   Tower__c, Tower__r.Name, Tower__r.Project__c, Tower__r.Project__r.Name
            FROM Unit__c
            WHERE Id = :unitId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (units.isEmpty()) return null;
        Unit__c u = units[0];

        UnitCardData d = new UnitCardData();
        d.unitId = u.Id;
        d.unitCode = (u.Unit_Code__c != null) ? u.Unit_Code__c : u.Name;
        d.status = u.Unit_Status__c;
        d.configuration = u.Configuration__c;
        d.facing = u.Facing__c;
        d.cornerUnit = u.Corner_Unit__c == true;
        d.parkFacing = u.Park_Facing__c == true;
        d.carpetArea = u.Carpet_Area_sqft__c;
        d.builtUpArea = u.BuiltUp_Area_sqft__c;
        d.superBuiltUpArea = u.Super_BuiltUp_Area_sqft__c;
        d.bspPerSqft = u.BSP_Per_Sqft__c;
        d.basePrice = u.Base_Price__c;
        if (u.Blocked_By__c != null) {
            d.blockedById = u.Blocked_By__c;
            d.blockedByName = u.Blocked_By__r.Name;
        }
        d.blockedUntil = u.Blocked_Until__c;
        if (u.Active_Booking__c != null) {
            d.activeBookingId = u.Active_Booking__c;
            d.activeBookingName = u.Active_Booking__r.Name;
        }
        if (u.Tower__c != null) {
            d.towerName = u.Tower__r.Name;
            if (u.Tower__r.Project__c != null) {
                d.projectName = u.Tower__r.Project__r.Name;
            }
        }
        return d;
    }

    public class UnitCardData {
        @AuraEnabled public Id unitId;
        @AuraEnabled public String unitCode;
        @AuraEnabled public String status;
        @AuraEnabled public String configuration;
        @AuraEnabled public String facing;
        @AuraEnabled public Boolean cornerUnit;
        @AuraEnabled public Boolean parkFacing;
        @AuraEnabled public Decimal carpetArea;
        @AuraEnabled public Decimal builtUpArea;
        @AuraEnabled public Decimal superBuiltUpArea;
        @AuraEnabled public Decimal bspPerSqft;
        @AuraEnabled public Decimal basePrice;
        @AuraEnabled public Id blockedById;
        @AuraEnabled public String blockedByName;
        @AuraEnabled public DateTime blockedUntil;
        @AuraEnabled public Id activeBookingId;
        @AuraEnabled public String activeBookingName;
        @AuraEnabled public String projectName;
        @AuraEnabled public String towerName;
    }
}
