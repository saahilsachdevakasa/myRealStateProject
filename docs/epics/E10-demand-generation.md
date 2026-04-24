# E10 — Demand Generation Service and Naming Trigger

## Objective

E09 created `Booking_Payment_Schedule__c` rows (Status='Pending') from
the selected Payment Plan's milestones. E10 wires up the next step:
when a milestone trigger fires (a date arrives, a construction event
is logged, etc.), an invocable Apex action raises a `Demand__c`
record from the matching schedule row, computes GST and TDS per
Indian real-estate tax rules, and transitions the schedule row to
`Demand Raised`.

Two distinct Apex artefacts:
1. **`DemandService`** — invocable `raiseDemands(List<DemandRequest>)`
   that creates Demand records from selected schedule rows.
2. **`DemandTrigger`** + **`DemandNamingService`** — before-insert
   trigger that names new Demands as `DM-{BookingName}-{nn}` per the
   project's naming convention.

These are kept as separate concerns: DemandService is the business
logic (which schedule, what amounts, when due); the naming trigger
is purely a formatting layer that runs on every Demand insert
regardless of source (so future direct DML, Data Loader imports, or
other invocables also get correctly-named Demands without duplicating
naming logic).

## Dependencies

- **E02b** — `Demand__c` object with all 21 fields (Principal,
  GST, TDS, Status, Due_Date, etc. — including 4 formula fields:
  Net_Payable, Total_Gross, Outstanding, Days_Overdue).
- **E07** — `RecursionGuard.cls` exists. E10's BookingTriggerHandler-
  style guard is **not** used here because DemandTrigger is
  before-insert with no self-DML, matching E07's UnitTriggerHandler
  pattern.
- **E08** — Booking with `Agreement_Value__c` (= `Quoted_Gross_Value__c`)
  + `Total_Consideration__c` (= QGV + GST_Amount). DemandService reads
  both via SOQL traversal: `Booking__r.Agreement_Value__c`,
  `Booking__r.Total_Consideration__c`, plus
  `Booking__r.Unit__r.Tower__r.Project__r.CC_Received__c` (4-level)
  for the GST rate decision.
- **E09** — `Booking_Payment_Schedule__c` rows must exist with
  `Status__c = 'Pending'` before DemandService can act on them.
  PaymentScheduleService creates them from Payment Plan milestones
  when `Booking.Payment_Plan__c` is set.

## In scope

### 4 new Apex artefacts

- **`triggers/DemandTrigger.trigger`** — thin trigger, before-insert
  only, 7 lines.
- **`classes/DemandTriggerHandler.cls`** — routes `BEFORE_INSERT` →
  `DemandNamingService.onBeforeInsert`. **No RecursionGuard** —
  before-insert with no self-DML doesn't need it (matches
  `UnitTriggerHandler` from E07).
- **`classes/DemandNamingService.cls`** — bulk-queries parent
  `Booking__c.Name` (because `Booking__r` is unavailable in
  before-insert context), then sets each Demand's `Name` to
  `DM-{BookingName}-{seq:02}` from `Demand_Seq__c`. Bulkified
  (single SOQL for all parents in the batch).
- **`classes/DemandService.cls`** — `@InvocableMethod
  raiseDemands(List<DemandRequest>) → List<Id>`. 6-step bulkified
  service:
  1. **Query** schedule rows with full Booking/Unit/Tower/Project
     traversal (`CC_Received__c` for GST, `Total_Consideration__c`
     for TDS).
  2. **Validate** all schedules exist and `Status__c = 'Pending'`;
     throws `AuraHandledException` with the actual status if not.
  3. **Count** existing Demands per Booking (single AggregateResult
     SOQL with GROUP BY) for sequence numbering. In-memory increment
     for bulk requests on the same Booking.
  4. **Compute** GST and TDS per record:
     - **GST rate**: `0%` if `Project.CC_Received__c = true` (post-CC),
       else `1%` if `Booking.Agreement_Value__c <= ₹45L` (affordable
       housing), else `5%` (under-construction standard).
     - **TDS rate**: `1%` if `Booking.Total_Consideration__c > ₹50L`,
       else `0%`. (Income Tax Act §194IA simplified.)
  5. **Insert** new Demands (DemandTrigger before-insert sets Names).
     Service does NOT set the 4 formula fields (Net_Payable,
     Total_Gross, Outstanding, Days_Overdue) — they compute
     automatically.
  6. **Update** schedule rows: `Status='Demand Raised'`,
     `Demand_Raised_Date=today`, `Actual_Demand=newDemand.Id`.
