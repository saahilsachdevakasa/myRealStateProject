# E08 — Opportunity → Booking Trigger

## Objective

When an Opportunity transitions to `Closed Won (Booked)`, the system
must atomically:

1. Create a `Booking__c` record with the proper naming convention
   (`BKG-{PROJ}-{YY}-{0000}`), seeded with all immutable
   booking-time data (RM, Source, BSP, Quoted Value, Owner=Post-Sales
   Queue).
2. Transition the Primary Unit from `Blocked` → `Booked` and link
   the unit's `Active_Booking__c` to the new Booking.
3. Link the Opportunity's `Booking__c` lookup to the new Booking
   for round-trip navigation.

E08 wires these three legs together via the project's first
**after-update trigger** on a standard object. It is also the first
real consumer of `RecursionGuard` (shipped utility-only in E07).

The **most complex Apex epic in the MVP** because it touches three
objects across two triggers (Opportunity after-update fires
BookingService → Unit update fires UnitTrigger → state-machine
validates Blocked→Booked) and orchestrates per-project sequence
numbering against an existing-records query.

## Dependencies

- **E02b** complete — `Booking__c` object with all 34 fields
  (the trigger writes 11 of them).
- **E04** complete — `Post_Sales_Queue` exists and is bound to
  `Booking__c` via `<queueSobject>`.
- **E05** complete — `Transfer_Booking_To_Post_Sales_Queue` Flow
  exists from E05; E08 sets `OwnerId=PostSalesQueue` at INSERT
  time, so the Flow becomes a no-op (no error, just a redundant
  ownership confirm).
- **E05b** complete — Admin profile FLS already grants
  most Booking fields. **E08 adds the `Booking__c.Payment_Plan__c`
  fieldPermissions entry** that was previously excluded under
  gotcha #26 (required fields reject FLS grants), since E08
  changes Payment_Plan__c from required to optional.
- **E06a** complete — `Closed Won (Booked)` is an active
  OpportunityStage and is the terminal stage in both
  `Pre_sales_Residential` and `Pre_sales_Commercial` BPs.
- **E06b** complete — Opportunity stage-gate VRs ensure
  `Project__c`, `Primary_Unit__c`, `EOI_Amount__c`, `Token_Amount__c`
  are populated before Closed Won; the trigger reads them safely
  knowing they're non-null.
- **E06c** complete — `TestDataFactory` exists with Project /
  Tower / Unit builders; E08 extends it with `createAccount` and
  `createOpportunity`.
- **E07** complete — `Unit_Status__c` state machine validates
  `Blocked → Booked` (allowed); `RecursionGuard.cls` exists as a
  utility (E08 is its first consumer).

## In scope

### 5 new Apex artefacts (flat `classes/`)

- **`triggers/OpportunityTrigger.trigger`** — thin trigger,
  after-update only. 7 lines.
- **`classes/OpportunityTriggerHandler.cls`** — routes
  `AFTER_UPDATE` to `BookingService.onOpportunityClosedWon`
  through `RecursionGuard.isFirstRun('Opportunity_afterUpdate')`.
  Guard is **necessary** here because Step 5 of the service does
  `update opps` on the same object, which would re-fire the
  trigger without the guard.
- **`classes/BookingService.cls`** — 6-step service:
  1. **Filter** Opps where Stage transitioned to
     `Closed Won (Booked)` AND `Booking__c IS NULL`.
  2. **Re-query** qualifying Opps with all needed fields
     (`AccountId, Primary_Unit__c, Project__c, Source_Channel__c,
     Source_CP__c, OwnerId, Quoted_Gross_Value__c`).
  3. **Query** related Units (for `BSP_Per_Sqft__c`) and Projects
     (for `Project_Code__c`).
  4. **Compute per-project sequences** for the current calendar
     year by querying existing Bookings on
     `Unit__r.Tower__r.Project__c IN :projectIds AND
     CALENDAR_YEAR(Booking_Date__c) = :currentYear`. In-memory
     map per project; in-memory increment for bulk waves.
  5. **Insert** new Bookings with computed name, status='Confirmed',
     all FK references, Owner=PostSalesQueue. Booking VR
     `Unit_Must_Be_Blocked_At_Booking` fires here — Unit is still
     in `Blocked` status at this point, VR passes.
  6. **Update** Units to `Booked` status with `Active_Booking__c`
     set. Trigger UnitTrigger → UnitLifecycleService validates
     `Blocked → Booked` (allowed).
  7. **Update** Opportunities with `Booking__c` reference. Trigger
     fires OpportunityTrigger again; RecursionGuard prevents
     re-entry into BookingService. ✓
