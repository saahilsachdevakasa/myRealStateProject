public with sharing class CpDashboardController {

    public class DashboardData {
        @AuraEnabled public Integer leadCount;
        @AuraEnabled public Integer activeBookings;
        @AuraEnabled public Decimal ytdCommission;
        @AuraEnabled public Decimal pendingPayouts;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        Id cpId = CP_Scope.getCpAccountId();
        DashboardData d = new DashboardData();

        d.leadCount = [
            SELECT COUNT() FROM Lead
            WHERE Source_CP__c = :cpId
            WITH SECURITY_ENFORCED
        ];

        d.activeBookings = [
            SELECT COUNT() FROM Booking__c
            WHERE Source_CP__c = :cpId
              AND Booking_Status__c NOT IN ('Cancelled', 'Possessed')
            WITH SECURITY_ENFORCED
        ];

        Date startOfYear = Date.newInstance(Date.today().year(), 1, 1);
        Decimal ytd = 0;
        for (AggregateResult ar : [
            SELECT SUM(Gross_Commission__c) total
            FROM Commission_Ledger__c
            WHERE Channel_Partner__c = :cpId
              AND Milestone_Date__c >= :startOfYear
            WITH SECURITY_ENFORCED
        ]) {
            Decimal v = (Decimal) ar.get('total');
            ytd = (v == null) ? 0 : v;
        }
        d.ytdCommission = ytd;

        Decimal pending = 0;
        for (AggregateResult ar : [
            SELECT SUM(Net_Payable__c) total
            FROM Commission_Ledger__c
            WHERE Channel_Partner__c = :cpId
              AND Status__c IN ('Accrued', 'Approved')
            WITH SECURITY_ENFORCED
        ]) {
            Decimal v = (Decimal) ar.get('total');
            pending = (v == null) ? 0 : v;
        }
        d.pendingPayouts = pending;

        return d;
    }
}
