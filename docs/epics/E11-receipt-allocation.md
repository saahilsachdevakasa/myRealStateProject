# E11 — Receipt Allocation and Reconciliation

## Objective

Capture buyer payments (Receipt) and allocate them against raised Demand records, with automatic Demand status transitions (Raised → Partial → Paid) and Receipt status transitions (Received → Under Reconciliation → Reconciled). Supports advance payments (allocations not tied to a Demand).

## Dependencies

- E10 — Demand records exist with `Net_Payable__c`, `Amount_Received__c`, `Status__c='Raised'`.
- E08 — Booking records exist as the parent of Receipts.
- E03 (objects) — `Receipt__c`, `Receipt_Allocation__c` already deployed with their fields.

## In-scope artefacts

1. **`ReceiptAllocationService.cls`** — invocable Apex service that creates `Receipt_Allocation__c` records and updates Demand and Receipt status atomically.
2. **`ReceiptAllocationServiceTest.cls`** — 8 test methods covering happy path, partial payment, multi-allocation, validation failures, bulk operation, and advance payment.
3. **`TestDataFactory.cls`** — extended with `createReceipt(bookingId, overrides)` and `createReceiptAllocation(receiptId, demandId, overrides)`.

NOT in E11:
- Receipt PDF generation (Phase 2)
- Bank reconciliation against statement files (Phase 2)
- Payment gateway integration (Phase 2)
- Receipt-side trigger / naming (Receipt.Name is AutoNumber `RCT-{YY}-{00000}`; status transitions handled by the allocation service)
- Manual deallocation flows
- Overdue auto-status (cron job — separate epic)

## Locked design decisions

**D1. Architecture — single service class, no triggers needed.**
Receipt records are created directly by users (manual data entry of payments received). Receipt naming is AutoNumber. No Receipt trigger exists or is needed for E11. The `ReceiptAllocationService.allocateReceipts` invocable is the single integration surface.

**D2. `AllocationRequest` shape:**
```apex
public class AllocationRequest {
    @InvocableVariable(required=true)  public Id receiptId;
    @InvocableVariable(required=false) public Id demandId;       // null = Advance
    @InvocableVariable(required=true)  public Decimal amount;
    @InvocableVariable(required=false) public String allocationType; // defaults 'Towards Demand'
}
```
Returns `List<Id>` of created `Receipt_Allocation__c` Ids.

**D3. Demand.Amount_Received__c is a Currency field — service must manually aggregate.**
Discovery confirmed it is NOT a roll-up. Service uses `AggregateResult` on `Receipt_Allocation__c` grouped by `Demand__c` after insert, then bulk-updates Demand records.

**D4. Receipt.Amount_Allocated__c IS a roll-up — service does NOT update it directly.**
But because Salesforce roll-ups may not reflect just-inserted children within the same transaction, the service computes the allocated total via fresh `AggregateResult` on `Receipt_Allocation__c` grouped by `Receipt__c`, then determines new Receipt.Status__c from that authoritative number rather than re-reading the rollup field.

**D5. Booking aggregate fields are not touched.**
`Booking.Total_Paid__c` is itself a roll-up of `Receipt.Amount__c` and was already accurate when the Receipt itself was inserted. Allocations don't change Receipt.Amount, so Booking aggregates are stable across allocation operations.

**D6. Demand status state machine:**
- `Amount_Received__c >= Net_Payable__c && Net_Payable__c > 0` → `'Paid'`
- `Amount_Received__c > 0` → `'Partial'`
- `Amount_Received__c = 0` → `'Raised'`
- `'Cancelled'` is terminal — service rejects allocations targeting Cancelled demands.
- `'Overdue'` is set by a separate cron job (out of scope) and treated like `'Raised'` for allocation purposes.

**D7. Receipt status state machine:**
- `total_allocated >= Amount__c` → `'Reconciled'` + set `Reconciled_By__c = current user`.
- `total_allocated > 0` → `'Under Reconciliation'`.
- Service writes to Receipt only when status actually changes (avoids redundant DML).
- `'Reversed'` Receipts cannot be allocated (only `'Received'` and `'Under Reconciliation'` are accepted).

**D8. Validation — fresh aggregates, not stale rollup fields.**
For Receipt balance check, the service computes `available = Receipt.Amount__c - SUM(existing allocations) - SUM(pending in this batch)` rather than using `Receipt.Amount_Allocated__c` (rollup). The pending-batch tracking via `Map<Id,Decimal>` prevents the bug where two requests in one call against the same Receipt/Demand could both pass individually but exceed capacity together. Same pattern applied for Demand outstanding.

**D9. Advance payments — Demand=null, Allocation_Type='Advance'.**
`Receipt_Allocation__c.Demand__c` is a Lookup with `required=false` (discovered), so advance allocations are natively supported. Skip Demand validation/aggregation for advance allocations; still count toward Receipt balance.

## Acceptance criteria

