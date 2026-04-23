public class UnitLifecycleService {

    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        'Available' => new Set<String>{ 'Blocked' },
        'Blocked'   => new Set<String>{ 'Available', 'Booked' },
        'Booked'    => new Set<String>{ 'Cancelled' },
        'Cancelled' => new Set<String>{ 'Available' }
    };

    private static final String ALLOWED_SUMMARY =
        'Available→Blocked; Blocked→Available/Booked; Booked→Cancelled; Cancelled→Available';

    public static void onBeforeUpdate(List<Unit__c> newUnits, Map<Id, Unit__c> oldMap) {
        Datetime nowTs = Datetime.now();
        String userId = UserInfo.getUserId();
        String timestamp = nowTs.format('yyyy-MM-dd HH:mm');

        for (Unit__c u : newUnits) {
            Unit__c oldU = oldMap.get(u.Id);
            String oldStatus = oldU.Unit_Status__c;
            String newStatus = u.Unit_Status__c;

            if (oldStatus == newStatus) continue;

            Set<String> allowedTargets = ALLOWED_TRANSITIONS.get(oldStatus);
            if (allowedTargets == null || !allowedTargets.contains(newStatus)) {
                u.addError(
                    'Invalid status transition: ' + oldStatus + ' → ' + newStatus +
                    '. Allowed: ' + ALLOWED_SUMMARY
                );
                continue;
            }

            String newLine = timestamp + ' | ' + userId + ' | ' + oldStatus + ' → ' + newStatus;
            String existing = u.Status_History__c;
            u.Status_History__c = String.isBlank(existing) ? newLine : existing + '\n' + newLine;

            u.Last_Status_Change__c = nowTs;

            if (newStatus == 'Available') {
                u.Blocked_By__c = null;
                u.Blocked_Until__c = null;
                u.Active_Booking__c = null;
            }
        }
    }
}
