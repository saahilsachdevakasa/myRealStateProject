public with sharing class CommissionPayoutBatch implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Booking__c, Channel_Partner__c,
                   Gross_Commission__c, GST_On_Commission__c, TDS_On_Commission__c,
                   Status__c
            FROM Commission_Ledger__c
            WHERE Status__c IN ('Accrued', 'Approved')
              AND Payout__c = null
            WITH SECURITY_ENFORCED
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Commission_Ledger__c> scope) {
        Map<Id, List<Commission_Ledger__c>> entriesByCp = new Map<Id, List<Commission_Ledger__c>>();
        for (Commission_Ledger__c c : scope) {
            if (!entriesByCp.containsKey(c.Channel_Partner__c)) {
                entriesByCp.put(c.Channel_Partner__c, new List<Commission_Ledger__c>());
            }
            entriesByCp.get(c.Channel_Partner__c).add(c);
        }
        if (entriesByCp.isEmpty()) return;

        String month = String.valueOf(Date.today().year()) + '-'
            + String.valueOf(Date.today().month()).leftPad(2, '0');

        Map<Id, Commission_Payout__c> payoutByCp = new Map<Id, Commission_Payout__c>();
        for (Id cpId : entriesByCp.keySet()) {
            List<Commission_Ledger__c> entries = entriesByCp.get(cpId);
            Decimal grossSum = 0, gstSum = 0, tdsSum = 0;
            for (Commission_Ledger__c c : entries) {
                grossSum += (c.Gross_Commission__c == null) ? 0 : c.Gross_Commission__c;
                gstSum += (c.GST_On_Commission__c == null) ? 0 : c.GST_On_Commission__c;
                tdsSum += (c.TDS_On_Commission__c == null) ? 0 : c.TDS_On_Commission__c;
            }
            payoutByCp.put(cpId, new Commission_Payout__c(
                Channel_Partner__c = cpId,
                Payout_Month__c = month,
                Status__c = 'Draft',
                Entry_Count__c = entries.size(),
                Gross_Commission__c = grossSum,
                GST_Total__c = gstSum,
                TDS_Total__c = tdsSum
            ));
        }
        insert payoutByCp.values();

        List<Commission_Ledger__c> ledgersToUpdate = new List<Commission_Ledger__c>();
        for (Commission_Ledger__c c : scope) {
            Commission_Payout__c p = payoutByCp.get(c.Channel_Partner__c);
            if (p != null) {
                ledgersToUpdate.add(new Commission_Ledger__c(Id = c.Id, Payout__c = p.Id));
            }
        }
        if (!ledgersToUpdate.isEmpty()) update ledgersToUpdate;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'CommissionPayoutBatch complete: jobId=' + bc.getJobId());
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CommissionPayoutBatch(), 200);
    }
}
