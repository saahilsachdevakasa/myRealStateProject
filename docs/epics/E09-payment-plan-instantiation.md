# E09 — Payment Plan Instantiation Trigger on Booking

## Objective

After E08 created `Booking__c` records with `Payment_Plan__c = null`, E09
wires up the next step: when a user (or future Quick Action) selects a
Payment Plan on a Booking, the system instantiates per-milestone
`Booking_Payment_Schedule__c` rows from the plan's milestone template.

The schedule rows carry: scheduled amount (computed from
`Booking.Agreement_Value__c × milestone.Percentage__c`), expected date
(computed from `Booking_Date__c + Days_From_Trigger__c` for
Booking/Time-Based triggers; null for Construction/Possession until
those events resolve in E10+), and a `Pending` status.

Plan switching (changing `Payment_Plan__c` from one plan to another) is
also handled — old schedule rows are deleted before new ones are
created, so there are never orphan rows or double instantiation.

E09 is the second after-update trigger consumer of `RecursionGuard`
(after `OpportunityTriggerHandler` from E08), reinforcing the pattern
for trigger handlers that DML on related objects.

## Dependencies

- **E02b** — `Payment_Plan__c`, `Payment_Plan_Milestone__c`,
  `Booking_Payment_Schedule__c` objects with all fields deployed.
  Booking_Payment_Schedule__c.Booking__c is MasterDetail on Booking__c
  (cascade delete, useful for cleanup).
- **E08** — `Booking__c.Payment_Plan__c` lookup is now optional
  (changed from required → optional in E08). BookingService creates
  Bookings with `Payment_Plan__c = null`; E09 fills the gap.
- **E07** — RecursionGuard pattern shipped; E08 was first consumer,
  E09 is the second. Per CLAUDE.md gotcha #40 mechanic
  (rollup-recalc-fires-VR), tests use `RecursionGuard.resetAll()` to
  simulate cross-transaction boundaries within a single test method.

## In scope

### 5 new Apex artefacts

- **`triggers/BookingTrigger.trigger`** — thin trigger, after-update
  only, 7 lines.
- **`classes/BookingTriggerHandler.cls`** — routes `AFTER_UPDATE` →
  `PaymentScheduleService.onPaymentPlanSelected` through
  `RecursionGuard.isFirstRun('Booking_afterUpdate')`. Guard is
  necessary because the service's child DML
  (insert `Booking_Payment_Schedule__c`) doesn't re-fire
  `BookingTrigger` (different SObject), but if E10+ adds Booking
  self-DML in the same handler chain, the guard prevents recursion.
