# E07 — Unit Status Lifecycle State Machine

## Objective

Enforce the Unit status state machine via Apex trigger, write
append-only audit history, and establish the trigger-handler pattern
that every future object-level automation in the project will follow.

Before E07, `UnitBlockingService` (from E06c) could flip any Unit to
`Blocked` regardless of current status. After E07:

- Only the 5 declared transitions are allowed (Available→Blocked,
  Blocked→Available/Booked, Booked→Cancelled, Cancelled→Available);
  all other transitions are rejected with a clear error message.
- Every legitimate status change appends an audit line to
  `Status_History__c` (timestamp, user id, old→new).
- `Last_Status_Change__c` timestamp is set on every legitimate change.
- Transitioning to `Available` auto-clears `Blocked_By__c`,
  `Blocked_Until__c`, and `Active_Booking__c` — used by manual
  releases and by the future auto-release Scheduled Flow.

E07 is the project's **first Apex trigger**. The thin-trigger +
handler + service split established here is the pattern for every
future trigger (Booking in E08, Demand in E10, Receipt in E11, etc.).

## Dependencies

- **E02a** complete — Unit__c, its status picklist, and the 6 fields
  the state machine touches (`Unit_Status__c`, `Blocked_By__c`,
  `Blocked_Until__c`, `Status_History__c`, `Last_Status_Change__c`,
  `Active_Booking__c`) all exist.
- **E05b** complete — Admin profile FLS grants allow the running
  user to read/write all six state-machine fields from Apex context.
- **E06c** complete — `UnitBlockingService` exists; E07 adds a
  pre-check on top of it to emit a friendlier error than the raw
  trigger addError when an RM tries to block a Booked/Cancelled unit.

## In scope

### 4 new Apex artefacts

- **`triggers/UnitTrigger.trigger`** — thin trigger on Unit__c,
  before update only. 7 lines. No business logic; delegates to the
  handler. Establishes the "one trigger per object" convention.

- **`classes/UnitTriggerHandler.cls`** — routes by
  `TriggerOperation` to service methods. Currently routes only
  `BEFORE_UPDATE` → `UnitLifecycleService.onBeforeUpdate`. As
  future epics add before/after hooks, this handler grows new
  branches.

- **`classes/UnitLifecycleService.cls`** — the state machine
  itself. Single `onBeforeUpdate(List<Unit__c>, Map<Id, Unit__c>)`
  static method. Holds the transitions map as a `private static
  final Map<String, Set<String>>` (5 declared transitions). For
  each record with a status delta: validates the transition,
  writes the audit line, sets `Last_Status_Change__c`, clears
  stale fields on → Available. Bulkified (no per-record SOQL or
  DML).

- **`classes/RecursionGuard.cls`** — simple static utility
  (`isFirstRun(key)`, `reset(key)`, `@TestVisible resetAll()`).
  Shipped now as a utility establishing the pattern; **not used
  by UnitTriggerHandler**. See decision D-RECURSION below.

### 2 modifications

- **`UnitBlockingService.cls`** — added a 7-line pre-check after
  the unit-found check. If `Unit_Status__c` is neither `Available`
  nor `Blocked`, throw
  `AuraHandledException('Cannot block unit <id>: current status
  is <status>. Only Available or Blocked units can be blocked.')`.
  Rationale: the trigger's `addError` fires too, but a service-level
  pre-check emits a more actionable message to callers (and aborts
  before issuing the DML).

- **`UnitBlockingServiceTest.cls`** — added
  `testBlockUnit_BookedUnit_Rejected` to verify the new pre-check.
  Existing 4 tests untouched; they still pass after the service
  pre-check is added (all still create Available or Blocked units).

### 1 new test class

- **`classes/UnitLifecycleServiceTest.cls`** — 9 test methods
  covering all 5 valid transitions (one each), 2 invalid transitions
  (Available→Booked, Booked→Blocked), a multi-transition chain
  (4 sequential updates, verifies 4 history lines), and a bulk
  transition (200 units in one DML, verifies trigger bulkification).
  Uses `TestDataFactory` and a private `createUnitWithStatus(status)`
  helper.

## Out of scope (deferred)

- **Release_Expired_Blocks Scheduled Flow** — deferred to manual
  Setup. Spec captured below under "Manual Setup steps". Apex state
  machine is the load-bearing deliverable; the Scheduled Flow is
  convenience automation and can land any time.
- **Unit deletion handling** — currently Unit__c deletion cascades
  through the MD relationship from Tower__c. No special logic in the
  trigger for delete ops. If future epics need Unit soft-delete or
  audit on delete, revisit here.
- **State machine for other objects** — Booking status lifecycle,
  Demand status, Commission ledger states, etc. — each gets its
  own epic with its own service class and (where needed) its own
  trigger. The pattern from E07 is reusable.

