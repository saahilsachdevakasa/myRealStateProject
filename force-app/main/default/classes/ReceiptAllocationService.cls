public with sharing class ReceiptAllocationService {

    public class AllocationRequest {
        @InvocableVariable(required=true label='Receipt Id')
        public Id receiptId;
        @InvocableVariable(required=false label='Demand Id (null for Advance)')
        public Id demandId;
        @InvocableVariable(required=true label='Amount')
        public Decimal amount;
        @InvocableVariable(required=false label='Allocation Type (Towards Demand | Advance | Adjustment)')
        public String allocationType;
    }

    @InvocableMethod(label='Allocate Receipt to Demand' description='Creates Receipt_Allocation records and updates Demand and Receipt status based on allocated amounts.')
    public static List<Id> allocateReceipts(List<AllocationRequest> requests) {
        if (requests == null || requests.isEmpty()) return new List<Id>();

        Set<Id> receiptIds = new Set<Id>();
        Set<Id> demandIds = new Set<Id>();
        for (AllocationRequest r : requests) {
            if (r.receiptId == null) {
                throw new AuraHandledException('Receipt Id is required on every allocation request.');
            }
            if (r.amount == null || r.amount <= 0) {
                throw new AuraHandledException('Allocation amount must be greater than zero.');
            }
            receiptIds.add(r.receiptId);
            if (r.demandId != null) demandIds.add(r.demandId);
        }

        Map<Id, Receipt__c> receiptsById = new Map<Id, Receipt__c>([
            SELECT Id, Amount__c, Status__c, Booking__c
            FROM Receipt__c
            WHERE Id IN :receiptIds
            WITH SECURITY_ENFORCED
        ]);
        Map<Id, Demand__c> demandsById = new Map<Id, Demand__c>();
        if (!demandIds.isEmpty()) {
            demandsById = new Map<Id, Demand__c>([
                SELECT Id, Net_Payable__c, Amount_Received__c, Status__c, Booking__c
                FROM Demand__c
                WHERE Id IN :demandIds
                WITH SECURITY_ENFORCED
            ]);
        }

        Map<Id, Decimal> existingAllocatedByReceipt = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Receipt__c rid, SUM(Amount_Allocated__c) total
            FROM Receipt_Allocation__c
            WHERE Receipt__c IN :receiptIds
            GROUP BY Receipt__c
        ]) {
            existingAllocatedByReceipt.put((Id) ar.get('rid'), (Decimal) ar.get('total'));
        }

        Map<Id, Decimal> pendingByReceipt = new Map<Id, Decimal>();
        Map<Id, Decimal> pendingByDemand = new Map<Id, Decimal>();

        List<Receipt_Allocation__c> newAllocations = new List<Receipt_Allocation__c>();
        for (AllocationRequest r : requests) {
            Receipt__c rec = receiptsById.get(r.receiptId);
            if (rec == null) {
                throw new AuraHandledException('Receipt not found: ' + r.receiptId);
            }
            if (rec.Status__c != 'Received' && rec.Status__c != 'Under Reconciliation') {
                throw new AuraHandledException(
                    'Cannot allocate Receipt in status ' + rec.Status__c + '. Allowed: Received, Under Reconciliation.'
                );
            }

            Decimal existingForReceipt = existingAllocatedByReceipt.containsKey(r.receiptId)
                ? existingAllocatedByReceipt.get(r.receiptId) : 0;
            Decimal pendingForReceipt = pendingByReceipt.containsKey(r.receiptId)
                ? pendingByReceipt.get(r.receiptId) : 0;
            Decimal availableOnReceipt = rec.Amount__c - existingForReceipt - pendingForReceipt;
            if (r.amount > availableOnReceipt) {
                throw new AuraHandledException(
                    'Allocation amount ' + r.amount + ' exceeds Receipt unallocated balance ' + availableOnReceipt + '.'
                );
            }
            pendingByReceipt.put(r.receiptId, pendingForReceipt + r.amount);

            String type = (r.allocationType == null || r.allocationType == '') ? 'Towards Demand' : r.allocationType;

            if (r.demandId != null) {
                Demand__c d = demandsById.get(r.demandId);
                if (d == null) {
                    throw new AuraHandledException('Demand not found: ' + r.demandId);
                }
                if (d.Status__c == 'Cancelled') {
                    throw new AuraHandledException('Cannot allocate to a Cancelled Demand: ' + r.demandId);
                }
                Decimal netPayable = (d.Net_Payable__c == null) ? 0 : d.Net_Payable__c;
                Decimal received = (d.Amount_Received__c == null) ? 0 : d.Amount_Received__c;
                Decimal pendingForDemand = pendingByDemand.containsKey(r.demandId)
                    ? pendingByDemand.get(r.demandId) : 0;
                Decimal demandOutstanding = netPayable - received - pendingForDemand;
                if (r.amount > demandOutstanding) {
                    throw new AuraHandledException(
                        'Allocation amount ' + r.amount + ' exceeds Demand outstanding ' + demandOutstanding + '.'
                    );
                }
                pendingByDemand.put(r.demandId, pendingForDemand + r.amount);
            } else if (type == 'Towards Demand') {
                throw new AuraHandledException('Allocation Type "Towards Demand" requires a Demand Id.');
            }

            newAllocations.add(new Receipt_Allocation__c(
                Receipt__c = r.receiptId,
                Demand__c = r.demandId,
                Amount_Allocated__c = r.amount,
                Allocation_Type__c = type
            ));
        }

        insert newAllocations;

        if (!demandIds.isEmpty()) {
            Map<Id, Decimal> totalByDemand = new Map<Id, Decimal>();
            for (AggregateResult ar : [
                SELECT Demand__c did, SUM(Amount_Allocated__c) total
                FROM Receipt_Allocation__c
                WHERE Demand__c IN :demandIds
                GROUP BY Demand__c
            ]) {
                totalByDemand.put((Id) ar.get('did'), (Decimal) ar.get('total'));
            }

            List<Demand__c> demandsToUpdate = new List<Demand__c>();
            for (Id did : demandIds) {
                Demand__c d = demandsById.get(did);
                Decimal newReceived = totalByDemand.containsKey(did) ? totalByDemand.get(did) : 0;
                Decimal netPayable = (d.Net_Payable__c == null) ? 0 : d.Net_Payable__c;
                String newStatus;
                if (newReceived >= netPayable && netPayable > 0) {
                    newStatus = 'Paid';
                } else if (newReceived > 0) {
                    newStatus = 'Partial';
                } else {
                    newStatus = 'Raised';
                }
                demandsToUpdate.add(new Demand__c(
                    Id = did,
                    Amount_Received__c = newReceived,
                    Status__c = newStatus
                ));
            }
            update demandsToUpdate;
        }

        Map<Id, Decimal> totalAllocByReceipt = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Receipt__c rid, SUM(Amount_Allocated__c) total
            FROM Receipt_Allocation__c
            WHERE Receipt__c IN :receiptIds
            GROUP BY Receipt__c
        ]) {
            totalAllocByReceipt.put((Id) ar.get('rid'), (Decimal) ar.get('total'));
        }

        List<Receipt__c> receiptsToUpdate = new List<Receipt__c>();
        Id currentUserId = UserInfo.getUserId();
        for (Id rid : receiptIds) {
            Receipt__c rec = receiptsById.get(rid);
            Decimal totalAlloc = totalAllocByReceipt.containsKey(rid) ? totalAllocByReceipt.get(rid) : 0;
            String newStatus;
            if (totalAlloc >= rec.Amount__c) {
                newStatus = 'Reconciled';
            } else if (totalAlloc > 0) {
                newStatus = 'Under Reconciliation';
            } else {
                newStatus = rec.Status__c;
            }
            if (newStatus != rec.Status__c) {
                Receipt__c updated = new Receipt__c(Id = rid, Status__c = newStatus);
                if (newStatus == 'Reconciled') {
                    updated.Reconciled_By__c = currentUserId;
                }
                receiptsToUpdate.add(updated);
            }
        }
        if (!receiptsToUpdate.isEmpty()) {
            update receiptsToUpdate;
        }

        List<Id> allocationIds = new List<Id>();
        for (Receipt_Allocation__c a : newAllocations) allocationIds.add(a.Id);
        return allocationIds;
    }
}
