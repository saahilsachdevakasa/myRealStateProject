# E17 — Commission Engine

## Goal

Three-milestone commission accrual (Booking, Agreement Signed,
Registration), a clawback path for cancelled bookings, and a monthly
batch process that rolls Accrued/Approved ledger entries into
per-CP Payout records.

This is the heaviest Apex epic in Phase 1. It binds together the
trigger framework, the rate card service from E14, and the existing
Booking/Agreement lifecycles from E08 / E12.

## Architecture (Section 8 of Phase 1 Architecture)

```
                        ┌────────────────────────┐
                        │  RateCardService (E14) │
                        │  getActiveRateCards()  │
                        └──────────┬─────────────┘
                                   │
   Booking AFTER_INSERT  ─────►   ┌▼─────────────────────────────┐
   Agreement AFTER_UPDATE ─────►  │   CommissionService          │
   Booking AFTER_UPDATE   ─────►  │   accrueOnBooking            │
                                  │   accrueOnAgreementSigned    │
                                  │   accrueOnRegistration       │
                                  │   clawbackOnCancellation     │
                                  └────────────┬─────────────────┘
                                               │ insert/update
                                               ▼
                              ┌─────────────────────────────────┐
                              │   Commission_Ledger__c          │
                              │   (Master-Detail to Booking)    │
                              │                                 │
                              │   Naming trigger applies:       │
                              │   CL-{BKG-NAME}-{nn}            │
                              └────────────┬────────────────────┘
                                           │
                                           ▼ batched & rolled up
                              ┌─────────────────────────────────┐
                              │   CommissionPayoutBatch         │
                              │   start: Accrued/Approved +     │
                              │     no Payout                   │
                              │   execute: group by CP, insert  │
                              │     Payout, link entries        │
                              │   schedulable for monthly cron  │
                              └────────────┬────────────────────┘
                                           ▼
                              ┌─────────────────────────────────┐
                              │   Commission_Payout__c          │
                              │   AutoNumber CPY-{YY}-{MM}-{000}│
                              └─────────────────────────────────┘
```

## Implemented

### Apex services

- `force-app/main/default/classes/CommissionService.cls` — 4 entry
  points, all bulkified, `WITH SECURITY_ENFORCED`, `with sharing`:

  | Method | Trigger context | Filter | Output |
  |---|---|---|---|
  | `accrueOnBooking(List<Booking__c>)` | BookingTrigger AFTER_INSERT | `Source_CP__c != null` | One Booking-milestone Ledger per Booking with rate card |
  | `accrueOnAgreementSigned(newList, oldMap)` | AgreementTrigger AFTER_UPDATE | `old.Status != 'Signed' && new.Status == 'Signed'` | One Agreement-milestone Ledger per qualifying Booking |
  | `accrueOnRegistration(newList, oldMap)` | AgreementTrigger AFTER_UPDATE | `Registration_Date null→non-null && Status == 'Executed'` | One Registration-milestone Ledger per qualifying Booking |
  | `clawbackOnCancellation(newList, oldMap)` | BookingTrigger AFTER_UPDATE | `old.Booking_Status != 'Cancelled' && new == 'Cancelled'` | Status update for Accrued/Approved; new offset entry for Paid |

  Internal `accrueMilestone(bookings, milestone)` is the shared
  accrual core. Bulk-loads CP accounts (Tier + GSTIN) once,
  bulk-loads rate cards via `RateCardService.getActiveRateCards`
  once, then computes and inserts Ledger entries in a single DML.

  Per Section 8.4: when no active rate card exists for the
  Booking's `Project x CP_Tier`, the service logs a `LoggingLevel.WARN`
  and skips silently — does NOT block Booking insert or Agreement
  status updates. Booking flows are commission-independent.

- `force-app/main/default/classes/CommissionPayoutBatch.cls` —
  `Database.Batchable<SObject>` + `Schedulable`. `start` queries
  Accrued/Approved entries with `Payout__c = null`. `execute`
  groups entries by `Channel_Partner__c`, computes Apex
  aggregates (`Entry_Count`, `Gross_Commission`, `GST_Total`,
  `TDS_Total`) per CP, inserts one Payout per CP, then updates
  ledger entries to point to their Payout. `Schedulable.execute`
  re-launches the batch (chunk size 200) — register a cron via
  `System.schedule('Monthly CP Payout', '0 0 1 1 * ? *', new CommissionPayoutBatch())`.