- **`classes/BookingServiceTest.cls`** — 5 test methods:
  - `testClosedWon_CreatesBooking` — happy path with full
    assertion of all booking fields, owner-is-queue, unit-is-Booked,
    opp-points-to-booking.
  - `testClosedWon_UnitNotBlocked_Fails` — Unit in `Available`
    state. Booking VR `Unit_Must_Be_Blocked_At_Booking` rejects
    insert with message containing `'Blocked'`.
  - `testClosedWon_NoDoubleBooking` — Opp already has
    `Booking__c` set. Re-saving Opp at Closed Won stage does NOT
    create a second Booking (filter excludes).
  - `testClosedWon_BulkOperation` — 5 Projects (codes TSA, TSB,
    TSC, TSD, TSE), one Opp each, all Closed Won in a single
    bulk DML. Each project gets its own seq=0001.
  - `testBookingName_SequentialInSameProject` — 1 project (PRK),
    2 separate close-won DMLs (with `RecursionGuard.resetAll()`
    between to simulate cross-transaction boundary). First gets
    `BKG-PRK-{YY}-0001`, second gets `BKG-PRK-{YY}-0002`.

### 3 file modifications

- **`objects/Booking__c/fields/Payment_Plan__c.field-meta.xml`** —
  `<required>true → false</required>`. Per D-PAYMENT-PLAN
  Option C, defers Payment Plan selection to E09. Without this
  change, the Booking insert would fail `REQUIRED_FIELD_MISSING`.
- **`profiles/Admin.profile-meta.xml`** — added
  `Booking__c.Payment_Plan__c` `<fieldPermissions>` block
  alphabetically (between `Payment_Plan_Instance__c` and
  `Possession__c`). Was previously excluded due to gotcha #26;
  now includable since required=false.
- **`classes/TestDataFactory.cls`** — added `createAccount` (with
  Buyer RT lookup at runtime via Schema describe — no hardcoded Id)
  and `createOpportunity` (defaults Stage='New' + CloseDate +
  AccountId).

## Out of scope (deferred)

- **Payment Plan selection** — E09 owns it (Demand schedule
  generation requires a Payment Plan). E08 leaves
  `Booking.Payment_Plan__c = null` post-creation; E09 will set it
  via Quick Action / Flow.
- **Booking-side cancellation logic** — E12+ owns Booking status
  transitions (Confirmed → Agreement Pending, etc.). E08 only
  creates the Booking in `Confirmed` status.
- **Commission accrual** — Phase 1 Section 8 — fires via a
  separate trigger on Booking insert (E10 or thereabouts). E08
  populates the fields commission needs (BSP, Source_CP, etc.)
  but doesn't compute commission.
- **Round-robin RM / Post-Sales-Exec assignment within the
  queue** — Booking owner is the queue group itself. Reassignment
  to a specific exec happens out-of-band (Salesforce queue UI or
  a future Flow).
- **Opportunity AccountId null handling** — current implementation
  relies on Account being set on the Opportunity (Booking insert
  fails REQUIRED_FIELD_MISSING on Primary_Buyer__c if null). No
  explicit guard. Worth a follow-up VR on Opportunity:
  `Closed_Won_Requires_Account` if seen in production.

## Decisions locked

- **D-PAYMENT-PLAN — Option C (drop Required).** Smallest E08
  surface area; defers an E09-owned concern to E09. Risk
  documented: a Booking could exist without a Payment Plan if
  E09's logic is broken or removed. Mitigation deferred to E09.
  Admin FLS update bundled in this commit (gotcha #26 sequencing:
  required-field FLS exclusion lifts when required becomes false).