- **`classes/DemandServiceTest.cls`** — 6 test methods covering
  happy path, already-raised rejection, sequential numbering,
  GST=0 post-CC, TDS=0 below threshold, bulk operation (5 schedules
  → 5 demands).

### 1 modified file

- **`classes/TestDataFactory.cls`** — added `createDemand(Id bookingId,
  Id scheduleId, Map<String, Object> overrides) → Demand__c`. Sets all
  required fields + `Demand_Seq__c=1` + `Booking__c=bookingId` so the
  trigger can compute Name. Does NOT set Name (trigger handles it).

## Out of scope (deferred)

- **Demand Letter PDF generation.** E10 sets `PDF_Generated__c = false`
  and `Sent_To_Buyer__c = false`. PDF rendering and email/buyer-portal
  delivery move to **E12** (Visualforce PDF + ESign / notification
  consolidated work).
- **Quick Action on Booking** ("Raise Demand" button that surfaces
  pending schedule rows for selection). The invocable is ready to be
  wired via Screen Flow / LWC; UX wiring deferred to a layout-polish
  pass.
- **Scheduled Flow** that auto-raises demands on time-based milestones
  reaching their `Expected_Date`. Out of scope; manual or programmatic
  invocation is sufficient for MVP demo.
- **Construction milestone date resolution** — E09 left
  `Expected_Date__c = null` for Construction/Possession trigger types.
  E11+ owns the logic to populate these when the underlying construction
  event is logged. Demands raised before that resolution use today + 15
  due-date computation regardless.
- **Status auto-transitions** — `Raised → Partial → Paid` from receipt
  application is **E11**'s responsibility. `Raised → Overdue` from a
  scheduled job is also E11+. E10 leaves Status as `Raised` after
  creation.
- **Interest accrual** — `Interest_Applicable__c` and
  `Interest_Accrued__c` exist on Demand but are out of E10 scope.

## Decisions locked

- **D1 — Invocable, not auto-trigger.** Demands aren't auto-generated
  on Booking creation. They're raised by user action or scheduled
  process when a milestone triggers. The invocable surface lets us
  wire to Quick Action, Screen Flow, Scheduled Flow, or direct Apex
  uniformly.
- **D2 — Naming via separate before-insert trigger.** Keeps naming
  logic out of `DemandService` so direct DML / data import paths get
  the same names. Aligns with the "one trigger per object,
  service-class-routed" framework.
- **D3 — Sequence via SOQL count + in-memory increment.** Same
  pattern as E08 BookingService (per-project-per-year count).
  Race-vulnerable on concurrent inserts, fine for SDO single-user
  demos; document as a Phase-2 hardening item.
- **D4 — GST simplification: 3-bracket model.** 0% / 1% / 5%. Real
  Indian GST has more conditions (commercial vs residential RM, ITC,
  state vs central, etc.). The 3-bracket model is enough for demo
  narrative; production would replace with a Custom Metadata Type
  rate-card lookup.
- **D5 — TDS simplification: §194IA single threshold.** 1% if
  `Total_Consideration > ₹50L`, else 0%. Real TDS has more rules
  (NRI seller, HUF, joint ownership, etc.). Demo-acceptable.
- **D6 — `AuraHandledException` for validation failures.**
  Surfaces cleanly to LWC/Flow callers; matches UnitBlockingService
  pattern (E06c).
- **D7 — Service does NOT set formula fields** (Net_Payable,
  Total_Gross, Outstanding, Days_Overdue) — verified during discovery.
  Salesforce computes them from the source fields the service does set.
- **D8 — `createDemand` factory does NOT set Name.** Tests (and any
  other caller) rely on the trigger to compute the canonical
  `DM-{BookingName}-{nn}` name from `Demand_Seq__c` + `Booking__c`.
  Forces the naming logic to live in one place.

## Acceptance criteria

1. **DemandTrigger active.**
2. **3 new Apex classes active** — `DemandTriggerHandler`,
   `DemandNamingService`, `DemandService` (+test class).
