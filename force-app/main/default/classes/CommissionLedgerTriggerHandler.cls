public class CommissionLedgerTriggerHandler {

    public void run(TriggerOperation operation, List<Commission_Ledger__c> newList) {
        if (operation == TriggerOperation.BEFORE_INSERT) {
            CommissionLedgerNamingService.onBeforeInsert(newList);
        }
    }
}