| # | Scenario | Expected |
|---|---|---|
| 1 | Allocate full Demand amount from a Receipt | Demand.Status='Paid', Receipt.Status='Reconciled', Reconciled_By set |
| 2 | Allocate half the Demand amount | Demand.Status='Partial', Outstanding=remaining, Receipt.Status='Reconciled' if fully consumed |
| 3 | Two sequential allocations totaling the Demand | After first: 'Partial'; after second: 'Paid' |
| 4 | Allocation amount exceeds Receipt balance | AuraHandledException, no records created |
| 5 | Allocation amount exceeds Demand outstanding | AuraHandledException, no records created |
| 6 | Allocation against a Cancelled Demand | AuraHandledException |
| 7 | Bulk allocation (3 receipts × 3 demands) | All processed in 1 call, all status transitions correct |
| 8 | Advance payment with null Demand | Allocation created with Type='Advance', Receipt status updates correctly, no Demand touched |

## Iteration story

- Discovery (read-only) revealed `Demand.Amount_Received__c` is Currency (not roll-up) and `Receipt.Amount_Allocated__c` IS a roll-up — drove the asymmetric handling in the service: aggregate-and-update for Demand, aggregate-only for Receipt status.
- Discovery also confirmed `Receipt_Allocation__c.Demand__c` is Lookup with `required=false`, enabling native advance-payment support without a separate object or workaround.
- No validation rules on any of the three objects → gotcha #40 (MD-rollup-VR mid-batch) does not apply, simplifying the service.
- DemandTrigger is `before insert` only → service updates to Demand records in step 4 fire no triggers, no recursion guard needed.
- Generation produced 3 new files + 1 modified (TestDataFactory).
- Dry-run deploy passed clean (3 components).
- Real deploy hit gotcha #31 (CLI v2.84.6 cosmetic "Missing message metadata.transfer:Finalizing" error). Verified actual success via `sf project deploy report --job-id <id>` which showed `status: Succeeded`, 3/3 components.
- All 40 tests passed on first run (8 new + 32 carried from prior epics).
- Coverage: ReceiptAllocationService 90% (102 lines covered, 11 uncovered — defensive validation branches that aren't worth dedicated tests).

## Files produced

```
force-app/main/default/classes/
├── ReceiptAllocationService.cls               (NEW, 192 lines, 90% covered)
├── ReceiptAllocationService.cls-meta.xml      (NEW)
├── ReceiptAllocationServiceTest.cls           (NEW, 8 test methods)
├── ReceiptAllocationServiceTest.cls-meta.xml  (NEW)
└── TestDataFactory.cls                        (MODIFIED — +createReceipt, +createReceiptAllocation)
```

## Test results

```
Tests Ran           40
Outcome             Passed
Pass Rate           100%
Test Run Id         707Hp0000Lledts
Test Total Time     42.7s
```

Coverage of touched/related classes:
- ReceiptAllocationService    90%  (102/113)
- DemandService               96%  (74/77)
- DemandNamingService        100%  (12/12)
- DemandTriggerHandler       100%  (3/3)
- PaymentScheduleService     100%  (43/43)
- BookingService             100%  (73/73)
- UnitBlockingService        100%  (23/23)
- UnitLifecycleService       100%  (28/28)

## Gotchas surfaced

None new. Honoured:
- #30 (TestDataFactory must honour VRs) — Tower/Unit factories already compute derived names; project codes 'HPY', 'PRT', 'MUL', 'XRB', 'XDO', 'CXD', 'BLK', 'ADV' all 3-char alpha (no digits).
- #31 (CLI v2.84.6 deploy reporting bug) — used `sf project deploy report --job-id` to confirm success after the cosmetic error.
- #40 (MD rollup VR mid-batch) — not applicable since no validation rules exist on Receipt, Receipt_Allocation, or Demand.

## Implemented

- [x] ReceiptAllocationService invocable (single `allocateReceipts` method)
- [x] AllocationRequest inner class with 4 fields
- [x] Demand.Amount_Received aggregation and status transitions
- [x] Receipt status transitions (with Reconciled_By set on Reconciled)
- [x] Receipt balance and Demand outstanding validation (with same-batch pending tracking)
- [x] Cancelled Demand rejection
- [x] Advance payment support (null Demand, Allocation_Type='Advance')
- [x] Bulk operation support (multiple requests in one call)
- [x] TestDataFactory.createReceipt, createReceiptAllocation
- [x] 8 test methods, 90% coverage on the service
- [x] Deployed to re-crm-sdo
- [x] All 40 tests pass

## Known follow-ups (next epics)

- **E12** — Demand Letter PDF generation (Visualforce + email/portal delivery).
- **E?** — Overdue cron job: nightly batch flips `Status='Raised'/'Partial'` to `'Overdue'` when `Due_Date__c < TODAY`.
- **E?** — Receipt deallocation Quick Action (currently no UI to remove an allocation; admin can do it via Setup).
- **E?** — Bank statement reconciliation upload + match-to-Receipt.
- **E?** — Buyer-portal "View payments and outstanding" page (LWC over Booking + Demands + Receipts).
- **E23 polish** — Quick Action on Demand to "Allocate Receipt" with Receipt picker + amount inputs, calling `ReceiptAllocationService` via Flow.