3. **TestDataFactory updated** with `createDemand` builder.
4. **All 32 tests pass** — 6 new (DemandService) + 5 (PaymentSchedule)
   + 5 (BookingService) + 5+1 (UnitBlocking) + 9+1 (UnitLifecycle).
5. **Coverage:**
   - DemandService: **96%** (3 defensive null-check lines uncovered;
     exceeds 90% target).
   - DemandNamingService: **100%**.
   - DemandTrigger / DemandTriggerHandler: **100%**.
6. **Demand Names follow `DM-{BookingName}-{nn}` convention** —
   verified by tests asserting `Name.endsWith('-01')`, `-02`, etc.

## Iteration story

| Step | Outcome |
|---|---|
| Dry-run | Green — 4 Created + 17 Unchanged |
| Real deploy | Green — 21 components (CLI cosmetic "Missing message" per gotcha #31; deploy report --json confirmed) |
| Test run 1 | 31/32 pass — 1 failure: `testRaiseDemand_AlreadyRaised_Rejected` used Project Code `'AR1'` (digits violate `Project_Code_Format` VR `^[A-Z]{3}$`) |
| 1-line fix: `'AR1'` → `'ARJ'` | — |
| Redeploy | Green — 21 components |
| Test run 2 | 32/32 pass |
| Sync coverage run | DemandService 96%, DemandNamingService/Trigger/Handler 100% |

The `'AR1'` bug is the **third** instance of the same gotcha class in
this project's history (E08's bulk test had `'BK1'`-`'BK5'` →
`'BKA'`-`'BKE'`; E09's bulk had `'BK1'`-`'BK5'` → `'BKA'`-`'BKE'`;
E10's already-raised had `'AR1'` → `'ARJ'`). All three were one-line
fixes caught at first test run. CLAUDE.md gotcha #41 (or worth
adding to existing #30) could codify the pattern: **any TestDataFactory
caller passing a Project_Code must use 3 uppercase letters with no
digits**.

## Files produced

**New (5 + meta = 10 files):**
- `triggers/DemandTrigger.trigger` (+meta)
- `classes/DemandTriggerHandler.cls` (+meta)
- `classes/DemandNamingService.cls` (+meta)
- `classes/DemandService.cls` (+meta)
- `classes/DemandServiceTest.cls` (+meta)

**Modified (1 file):**
- `classes/TestDataFactory.cls` — `+createDemand` builder
  (+18 lines).

## Gotchas captured

No new gotchas. E10 hit only known classes:
- **#30** (Required Project_Code format VR — third instance of the
  same TestDataFactory misuse; pattern documented in iteration story
  above for future reference).
- **#31** (CLI v2.84.6 deploy reporting bug; standard
  `deploy report --json` workaround).

## Implemented

**Commits**
See `git log --grep='E10'` for the commits that implemented this
epic (two: feat for the Apex, docs for this spec).

## Known follow-ups

- **E11**: Receipt allocation against Demands; Status auto-transitions
  (Raised → Partial → Paid → Overdue). Currently Demand stays at
  `Raised` after creation regardless of receipt allocations.
- **E12**: Demand Letter PDF generation via Visualforce; email/buyer-
  portal delivery; flips `PDF_Generated__c` and `Sent_To_Buyer__c`.
- **Quick Action on Booking** — "Raise Demand" UX. List of pending
  schedule rows → user picks one → calls invocable. Defer to
  layout-polish epic.
- **Scheduled Flow** — auto-raise demands on time-based milestones
  reaching `Expected_Date`. E10's invocable design supports this
  cleanly; just needs the Flow trigger.
- **GST Custom Metadata** — replace the 3 hard-coded constants in
  DemandService with a `GST_Rate_Card__mdt` lookup so demo can change
  rates without redeploying Apex. Phase 2 polish.
- **Construction milestone date resolution** — E11+ should populate
  schedule `Expected_Date__c` for Construction/Possession trigger
  types when the underlying event is logged. E10 demands raised
  before that use today + 15 due-date.
- **Concurrent demand-creation race** — current SOQL-count sequencing
  is not safe for concurrent invocations on the same Booking. Replace
  with a locked Custom Setting counter or platform sequence in Phase
  2. SDO single-user demo doesn't hit the race.
