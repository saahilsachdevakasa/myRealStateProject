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

    public static Account createAccount(Map<String, Object> overrides) {
        Id buyerRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Buyer').getRecordTypeId();
        Account a = new Account(
            Name = 'Test Buyer',
            RecordTypeId = buyerRtId,
            Phone = '9820000001'
        );
        applyOverrides(a, overrides);
        insert a;
        return a;
    }

    public static Opportunity createOpportunity(Id accountId, Map<String, Object> overrides) {
        Opportunity o = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'New',
            CloseDate = Date.today().addDays(90),
            AccountId = accountId
        );
        applyOverrides(o, overrides);
        insert o;
        return o;
    }

    public static Payment_Plan__c createPaymentPlan(Map<String, Object> overrides) {
        Payment_Plan__c p = new Payment_Plan__c(
            Name = 'Test Plan',
            Plan_Code__c = 'TST',
            Active__c = false,
            Applicable_Project_Types__c = 'Residential'
        );
        applyOverrides(p, overrides);
        insert p;
        return p;
    }

    public static Payment_Plan_Milestone__c createPaymentPlanMilestone(Id planId, Map<String, Object> overrides) {
        Payment_Plan_Milestone__c m = new Payment_Plan_Milestone__c(
            Payment_Plan__c = planId,
            Sequence__c = 1,
            Trigger__c = 'On Booking',
            Trigger_Type__c = 'Booking',
            Percentage__c = 100,
            Active__c = true,
            Days_From_Trigger__c = 0
        );
        applyOverrides(m, overrides);
        insert m;
        return m;
    }

    public static Payment_Plan__c createPaymentPlanWithMilestones(Integer milestoneCount, Map<String, Object> planOverrides) {
        Payment_Plan__c plan = createPaymentPlan(planOverrides);
        Decimal eachPct = (100.0 / milestoneCount).setScale(2);
        Decimal lastPct = 100 - (eachPct * (milestoneCount - 1));
        List<Payment_Plan_Milestone__c> ms = new List<Payment_Plan_Milestone__c>();
        for (Integer i = 1; i <= milestoneCount; i++) {
            ms.add(new Payment_Plan_Milestone__c(
                Payment_Plan__c = plan.Id,
                Sequence__c = i,
                Trigger__c = 'Milestone ' + i,
                Trigger_Type__c = 'Time-Based',
                Days_From_Trigger__c = (i - 1) * 30,
                Percentage__c = (i == milestoneCount) ? lastPct : eachPct,
                Active__c = true
            ));
        }
        insert ms;
        return plan;
    }

    public static Demand__c createDemand(Id bookingId, Id scheduleId, Map<String, Object> overrides) {
        Demand__c d = new Demand__c(
            Booking__c = bookingId,
            Payment_Schedule__c = scheduleId,
            Demand_Seq__c = 1,
            Raised_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(15),
            Principal_Amount__c = 100000,
            GST_Amount__c = 5000,
            TDS_Amount__c = 1000,
            Status__c = 'Raised',
            PDF_Generated__c = false
        );
        applyOverrides(d, overrides);
        insert d;
        return d;
    }

    public static Receipt__c createReceipt(Id bookingId, Map<String, Object> overrides) {
        Receipt__c r = new Receipt__c(
            Booking__c = bookingId,
            Receipt_Date__c = Date.today(),
            Amount__c = 100000,
            Payment_Mode__c = 'NEFT',
            Status__c = 'Received',
            Payer_Name__c = 'Test Payer'
        );
        applyOverrides(r, overrides);
        insert r;
        return r;
    }

    public static Receipt_Allocation__c createReceiptAllocation(Id receiptId, Id demandId, Map<String, Object> overrides) {
        Receipt_Allocation__c a = new Receipt_Allocation__c(
            Receipt__c = receiptId,
            Demand__c = demandId,
            Amount_Allocated__c = 100000,
            Allocation_Type__c = (demandId == null) ? 'Advance' : 'Towards Demand'
        );
        applyOverrides(a, overrides);
        insert a;
        return a;
    }

    public static Booking__c createBooking(Id oppId, Id unitId, Id accountId, Map<String, Object> overrides) {
        Unit__c u = [SELECT Tower__r.Project__r.Project_Code__c FROM Unit__c WHERE Id = :unitId LIMIT 1];
        String projCode = u.Tower__r.Project__r.Project_Code__c;
        String yearStr = String.valueOf(Date.today().year()).right(2);
        String computedName = 'BKG-' + projCode + '-' + yearStr + '-0001';

        Booking__c b = new Booking__c(
            Name = computedName,
            Booking_Status__c = 'Confirmed',
            Booking_Date__c = Date.today(),
            Opportunity__c = oppId,
            Unit__c = unitId,
            Primary_Buyer__c = accountId
        );
        applyOverrides(b, overrides);
        insert b;
        return b;
    }

    public static Agreement__c createAgreement(Id bookingId, Map<String, Object> overrides) {
        Agreement__c a = new Agreement__c(
            Booking__c = bookingId,
            Status__c = 'Not Started'
        );
        applyOverrides(a, overrides);
        insert a;
        return a;
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