- **D-RECURSION-GUARD — use as specified, no try/finally reset
  in handler.** Within a single DML, Step 5's re-fire is correctly
  suppressed. Across multiple DMLs in the same Apex test method
  (rare in production; common in tests), tests use the
  `@TestVisible RecursionGuard.resetAll()` to simulate
  cross-transaction boundaries. In production, separate user
  actions = separate Apex transactions = static state resets
  automatically.

- **D-OWNER-AT-INSERT — set OwnerId = PostSalesQueue on the
  Booking insert (Step 5), not as a separate update.** Saves one
  DML statement per bulk wave. The E05
  `Transfer_Booking_To_Post_Sales_Queue` Flow becomes a redundant
  no-op (sets owner to the same queue); not removed in E08 to
  preserve the Flow as a fallback if the trigger is disabled.

- **D-SEQUENCE-VIA-COUNT — count existing bookings per project
  per year via SOQL, not Custom Setting.** Phase 1 spec calls for
  a `Booking_Sequence__c` Custom Setting. For SDO/MVP, simpler
  count-based approach is sufficient; production Phase 2 will
  replace with locked Custom Setting or platform sequence to
  handle concurrent inserts safely. Documented as known
  limitation.

- **D-TRIGGER-CONTEXT — after-update only.** Filter logic
  requires `Trigger.oldMap` to detect stage transitions. Before-
  update would also work but after-update is more conventional
  for "create related records" patterns and matches Salesforce
  best practice for cross-object DML.

- **D-API-VERSION — 62.0** for trigger + handler + service +
  test. Matches E06c/E07.

## Acceptance criteria

1. **OpportunityTrigger active** — verified via Tooling API
   (`SELECT Status FROM ApexTrigger WHERE Name='OpportunityTrigger'`
   returns `Active`).
2. **3 new Apex classes active** — `OpportunityTriggerHandler`,
   `BookingService`, `BookingServiceTest` all `Status=Active`,
   API 62.
3. **TestDataFactory updated** with `createAccount` +
   `createOpportunity`; existing 6 builders unchanged.
4. **Payment_Plan__c.required = false** in source and on org
   (deploy reports Changed).
5. **Admin profile has FLS for Payment_Plan__c** — verified via
   `grep` post-deploy.
6. **All 21 tests pass** — 5 new (BookingService) + 5
   (UnitBlockingService) + 9 (UnitLifecycleService) + 2 setups.
7. **Coverage ≥ 85%** on every E08 class:
   - BookingService: **100%** (73/73)
   - OpportunityTrigger: **100%** (4/4)
   - OpportunityTriggerHandler: **100%** (4/4)
   - RecursionGuard: **80%** (8/10) — raised from 0% in E07.
     Uncovered: `reset(key)` method (called by neither tests nor
     consumers; would be exercised by a fault-injection scenario).
     Deferred — won't fix until a real consumer needs `reset()`.
8. **No regression on E06c/E07 tests** — UnitBlockingServiceTest,
   UnitLifecycleServiceTest still 100% pass with same coverage.

## Manual verification (post-deploy, E23 rehearsal hook)

Cannot be scripted automatically — Sahil to run as a smoke test
at next SDO login:

1. Create a fresh Opportunity on a Pre-sales Residential record
   type. Set Project, advance through the stage gates (E06b
   validations) populating Primary_Unit, EOI_Amount, Token_Amount
   etc. Block the Unit before reaching Negotiation (use the Block
   Unit affordance from E06c — when the Screen Flow lands in
   E06-layout — or directly via Setup UI).
2. Set Stage to `Closed Won (Booked)`. Save.
3. Refresh the Opp. Confirm:
   - `Booking__c` lookup is now populated.
   - Click through to the Booking. Name should be
     `BKG-{PROJ_CODE}-{YY}-0001` (or higher if other Bookings
     exist for that project this year).
   - Booking owner = "Post-Sales Queue".
   - Booking_Status = "Confirmed".
   - Linked Unit's status = "Booked", Active_Booking points back
     to this Booking.
   - Booking shows on the Post-Sales Queue's list view.

