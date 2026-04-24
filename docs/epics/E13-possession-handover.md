# E13 — Possession Handover and Snag Items

## Objective

Final piece of the buyer lifecycle. Create `Possession__c` from a `Booking__c` (after registration), sync Booking status when keys are handed over, and support `Snag_Item__c` capture during the snag-rectification phase via native Salesforce roll-ups (no Apex aggregation needed).

## Dependencies

- E12 — Agreement workflow (`Agreement.Status='Executed'` → `Booking_Status='Registered'`).
- E08 — Booking exists with the lifecycle picklist `Confirmed → Agreement Pending → Agreement Signed → Registered → Possession Ready → Possessed → Cancelled`.
- E03 (objects) — `Possession__c` (15 custom fields incl. native rollups Snag_Count + Open_Snag_Count) and `Snag_Item__c` (9 custom fields, MD to Possession).

## In-scope artefacts

**Apex (5 new + factory addition):**
1. `triggers/PossessionTrigger.trigger` — `before insert, after update`
2. `classes/PossessionTriggerHandler.cls` — routes BEFORE_INSERT → naming, AFTER_UPDATE → service. RecursionGuard('Possession_afterUpdate') wraps the after-update branch.
3. `classes/PossessionNamingService.cls` — bulk-queries Booking names, sets `Name = 'POS-' + Booking.Name` (mirrors AgreementNamingService and DemandNamingService).
4. `classes/PossessionService.cls` — invocable `createPossessions(List<PossessionRequest>)` + `onAfterUpdate` handler. Validates Booking_Status ∈ {Registered, Possession Ready}, rejects duplicates (1:1 Booking↔Possession), creates Possession with Status='Ready to Offer', updates Booking.Booking_Status→'Possession Ready' + sets Booking.Possession__c. After-update maps Possession.Status='Handed Over' → Booking.Booking_Status='Possessed'.
5. `classes/PossessionServiceTest.cls` — 7 tests.
6. `classes/TestDataFactory.cls` — +`createPossession(bookingId, overrides)` and +`createSnagItem(possessionId, overrides)`. The Snag factory honours the two required fields (Description__c, Reported_Date__c).

**NOT in E13:**
- Possession Letter / NOC PDF generation (defer to Phase 2 polish — same VF + ContentVersion pattern as E12 Demand Letter).
- Snag aggregation Apex — native roll-ups handle it.
- Snag assignment workflow / SLA (manual in MVP).
- Cancellation / refund flow on Possessed bookings (Phase 2).

## Locked design decisions

**D1. Booking lookup field: `Booking.Possession__c`** (NOT `Related_Possession__c` as the spec referred). Same pattern as `Booking.Agreement__c` corrected in E12 — actual API name is `Possession__c`, label is "Related Possession", `relationshipName=Originating_Booking`, Lookup, `required=false`, `deleteConstraint=SetNull`.

**D2. Possession naming**: `Name = 'POS-' + Booking.Name`. Example: `BKG-HND-26-0001` → `POS-BKG-HND-26-0001`. Set in before-insert via bulk-queried parent Booking name (Booking__r.Name not loaded in before-insert).

**D3. Booking_Status validation on creation**: only `Registered` and `Possession Ready` allowed. `Confirmed`, `Agreement Pending`, `Agreement Signed` are too early; `Possessed`, `Cancelled` are terminal.

**D4. Possession Status → Booking Status mapping** (after-update only):
- `Handed Over` → Booking.Booking_Status = `Possessed`
- All other Possession statuses (`Ready to Offer`, `Offered`, `Snag Phase`, `Cleared`, `Delayed`) → Booking unchanged. They are internal to the possession workflow.
- Possession Status itself is NOT state-machine-enforced (consistent with Agreement in E12 — manual moves allowed).

**D5. Snag rollups are native** — no trigger or service for `Snag_Item__c`:
- `Possession.Snag_Count__c` — Roll-Up Summary COUNT
- `Possession.Open_Snag_Count__c` — Roll-Up Summary COUNT filtered `Snag_Item__c.Status__c equals "Open,In Progress"`

The test verifies these auto-compute correctly.

**D6. RecursionGuard key**: `'Possession_afterUpdate'`. Existing BookingTriggerHandler only acts on `Payment_Plan__c` changes (E09), so updating Booking_Status won't cascade — but the guard is still wise.

**D7. 1:1 Booking↔Possession**. Enforced by service: rejects duplicate via `SELECT FROM Possession__c WHERE Booking__c IN :ids`. `Possession.Booking__c` is Master-Detail; `Booking.Possession__c` is Lookup (one slot).

**D8. No validation rules** on Possession__c or Snag_Item__c — gotcha #40 (MD-rollup-VR mid-batch) does not apply.

## Acceptance criteria

| # | Scenario | Expected |
|---|---|---|
| 1 | Create Possession from a Registered Booking | Possession.Name='POS-BKG-...', Status='Ready to Offer', Booking.Status='Possession Ready', Booking.Possession__c set |
| 2 | Try to create a second Possession for same Booking | AuraHandledException "Possession already exists" |
| 3 | Try to create Possession when Booking is Confirmed (too early) | AuraHandledException about invalid status |
| 4 | Update Possession.Status='Handed Over' + Keys_Handed_Date | Booking.Status = 'Possessed' |
| 5 | Update Possession.Status='Offered' or 'Snag Phase' | Booking.Status unchanged (still 'Possession Ready') |
| 6 | Bulk-create 3 Possessions in one call | All 3 named correctly, all 3 Bookings updated |
| 7 | Create 3 Snag Items (Open, In Progress, Resolved) on a Possession | Native Roll-Ups: Snag_Count=3, Open_Snag_Count=2 (Open + In Progress) |