## Decisions locked

- **D-RECURSION — Option 1: ship RecursionGuard, don't use it in
  UnitTriggerHandler.** Before-update triggers that mutate
  `Trigger.new` in-place and perform no DML on the trigger's own
  object have no self-re-entry risk, so no guard needed. Using
  `isFirstRun(key)` *would* break `testStatusHistory_MultipleTransitions`
  because Apex static state persists across DMLs within a
  transaction — the guard would silently skip trigger-processing on
  the 2nd, 3rd, 4th sequential DML. `RecursionGuard.cls` is still
  shipped because E08+ after-triggers (booking creation,
  commission ledger) will do DML on related objects and WILL need
  the guard. Documenting the pattern up front is worth the small
  coverage gap (see follow-ups).

- **D-STATE-MACHINE — 5 declared transitions only.** `Available →
  Blocked`, `Blocked → Available`, `Blocked → Booked`, `Booked →
  Cancelled`, `Cancelled → Available`. Everything else rejected.
  Deliberately excluded: `Available → Cancelled` (cancellation
  implies a prior booking), `Booked → Available` (must go through
  Cancelled first for audit trail).

- **D-HISTORY-FORMAT — append-only text, newline-separated.**
  `yyyy-MM-dd HH:mm | <userId> | <oldStatus> → <newStatus>`.
  Stored in `Status_History__c` (LongTextArea 32,768 chars, ~650
  transitions before overflow). Append via
  `existing + '\n' + newLine` with `String.isBlank(existing)`
  null-handling.

- **D-FIELD-CLEARING — only on transition to Available.** Clears
  `Blocked_By__c`, `Blocked_Until__c`, `Active_Booking__c`. Other
  transitions leave unrelated fields alone (service classes are
  responsible for setting them).

- **D-ERROR-LEVEL — record-level `addError(msg)`.** Chosen over
  field-level `u.Unit_Status__c.addError(msg)` because field-level
  syntax on restricted picklists is historically flaky across API
  versions. Record-level errors show at the top of the record page
  with the full error message — universal and clear.

- **D-API-VERSION — 62.0 for all new classes and the trigger.**
  Matches E06c's established default.

## Acceptance criteria

1. **UnitTrigger active** — `SELECT Status FROM ApexTrigger WHERE
   Name='UnitTrigger'` returns `Active`.
2. **4 new Apex classes active** — `UnitTriggerHandler`,
   `UnitLifecycleService`, `RecursionGuard`, `UnitLifecycleServiceTest`
   all `Status=Active`, API 62.
3. **2 modified Apex classes still active** — `UnitBlockingService`,
   `UnitBlockingServiceTest` re-deployed with their changes.
4. **All 14 tests pass** — 5 in `UnitBlockingServiceTest` (existing
   4 + new Booked-rejection), 9 in `UnitLifecycleServiceTest`.
5. **Coverage ≥ 85% on every service/handler/trigger class.**
   Actual:
   - UnitBlockingService: **100%**
   - UnitLifecycleService: **100%**
   - UnitTriggerHandler: **100%**
   - UnitTrigger: **100%**
   - TestDataFactory: 77% (below target — carryover from E06c;
     uncovered paths are `createUser` and commercial-tower branch,
     both unexercised by current tests)
   - RecursionGuard: 0% (deliberately — no consumer yet; covered
     when E08+ uses it)
6. **Existing `UnitBlockingServiceTest` behaviour unchanged.** The
   `testBlockUnit_AlreadyBlocked` test still passes post-E07: the
   trigger sees Blocked→Blocked (no status change), skips validation
   and history write, the DML re-saves Blocked_By and Blocked_Until.

## Manual verification (post-deploy, E23 rehearsal hook)

1. Find an Available Unit, edit via Lightning record page, set
   status to `Booked`. Save should fail with "Invalid status
   transition: Available → Booked. Allowed: Available→Blocked;
   Blocked→Available/Booked; Booked→Cancelled; Cancelled→Available".
2. Find a Blocked Unit, set status to `Available`. Save should
   succeed; Blocked_By, Blocked_Until, Active_Booking should clear;
   Status_History should show the new line with timestamp + user
   + arrow.
3. After several transitions on the same unit, Status_History
   should grow by one line per valid transition, never shrink.

## Iteration story