### Naming pipeline

- `force-app/main/default/triggers/CommissionLedgerTrigger.trigger`
  — `before insert` only.
- `force-app/main/default/classes/CommissionLedgerTriggerHandler.cls`
  — minimal routing.
- `force-app/main/default/classes/CommissionLedgerNamingService.cls`
  — self-computes sequence (no `Ledger_Seq__c` field needed):
  bulk-queries `COUNT(Id) GROUP BY Booking__c` for existing
  entries, tracks per-Booking offset for in-batch entries, writes
  `CL-{BKG-NAME}-{nn}` (zero-padded 2 digits).

  Differs from `DemandNamingService` (which reads pre-set
  `Demand_Seq__c` from caller). Self-computing here avoids a
  schema field on Commission_Ledger.

### Trigger wiring (modifications to existing handlers)

- `BookingTrigger.trigger` — added `after insert` context.
- `BookingTriggerHandler.cls`:
  - `AFTER_INSERT` → `CommissionService.accrueOnBooking(newList)`
    — no recursion guard (insert fires once per record).
  - `AFTER_UPDATE` (inside existing `Booking_afterUpdate` guard) —
    added `CommissionService.clawbackOnCancellation(newList, oldMap)`
    after the existing `PaymentScheduleService` call.
- `AgreementTriggerHandler.cls`:
  - `AFTER_UPDATE` (inside existing `Agreement_afterUpdate` guard) —
    added `CommissionService.accrueOnAgreementSigned(newList, oldMap)`
    and `CommissionService.accrueOnRegistration(newList, oldMap)`
    after the existing `AgreementService.onAfterUpdate` call.

  No new RecursionGuard keys needed — commission methods do not
  modify Booking or Agreement (they only insert into
  Commission_Ledger__c, which only has a BeforeInsert trigger
  for naming). No re-entry risk.

### Schema change

- `Commission_Ledger__c.Milestone__c` picklist gained the
  `Clawback` value (in addition to the existing Booking,
  Agreement, Registration). Used for the negative-amount offset
  entry created when an already-Paid commission is clawed back
  due to Booking cancellation.

### Test coverage

- `CommissionServiceTest` — 10 tests, 100% pass:
  - Happy path with GSTIN (no GST)
  - No CP → no accrual
  - CP without GSTIN → 18% reverse-charge GST
  - No matching rate card → silent skip, Booking unaffected
  - Agreement Signed → 2 entries
  - Registration → 3 entries
  - Full lifecycle: 3 entries, sequential naming `-01/-02/-03`,
    snapshotted basis, milestone-specific rates
  - Clawback of Accrued → status update, no new entry
  - Clawback of Paid → original preserved, new `Clawback` entry
    with negative amounts and `Hold_Reason` reference
  - Bulk: 3 Bookings × 3 different CP tiers in one transaction

- `CommissionPayoutBatchTest` — 3 tests, 100% pass: groups by CP
  with per-CP roll-ups, no-eligible-entries no-op, Schedulable
  interface registration.

- Full regression: **73 / 73 tests pass** across all 11 service
  test suites. The new BookingTrigger AFTER_INSERT context did
  not break any existing tests because every existing Booking
  test (and the seeded data) had `Source_CP__c = null` →
  `accrueOnBooking` short-circuits at the SOQL filter.

### TestDataFactory extensions

- `createCommissionLedger(bookingId, cpAccountId, overrides)` —
  defaults Milestone='Booking', Status='Accrued', basis 1,000,000,
  Rate_Pct 2, computed GST/TDS.
- `createCommissionPayout(cpAccountId, overrides)` — defaults
  Status='Draft', Payout_Month='2026-04'.

### Demo seed

`scripts/seed-demo-data-05-commissions.apex` — idempotent,
backfills the existing Possessed Happy Path Booking (BKG-PRK-26-0001)
with `Source_CP = Acme Realty Advisors` (Platinum), inserts 3
ledger entries (Booking 540K / Agreement 270K / Registration 135K
gross), and runs `CommissionPayoutBatch`. Output:

