public class TestDataFactory {

    public static Project__c createProject(Map<String, Object> overrides) {
        Project__c p = new Project__c(
            Name = 'Test Project',
            Project_Code__c = 'TST',
            Project_Type__c = 'Residential',
            Active_for_Bookings__c = true
        );
        applyOverrides(p, overrides);
        insert p;
        return p;
    }

    public static Tower__c createTower(Id projectId, Map<String, Object> overrides) {
        Project__c parent = [SELECT Project_Code__c FROM Project__c WHERE Id = :projectId LIMIT 1];

        String towerType = 'Residential Tower';
        Integer towerNumber = 1;
        if (overrides != null) {
            if (overrides.containsKey('Tower_Type__c')) towerType = (String) overrides.get('Tower_Type__c');
            if (overrides.containsKey('Tower_Number__c')) towerNumber = toInt(overrides.get('Tower_Number__c'));
        }
        String typeLetter = (towerType == 'Commercial Block') ? 'B' : 'T';
        String computedName = parent.Project_Code__c + '-' + typeLetter + String.valueOf(towerNumber).leftPad(2, '0');

        Tower__c t = new Tower__c(
            Name = computedName,
            Project__c = projectId,
            Tower_Number__c = towerNumber,
            Tower_Type__c = towerType,
            Total_Floors__c = 4,
            Units_Per_Floor__c = 4
        );
        applyOverrides(t, overrides);
        insert t;
        return t;
    }

    public static Unit__c createUnit(Id towerId, Map<String, Object> overrides) {
        Tower__c parent = [SELECT Name FROM Tower__c WHERE Id = :towerId LIMIT 1];

        Integer floor = 1;
        Integer unitNumber = 1;
        if (overrides != null) {
            if (overrides.containsKey('Floor__c')) floor = toInt(overrides.get('Floor__c'));
            if (overrides.containsKey('Unit_Number__c')) unitNumber = toInt(overrides.get('Unit_Number__c'));
        }
        String computedName = parent.Name
            + '-F' + String.valueOf(floor).leftPad(2, '0')
            + '-U' + String.valueOf(unitNumber).leftPad(3, '0');

        Unit__c u = new Unit__c(
            Name = computedName,
            Tower__c = towerId,
            Floor__c = floor,
            Unit_Number__c = unitNumber,
            Unit_Status__c = 'Available',
            Unit_Type_Class__c = 'Residential',
            Configuration__c = '3BHK',
            Carpet_Area_sqft__c = 1000,
            BuiltUp_Area_sqft__c = 1200,
            Super_BuiltUp_Area_sqft__c = 1500,
            BSP_Per_Sqft__c = 10000
        );
        applyOverrides(u, overrides);
        insert u;
        return u;
    }

    public static List<Unit__c> createUnits(Id towerId, Integer count, Map<String, Object> overrides) {
        Tower__c parent = [SELECT Name FROM Tower__c WHERE Id = :towerId LIMIT 1];

        Integer floor = 1;
        if (overrides != null && overrides.containsKey('Floor__c')) {
            floor = toInt(overrides.get('Floor__c'));
        }
        String floorStr = String.valueOf(floor).leftPad(2, '0');

        List<Unit__c> units = new List<Unit__c>();
        for (Integer i = 1; i <= count; i++) {
            String computedName = parent.Name + '-F' + floorStr + '-U' + String.valueOf(i).leftPad(3, '0');
            Unit__c u = new Unit__c(
                Name = computedName,
                Tower__c = towerId,
                Floor__c = floor,
                Unit_Number__c = i,
                Unit_Status__c = 'Available',
                Unit_Type_Class__c = 'Residential',
                Configuration__c = '3BHK',
                Carpet_Area_sqft__c = 1000,
                BuiltUp_Area_sqft__c = 1200,
                Super_BuiltUp_Area_sqft__c = 1500,
                BSP_Per_Sqft__c = 10000
            );
            applyOverrides(u, overrides);
            units.add(u);
        }
        insert units;
        return units;
    }

    public static User createUser(String profileName, Map<String, Object> overrides) {
        Profile prof = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        String unique = String.valueOf(System.currentTimeMillis());
        User u = new User(
            ProfileId = prof.Id,
            LastName = 'Test',
            Email = 'test_' + unique + '@recrm-demo.invalid',
            Username = 'test_' + unique + '@recrm-demo.invalid',
            Alias = 'tst' + unique.right(5),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        applyOverrides(u, overrides);
        insert u;
        return u;
    }

    private static void applyOverrides(SObject record, Map<String, Object> overrides) {
        if (overrides == null) return;
        for (String fieldName : overrides.keySet()) {
            record.put(fieldName, overrides.get(fieldName));
        }
    }

    private static Integer toInt(Object o) {
        if (o == null) return 0;
        if (o instanceof Integer) return (Integer) o;
        return Integer.valueOf(String.valueOf(o));
    }
}