## Iteration story

| Attempt | Components | Tests | Result |
|---|---|---|---|
| Dry-run 1 | 9 deltas (4 Created Apex/trigger + 3 Changed + others Unchanged) | Skipped | Green, ~5s, Deploy ID `0AfHp0...` |
| Real deploy 1 (NoTestRun) | 7 deployed | N/A | Succeeded — CLI cosmetic "Missing message" error per gotcha #31; `deploy report --json` confirmed `Status=Succeeded`, 0 errors |
| Async test run 1 (3 classes) | — | 21/21 pass | Green, 100% pass rate |
| Sync run 1 (BookingServiceTest, coverage) | — | 5/5 pass | 100% on E08 deliverables |
| Sync run 2 (UnitBlockingServiceTest, coverage) | — | 5/5 pass | Refreshes UnitBlockingService aggregate to 100% |
| Sync run 3 (UnitLifecycleServiceTest, coverage) | — | 9/9 pass | Refreshes UnitLifecycleService aggregate to 100% |

No deploy retries. No test failures.

## Files produced

- **New (5 + 5 meta = 10 files):**
  - `triggers/OpportunityTrigger.trigger` (+meta)
  - `classes/OpportunityTriggerHandler.cls` (+meta)
  - `classes/BookingService.cls` (+meta)
  - `classes/BookingServiceTest.cls` (+meta)

- **Modified (3 files):**
  - `objects/Booking__c/fields/Payment_Plan__c.field-meta.xml`
    (single-line: required true → false)
  - `profiles/Admin.profile-meta.xml` (+5 lines:
    `Booking__c.Payment_Plan__c` fieldPermissions)
  - `classes/TestDataFactory.cls` (+24 lines: `createAccount` +
    `createOpportunity`)

## Gotchas captured

No new gotchas from E08. Reinforces gotcha #31 (CLI quirks
workaround = sync runs + Tooling API queries).

## Implemented

**Commits**
See `git log --grep='E08'` for the commits that implemented this
epic (two: feat for the Apex + metadata, docs for this spec).

## Known follow-ups

- **Custom Setting sequence counter** — replace SOQL-count
  sequencing with a locked Custom Setting record per project per
  year. Defends against concurrent insert races. Worth doing
  before production go-live; SDO single-user demos don't hit the
  race.
- **Opportunity AccountId guard** — add a VR
  `Closed_Won_Requires_Account: NOT(ISBLANK(AccountId))` to
  prevent the cryptic `Primary_Buyer__c REQUIRED_FIELD_MISSING`
  error when Opp closes won without an Account. Quick win;
  bundle with E06b's other VRs in a polish pass.
- **`Transfer_Booking_To_Post_Sales_Queue` Flow** — now a no-op
  since BookingService sets the owner at insert time. Either
  deactivate the Flow (one-line metadata change) or leave as a
  fallback. Recommend keeping for now — robustness via
  belt-and-suspenders.
- **RecursionGuard.reset(key) method** — uncovered (`8/10` covered).
  Will get coverage when a consumer needs to explicitly reset a
  guard mid-transaction (e.g., a complex multi-phase trigger).
  Defer until real consumer.
- **TestDataFactory.createUser** — still uncovered (carryover
  from E06c). Will be covered when a future test class needs
  to test System.runAs(otherUser) scenarios. Defer.
- **E09 Payment Plan selection** — must populate
  `Booking.Payment_Plan__c` after Booking creation. Recommended:
  Quick Action on Booking → Update Record (Payment Plan picker).
  When E09 lands, audit any existing Bookings created without a
  Payment Plan and either backfill or flag.
- **Admin profile metadata-API normalisation** (gotcha #28)
  may surface `Booking__c.Payment_Plan__c` as a re-serialised
  block on the next Admin profile deploy. Cosmetic; safe to accept.
