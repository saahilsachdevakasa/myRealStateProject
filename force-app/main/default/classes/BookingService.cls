public with sharing class BookingService {

    private static final String POST_SALES_QUEUE_DEV_NAME = 'Post_Sales_Queue';
    private static final String CLOSED_WON_STAGE = 'Closed Won (Booked)';

    public static void onOpportunityClosedWon(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        Set<Id> qualifyingIds = new Set<Id>();
        for (Opportunity o : newList) {
            Opportunity oldO = oldMap.get(o.Id);
            if (o.StageName != oldO.StageName
                && o.StageName == CLOSED_WON_STAGE
                && o.Booking__c == null) {
                qualifyingIds.add(o.Id);
            }
        }
        if (qualifyingIds.isEmpty()) return;

        List<Opportunity> opps = [
            SELECT Id, AccountId, Primary_Unit__c, Project__c,
                   Source_Channel__c, Source_CP__c, OwnerId, Quoted_Gross_Value__c
            FROM Opportunity
            WHERE Id IN :qualifyingIds
            WITH SECURITY_ENFORCED
        ];

        Set<Id> unitIds = new Set<Id>();
        Set<Id> projectIds = new Set<Id>();
        for (Opportunity o : opps) {
            if (o.Primary_Unit__c != null) unitIds.add(o.Primary_Unit__c);
            if (o.Project__c != null) projectIds.add(o.Project__c);
        }

        Map<Id, Unit__c> unitsById = new Map<Id, Unit__c>([
            SELECT Id, Unit_Status__c, BSP_Per_Sqft__c
            FROM Unit__c
            WHERE Id IN :unitIds
            WITH SECURITY_ENFORCED
        ]);

        Map<Id, Project__c> projectsById = new Map<Id, Project__c>([
            SELECT Id, Project_Code__c
            FROM Project__c
            WHERE Id IN :projectIds
            WITH SECURITY_ENFORCED
        ]);

        Integer currentYear = Date.today().year();
        String yearStr = String.valueOf(currentYear).right(2);

        Map<Id, Integer> bookingCountByProject = new Map<Id, Integer>();
        for (Booking__c b : [
            SELECT Id, Unit__r.Tower__r.Project__c
            FROM Booking__c
            WHERE Unit__r.Tower__r.Project__c IN :projectIds
              AND CALENDAR_YEAR(Booking_Date__c) = :currentYear
        ]) {
            Id projId = b.Unit__r.Tower__r.Project__c;
            Integer cnt = bookingCountByProject.containsKey(projId) ? bookingCountByProject.get(projId) : 0;
            bookingCountByProject.put(projId, cnt + 1);
        }

        Group psQueue = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :POST_SALES_QUEUE_DEV_NAME
            LIMIT 1
        ];

        Date today = Date.today();
        List<Booking__c> newBookings = new List<Booking__c>();
        Map<Id, Booking__c> bookingByOppId = new Map<Id, Booking__c>();

        for (Opportunity o : opps) {
            Project__c proj = projectsById.get(o.Project__c);
            Unit__c unit = unitsById.get(o.Primary_Unit__c);

            Integer currentCount = bookingCountByProject.containsKey(o.Project__c)
                ? bookingCountByProject.get(o.Project__c) : 0;
            Integer nextSeq = currentCount + 1;
            String seqStr = String.valueOf(nextSeq).leftPad(4, '0');
            String bookingName = 'BKG-' + proj.Project_Code__c + '-' + yearStr + '-' + seqStr;

            Booking__c b = new Booking__c(
                Name = bookingName,
                Booking_Status__c = 'Confirmed',
                Booking_Date__c = today,
                Opportunity__c = o.Id,
                Unit__c = o.Primary_Unit__c,
                Primary_Buyer__c = o.AccountId,
                Source_Channel__c = o.Source_Channel__c,
                Source_CP__c = o.Source_CP__c,
                RM_At_Booking__c = o.OwnerId,
                BSP_at_Booking__c = unit != null ? unit.BSP_Per_Sqft__c : null,
                Quoted_Gross_Value__c = o.Quoted_Gross_Value__c,
                OwnerId = psQueue.Id
            );
            newBookings.add(b);
            bookingByOppId.put(o.Id, b);

            bookingCountByProject.put(o.Project__c, nextSeq);
        }

        insert newBookings;

        List<Unit__c> unitsToUpdate = new List<Unit__c>();
        for (Opportunity o : opps) {
            unitsToUpdate.add(new Unit__c(
                Id = o.Primary_Unit__c,
                Unit_Status__c = 'Booked',
                Active_Booking__c = bookingByOppId.get(o.Id).Id
            ));
        }
        update unitsToUpdate;

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        for (Opportunity o : opps) {
            oppsToUpdate.add(new Opportunity(
                Id = o.Id,
                Booking__c = bookingByOppId.get(o.Id).Id
            ));
        }
        update oppsToUpdate;
    }
}