| Attempt | Components | Tests | Result |
|---|---|---|---|
| Dry-run 1 (all 8 classes + trigger) | 9 components: 5 Created, 2 Changed, 2 Unchanged | Skipped | Green, 5.x s, Deploy ID `0AfHp00003nOU...` |
| Real deploy 1 (NoTestRun) | 8 components deployed (Unchanged ones skipped in this report) | N/A | Succeeded — CLI cosmetic "Missing message" error per gotcha #31; `deploy report --json` confirmed Status=Succeeded, 0 errors |
| Async test run 1 (both classes) | — | 14/14 pass (5 UBS + 9 ULS, plus 2 setup=Pass) | Green, 100% pass rate |
| Sync run 1 (UnitLifecycleServiceTest, coverage) | — | 9/9 pass | 100% coverage on trigger + handler + service |
| Sync run 2 (UnitBlockingServiceTest, coverage) | — | 5/5 pass | 100% coverage on UnitBlockingService |

No deploy retries. No test failures after correct TestDataFactory
spec from E06c.

## Files produced

- **New (6 files):**
  - `force-app/main/default/triggers/UnitTrigger.trigger` + meta
  - `force-app/main/default/classes/UnitTriggerHandler.cls` + meta
  - `force-app/main/default/classes/UnitLifecycleService.cls` + meta
  - `force-app/main/default/classes/RecursionGuard.cls` + meta
  - `force-app/main/default/classes/UnitLifecycleServiceTest.cls` + meta
  - (Plus the 6 `.cls-meta.xml` / `.trigger-meta.xml` files.)

- **Modified (2 files):**
  - `force-app/main/default/classes/UnitBlockingService.cls` —
    +7-line pre-check
  - `force-app/main/default/classes/UnitBlockingServiceTest.cls` —
    +23 lines, new `testBlockUnit_BookedUnit_Rejected` test

## Manual Setup steps (Scheduled Flow deferral)

The Release_Expired_Blocks automation is deferred to manual Setup.
Spec to reproduce in Flow Builder on the next SDO session (or
whenever UI wiring is prioritised):

- **Type:** Scheduled-Triggered Flow (not Record-Triggered, not
  Screen)
- **API Name:** `Release_Expired_Blocks`
- **Object:** `Unit__c`
- **Entry conditions:**
  `Unit_Status__c = 'Blocked' AND Blocked_Until__c < {!$Flow.CurrentDateTime}`
- **Schedule:** Hourly. (Salesforce's minimum interval for
  Scheduled-Triggered Flows is 1 hour; 15-minute scheduling is not
  supported for this Flow type.)
- **Actions per matched record:**
  - Update Records: set `Unit_Status__c = 'Available'`,
    `Blocked_By__c = null`, `Blocked_Until__c = null`.
- **Side-effect via trigger:** UnitTrigger fires on the update,
  validates `Blocked → Available` (allowed), writes audit history
  line ("expired block" semantics derived from the Flow's user
  context — typically the Automated Process user), sets
  `Last_Status_Change__c`, clears `Active_Booking__c`.

Add to `docs/manual-setup-steps.md` on the next update pass if
this Flow isn't landed soon.

## Gotchas captured

No new gotchas from E07. CLI quirks (gotcha #31) reprised —
reinforcing the workaround: sync test runs + direct Tooling API
queries for coverage.

## Implemented

**Commits**
See `git log --grep='E07'` for the commits that implemented this
epic (two: feat for the Apex deliverable, docs for this spec).

## Known follow-ups

- **RecursionGuard coverage.** Currently 0% because
  UnitTriggerHandler doesn't call it (D-RECURSION). When E08
  lands the first after-trigger with self-DML risk (e.g., BookingTrigger
  updating Unit on Closed Won insert), that epic should include
  `RecursionGuardTest.cls` covering `isFirstRun`, `reset`, and
  `resetAll`. Alternatively, add the minimal test now as a
  one-commit follow-up if per-class coverage is enforced earlier.
- **TestDataFactory coverage gap unchanged from E06c.** 77% still
  — `createUser` and commercial-tower branch unexercised. Rises as
  future epics need those builders.
- **Scheduled Flow landing.** Per the manual-Setup spec above, or
  rolled into E06-layout when UI automation gets batch attention.
- **Field-level error messages.** Current implementation uses
  record-level `addError`. If UX feedback prefers field-highlighted
  errors on the Status picklist specifically, revisit D-ERROR-LEVEL
  and test field-level syntax empirically on the current API version.
- **Audit history format.** If future reporting needs machine-parseable
  history (e.g., dashboards on transition counts per status), the
  plain-text `Status_History__c` will need to be restructured
  (maybe a child object `Unit_Status_History__c`). E07 ships the
  simpler text format; restructure later if reporting needs arise.
- **UserInfo.getUserId() in tests.** Test asserts `Blocked_By__c ==
  UserInfo.getUserId()` — the running user in Apex tests is always
  the user invoking the test. For `System.runAs()` scenarios (future
  persona-specific tests), `Blocked_By__c` will reflect the runAs
  user, not the test invoker. Document as an expected behaviour
  when persona tests land.