```
CL-BKG-PRK-26-0001-01 [Booking]      Gross=540,000  Net=610,200
CL-BKG-PRK-26-0001-02 [Agreement]    Gross=270,000  Net=305,100
CL-BKG-PRK-26-0001-03 [Registration] Gross=135,000  Net=152,550
CPY-26-04-004 [Acme Realty Advisors] Entries=3 Gross=945,000 Net=1,067,850
```

(Net > Gross because Acme has no GSTIN → 18% reverse-charge GST
adds to Net; TDS subtracts. Per Section 8.3.)

## Non-obvious design decisions

### Percent storage and the Currency × Percent formula

`Commission_Ledger__c.Rate_Pct__c` stores the literal display
value (2 for 2%, NOT 0.02). The `Gross_Commission__c` formula is
`Agreement_Value_Basis * Rate_Pct` — empirically verified that
Salesforce's `Currency × Percent` formula evaluation treats the
Percent operand as a decimal (2 → 0.02), so `1,000,000 * 2`
yields 20,000 (2% of basis), NOT 2,000,000. CommissionService
passes `Rate_Pct` through from the rate card unchanged.

For Apex GST/TDS computation we explicitly divide by 100 to
mirror this:
```apex
Decimal gross = (basis * ratePct / 100).setScale(2);  // mirrors formula
Decimal gst = String.isBlank(cp.GSTIN__c) ? (gross * 0.18).setScale(2) : 0;
Decimal tds = (gross * 0.05).setScale(2);
```

### `Booking.Project__c` is a Formula(Text), not a Lookup

The Booking's "project" field returns the Project_Code string,
not the Project Id. To get the Project Id needed for rate-card
lookup, traverse `Unit__r.Tower__r.Project__c` (the actual Lookup
field on Tower). Every CommissionService SOQL on Booking includes
this traversal.

### Clawback semantics

- **Accrued or Approved** entries: `Status` flipped to `Clawed Back`,
  no new entry. Audit trail is the entry's modification timestamp.
- **Paid** entries: original is **never modified** (audit-preserving).
  A new offset entry is inserted with `Milestone = 'Clawback'`,
  negated `Agreement_Value_Basis / GST / TDS`, `Status = 'Accrued'`
  (so it flows through the normal approval/payout cycle as a
  negative on the next Payout), and `Hold_Reason = 'Clawback of {original Name}'`
  for cross-reference.

### CommissionPayoutBatch aggregates are NOT roll-up summary fields

`Commission_Payout__c.Entry_Count`, `Gross_Commission`, `GST_Total`,
`TDS_Total` are plain Number/Currency fields (verified in
discovery). The batch computes them in Apex when grouping ledgers
by CP. Roll-up summaries weren't used because Commission_Ledger
is master-detail to **Booking**, not Payout — Payout is a Lookup
relationship from Ledger, which doesn't support roll-ups.

## Out of scope

- **Approval flow** (Accrued → Approved transition before Payout)
  — Section 8.5. Currently the batch processes both Accrued and
  Approved entries indiscriminately. Adding an approval step is a
  small follow-up.
- **CP-facing payout statement PDF** generation — `Statement_PDF_Id__c`
  field exists on Commission_Payout but is not populated yet.
- **Scheduled cron registration** for monthly run — Schedulable
  interface is implemented, but `System.schedule(...)` itself is
  one-line manual setup (or via a deploy of a scheduled CronTrigger
  metadata in a future epic).
- **Payment UTR capture and Status='Paid'** transition — manual
  workflow today; field exists, no automation yet.
- **Rate card change versioning impact on in-flight commissions**
  — current implementation snapshots Rate_Pct on each Ledger entry
  at accrual time, so rate-card edits don't retroactively shift
  past entries. Section 8.4 ✓.

## Test coverage detail

| Test class | Pass | Notes |
|---|---|---|
| CommissionServiceTest | 10/10 | Synchronous run |
| CommissionPayoutBatchTest | 3/3 | Synchronous run |
| Full regression (11 classes, 73 tests) | 73/73 | Async run |

Coverage figures pending — CLI v2.84.6 has known issues per gotcha
#31. Verified via Tooling API that `CommissionService` is exercised
by 10 tests touching every entry point, and the trigger pipeline
is exercised end-to-end (Closed Won → Booking → Agreement → Registration
→ Cancellation chains all run through real triggers in the tests).