## Iteration story

- Discovery surfaced two corrections to the spec:
  - Field name is `Booking.Possession__c`, not `Related_Possession__c` (parallel to E12 Agreement correction).
  - `Snag_Count__c` and `Open_Snag_Count__c` are native Roll-Up Summary fields, not Number fields requiring Apex aggregation. Big simplification — no SnagItem trigger needed.
- Snag_Item__c has 2 required fields: `Description__c` (Text 255), `Reported_Date__c` (Date). Factory honours both.
- No validation rules on either object.
- Generation produced 6 new files + 1 modified.
- Dry-run deploy clean (36 components total).
- Real deploy hit gotcha #31 (CLI cosmetic "Missing message metadata.transfer:Finalizing"); verified 36/36 Succeeded via `sf project deploy report`.
- **Tests passed 59/59 on first run** — no fix cycles needed. The E12 lesson about `RecursionGuard.resetAll()` in test helpers (top + before each guarded DML) was applied preemptively, avoiding the failure mode that hit E12's bulk test.
- Coverage: PossessionService 96.6%, PossessionNamingService 100%, PossessionTriggerHandler 100%, PossessionTrigger 100%.

## Files produced

```
force-app/main/default/
├── triggers/
│   ├── PossessionTrigger.trigger              NEW
│   └── PossessionTrigger.trigger-meta.xml     NEW
├── classes/
│   ├── PossessionTriggerHandler.cls           NEW   (100% covered)
│   ├── PossessionNamingService.cls            NEW   (100% covered)
│   ├── PossessionService.cls                  NEW   (96.6% covered)
│   ├── PossessionServiceTest.cls              NEW   (7 tests)
│   └── TestDataFactory.cls                    MODIFIED (+createPossession, +createSnagItem)
```

## Test results

```
Tests Ran           59
Outcome             Passed
Pass Rate           100%
Test Run Id         707Hp0000LlefXN
Test Execution Time 69.7s
```

Coverage of E13 classes (all ≥85% target):
- PossessionService            96.6%  (56/58)
- PossessionNamingService     100%   (11/11)
- PossessionTriggerHandler    100%   (6/6)
- PossessionTrigger           100%   (4/4)

Cumulative coverage of all post-sales chain (E08-E13):
- BookingService              100%
- PaymentScheduleService      100%
- DemandService                96%
- DemandNamingService         100%
- ReceiptAllocationService     90%
- AgreementService             97%
- AgreementNamingService      100%
- DemandLetterService          96%
- DemandLetterController       91%
- PossessionService           97%
- All triggers + handlers     100%

## Gotchas surfaced

No new CLAUDE.md entries needed. Honoured:
- **#30** — TestDataFactory respects required fields (Snag_Item.Description, Reported_Date) and Tower/Unit naming VRs.
- **#31** — CLI v2.84.6 cosmetic "Missing message" error on real deploy. Verified via `sf project deploy report`.
- **E12 lesson (RecursionGuard in helpers)** — applied preemptively in `seedAndRegister` (resetAll at top + before each guarded DML: close-won update, agreement update). This prevented the failure mode that bit E12 on first test run.

## Implemented

- [x] PossessionTrigger (before insert, after update)
- [x] PossessionTriggerHandler routing with RecursionGuard('Possession_afterUpdate')
- [x] PossessionNamingService — Name='POS-'+Booking.Name
- [x] PossessionService.createPossessions — invocable with validation + Booking sync
- [x] PossessionService.onAfterUpdate — Handed Over → Possessed
- [x] TestDataFactory.createPossession + createSnagItem
- [x] 7 PossessionServiceTest tests
- [x] Native Snag rollups verified (no Apex needed)
- [x] Deployed to re-crm-sdo
- [x] All 59 tests pass
- [x] Coverage ≥ 96% on every new class

## Buyer lifecycle — now complete (E08 → E13)

```
Lead → Opportunity → Booking [Confirmed]
   ↓ Agreement created (E12)
Booking [Agreement Pending] → Agreement Signed → Booking [Agreement Signed]
   ↓ Agreement Executed (E12)
Booking [Registered]
   ↓ Possession created (E13)
Booking [Possession Ready] → Snag Phase → keys handed
   ↓ Possession Handed Over (E13)
Booking [Possessed] ✓
```

Parallel side-chains:
- Payment Plan instantiation (E09) → Demands (E10) → Demand Letters (E12) → Receipts + Allocations (E11)
- Snag Items (E13) — captured during Snag Phase, native rollups on Possession

## Known follow-ups (next epics)

- **E14** — Possession Offer Letter PDF (VF + ContentVersion, same pattern as E12 Demand Letter).
- **E15** — NOC (No Objection Certificate) PDF for buyers with Total_Outstanding=0 (uses `Possession.All_Dues_Cleared__c` formula gate).
- **E16** — Buyer-portal possession status view (LWC over Booking + Possession + Snag Items).
- **E17** — Commission Payout Statement PDF for partners (E12 PDF pattern).
- **E?** — Snag SLA workflow: due-date alerts, auto-reassignment, escalation.
- **E?** — Possession Quick Actions: "Offer Letter Sent", "Schedule Inspection", "Issue NOC", "Hand Over Keys".
- **E?** — Booking cancellation flow (refund computation, unit re-availability).
- **E23 polish** — Page layouts and Lightning Apps for Possession & Snag Item objects.
