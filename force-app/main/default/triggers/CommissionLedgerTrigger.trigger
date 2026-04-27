trigger CommissionLedgerTrigger on Commission_Ledger__c (before insert) {
    new CommissionLedgerTriggerHandler().run(
        Trigger.operationType,
        Trigger.new
    );
}