- **`classes/PaymentScheduleService.cls`** — 5-step service:
  1. **Filter** Bookings where `Payment_Plan__c` changed (null→value
     OR value→different value). Skips no-change updates and
     value→null (which means "user unset the plan" — leave existing
     rows as-is for safety).
  2. **Re-query** qualifying Bookings with `Agreement_Value__c`,
     `Booking_Date__c`.
  3. **Query** active milestones grouped by Payment_Plan_Id, ordered
     by Sequence__c.
  4. **DELETE** existing schedule rows for these Bookings. Safe for
     null→value (no-op delete) and value→different (drops the old
     plan's instantiation).
  5. **Build + INSERT** new schedule rows. `Scheduled_Amount = Agreement_Value × (Percentage / 100)`.
     `Expected_Date` = `Booking_Date + Days_From_Trigger` for
     Booking / Time-Based triggers; `null` for Construction /
     Possession (resolved later by E10+).

- **`classes/PaymentScheduleServiceTest.cls`** — 5 test methods,
  all passing:
  - `testPaymentPlanSelection_CreatesScheduleRows` — happy path
    via E08 close-won + plan select; asserts row count, percentages,
    amounts, expected dates per trigger type.
  - `testPaymentPlanSwitch_DeletesOldCreatesNew` — Plan A (3 rows)
    → Plan B (2 rows); asserts old rows deleted, new rows have Plan
    B's milestone triggers.
  - `testPaymentPlanSelection_NoAgreementValue` — `Quoted_Gross_Value=0`
    → `Agreement_Value=0`; asserts schedule rows still created with
    `Scheduled_Amount=0`.
  - `testPaymentPlanSelection_BulkOperation` — 5 Bookings (codes
    `BKA`-`BKE` per Project_Code_Format VR), bulk update, asserts
    10 schedule rows total (5 × 2 milestones).
  - `testPaymentPlanSelection_InactiveMilestonesSkipped` — plan with
    4 milestones, 1 inactive; asserts 3 rows created, no row
    references the inactive milestone.

### Modified file: TestDataFactory.cls

Added 4 builder methods:
- `createPaymentPlan(Map<String,Object> overrides)` — defaults
  `Active__c = false` to avoid the gotcha-#40 VR issue during
  subsequent milestone inserts. Tests that need active plans
  override.
- `createPaymentPlanMilestone(Id planId, Map<String,Object> overrides)`
  — singleton create with sensible defaults (Sequence=1, Trigger='On Booking',
  Trigger_Type='Booking', Percentage=100, Active=true).
- `createPaymentPlanWithMilestones(Integer count, Map<String,Object> planOverrides)`
  — convenience: plan + N milestones with equal-split percentages
  (100/N each, rounded; last one absorbs the remainder so total is
  exactly 100).
- `createBooking(Id oppId, Id unitId, Id accountId, Map<String,Object> overrides)`
  — direct-create Booking. 4-arg signature (vs spec's 3-arg) explicitly
  takes `accountId` since `Primary_Buyer__c` is required and isn't
  derivable from the Opp without an extra SOQL. Computes Name from
  the linked Unit's Project_Code__c (single SOQL). Caller is
  responsible for ensuring the Unit is in `Blocked` status before
  call (per Booking VR `Unit_Must_Be_Blocked_At_Booking`).

### Seed script: `scripts/seed-payment-plans.apex`

Anonymous Apex that idempotently seeds 3 demo Payment Plans:
- **CLP** (Construction Linked Plan) — 10 milestones
- **DLP** (Down Payment Plan) — 3 milestones (10/80/10)
- **PLP** (Possession Linked Plan) — 4 milestones (10/10/10/70)

Run: `sf apex run --file scripts/seed-payment-plans.apex --target-org re-crm-sdo`

**Plans seeded as `Active__c = false`** — see gotcha #40 + Manual Setup
section for why and how to activate.

## Out of scope (deferred)

- **`Booking.Payment_Plan_Instance__c` lookup** — exists in the data
  model but its purpose is unclear from the spec (lookup to
  Booking_Payment_Schedule__c). E09 doesn't populate it. E10+ may
  use it to point to "the next due milestone" or similar — TBD when
  the field's intent is clarified.
- **Construction / Possession milestone date resolution.** E09
  leaves `Expected_Date__c = null` for these trigger types. E10
  (or whichever epic owns construction milestone tracking) will
  populate them as the underlying events occur.
- **Quick Action on Booking to select a Payment Plan.** E09 fires
  on any update to `Payment_Plan__c` — the user can select via the
  inline Lightning record-page edit. A dedicated Quick Action with
  filtering (e.g., only show Active plans applicable to this
  Project's type) is a UX polish item; not blocking.
- **Inactive plan filter on the picker.** Lookup pickers show all
  Payment Plans regardless of `Active__c`. To restrict, add a Lookup
  Filter on `Booking.Payment_Plan__c` for `Active__c = true`. Defer
  until activation manual step is automated.
- **Async / Platform Event implementation.** Phase 1 spec mentioned
  Platform Events for this; E09 went with direct trigger for MVP
  simplicity. If demo throughput becomes an issue, refactor to
  PE-subscriber.

## Decisions locked

- **D1 — After-update trigger pattern, RecursionGuard required for
  pattern consistency** even though current handler doesn't self-DML.
  Sets the pattern for E10+ Booking after-triggers.
- **D2 — Plan switching = delete-then-create.** Cleanest semantics.
  No partial re-creation, no schema for "plan version" tracking.
- **D3 — Filter null→null and value→null are no-ops.** Removing a plan
  doesn't delete schedule rows; deletion happens only on switch
  (value→value). Rationale: prevents accidental data loss; user can
  manually delete schedule rows if needed.
- **D4 — Expected_Date math:** Booking-trigger gives
  `Booking_Date + 0`, Time-Based gives `Booking_Date + Days_From_Trigger`,
  Construction and Possession get `null` until those events resolve.
- **D5 — TestDataFactory.createPaymentPlan defaults Active=false.**
  The simplest workaround for gotcha #40. Tests that need active
  plans override via the Map. Production seed script same default.
- **D6 — Direct-create createBooking signature**:
  `(Id oppId, Id unitId, Id accountId, Map<String,Object>)`. Explicit
  accountId for clarity; derives Name from Unit's Project_Code via
  one extra SOQL.
- **D7 — Plan VR `Active_Plan_Total_Pct_Must_Be_100` left in place.**
  The 100% invariant is valuable for production; the seed-time UX
  cost (manual activation) is acceptable. Captured as gotcha #40.

## Acceptance criteria

1. **BookingTrigger active** — verified.
2. **3 new Apex classes active** — `BookingTriggerHandler`,
   `PaymentScheduleService`, `PaymentScheduleServiceTest`.
3. **TestDataFactory updated** with 4 new builder methods.
4. **All 26 tests pass** — 5 new (PaymentScheduleService) + 5
   (BookingService) + 5 (UnitBlockingService) + 9 (UnitLifecycleService)
   + 2 setup methods.
5. **Coverage ≥ 85%** on PaymentScheduleService (actual: 100%).
6. **Seed script runs cleanly** — 3 plans + 17 milestones loaded.

## Manual Setup steps (post-deploy)

### 1. Run the seed script

```bash
sf apex run --file scripts/seed-payment-plans.apex --target-org re-crm-sdo
```

Verify:
```bash
sf data query --query "SELECT Name, Plan_Code__c, Active__c FROM Payment_Plan__c WHERE Plan_Code__c IN ('CLP','DLP','PLP')" --target-org re-crm-sdo
```
Expected: 3 plans, all `Active__c = false`.

### 2. Activate the plans via Setup UI

Per gotcha #40, the plans cannot be activated via Apex without
hitting the `Active_Plan_Total_Pct_Must_Be_100` VR. Manual activation
is the workaround:

1. Setup → Object Manager → **Payment Plan** → Tab "Page Layouts" →
   verify the layout is in place (deployed in E06-layout).
2. Open the Payment Plans tab in the App Launcher.
3. For each of the 3 seeded plans:
   - Open the record (CLP, DLP, PLP).
   - Click Edit. Toggle `Active` to true. Save.
   - The save succeeds because the Setup UI's record-detail edit
     issues an explicit user DML on the Plan, and by that time the
     async rollup recalculation has long-committed (`Total_Pct_Check__c`
     = 100). VR passes.

This activation is one-time per SDO refresh.

## Iteration story

| Attempt | Outcome | Class |
|---|---|---|
| Seed run 1 (Active=true plans, then milestones single-txn) | FAILED — milestone insert fires parent VR via rollup recalc | NEW (gotcha #40) |
| Seed run 2 (Active=false plans, then milestones, then Active=true update) | FAILED — same VR; rollup not committed even across separate `sf apex run` calls | NEW (gotcha #40 reinforces) |
| Seed run 3 (Active=false plans, then milestones, leave inactive) | Green — manual activation via Setup UI documented as a one-time step | — |
| Apex deploy 1 | Green — 16 components Created/Unchanged | — |
| Test run 1 | 22/26 pass — 3 fail same gotcha #40 (TDF default Active=true), 1 fails Project_Code_Format (codes BK1-BK5 had digits) | NEW (TDF default + bulk-test typo) |
| Apex redeploy after 2-line fixes (TDF default → Active=false, bulk codes → BKA-BKE) | Green — 16 deployed | — |
| Test run 2 | **26/26 pass** | — |
| Sync coverage run | PaymentScheduleService 100%, BookingTrigger 100%, BookingTriggerHandler 100% | — |

## Files produced

**New (5 + meta = 10 files):**
- `triggers/BookingTrigger.trigger` (+meta)
- `classes/BookingTriggerHandler.cls` (+meta)
- `classes/PaymentScheduleService.cls` (+meta)
- `classes/PaymentScheduleServiceTest.cls` (+meta)
- `scripts/seed-payment-plans.apex`

**Modified (1 file):**
- `classes/TestDataFactory.cls` — +4 builder methods (createPaymentPlan,
  createPaymentPlanMilestone, createPaymentPlanWithMilestones,
  createBooking)

## Gotchas captured (now in CLAUDE.md)

- **#39** — Lightning Apps default to invisible on all profiles
  (deferred from E06-apps; codified now).
- **#40** — MD child DML fires parent VRs through rollup recalc.

## Implemented

**Commits**
See `git log --grep='E09'` for the commits that implemented this
epic (3 commits per spec):
- `chore(E09)` — seed script
- `feat(E09)` — Apex (trigger + handler + service + test + TDF extension)
- `docs(E09)` — epic spec + CLAUDE.md gotchas #39, #40

## Known follow-ups

- **Plan activation UX.** If the manual activation step becomes
  painful at SDO refresh, options:
  - A scheduled Apex job that re-evaluates plan activation post-rollup.
  - Drop the VR (loses invariant protection).
  - Replace VR with a Flow that triggers only on user-initiated
    activation (skips rollup-recalc re-evaluation).
- **Lookup filter on `Booking.Payment_Plan__c`** to exclude inactive
  plans from the picker. Small polish.
- **`Booking.Payment_Plan_Instance__c`** purpose clarification — if
  it's meant to point to the "current due" schedule row, add
  population logic in PaymentScheduleService.
- **Construction milestone date resolution** (E10+). When a
  construction-stage event is logged on the Project (e.g., "1st
  floor slab cast on YYYY-MM-DD"), all related schedule rows with
  matching `Milestone_Trigger__c` should have their `Expected_Date__c`
  populated.
- **Booking Payment Schedule status auto-transitions** — `Pending`
  → `Demand Raised` (E11) → `Paid` (E11) → `Overdue` (scheduled
  Flow). Out of E09 scope.
