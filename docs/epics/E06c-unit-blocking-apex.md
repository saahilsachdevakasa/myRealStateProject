# E06c — Unit Blocking Invocable Apex + TestDataFactory

## Objective

Land the first Apex code of the project. Ship a bulkified invocable
service (`UnitBlockingService`) that sets a Unit to `Blocked` status
with a timed expiry, backed by a test class that exercises happy
path, bulk, error, and already-blocked scenarios. Along the way,
establish the `TestDataFactory` utility that every subsequent Apex
test in the project will depend on.

E06c is the **third** of three E06 sub-phases (E06a stages/BPs,
E06b validation/path/concession action, E06c Apex). It closes out
E06 and establishes the Apex patterns (flat `classes/` layout,
bulkified invocable methods, TestDataFactory with Map<String,Object>
overrides, parent-derived-value computation in test factories) that
every future Apex epic must follow.

## Dependencies

- **E02a** complete — Inventory cluster objects (Project/Tower/Unit)
  with the validation rules that TestDataFactory must honour
  (`Tower_Name_Matches_Code`, `Floor_In_Range`, `Unit_Number_In_Range`,
  `Project_Code_Format`).
- **E05b** complete — Admin profile FLS grants allow the test user
  to read Unit__c fields; SOQL visibility is not blocked.
- **E06a** complete — only for E06c's narrative flow (Opportunity
  stages exist). No direct dependency.
- **E06b** complete — only for the sub-phase sequencing.

## In scope

### 3 Apex classes (flat `classes/` layout)

- **`UnitBlockingService.cls`** — `public with sharing` service
  with one inner `BlockRequest` class and one `@InvocableMethod`:
  - Bulkified: accepts `List<BlockRequest>`; a single SOQL loads
    all target units, a single DML updates all.
  - Inputs via `@InvocableVariable`: `unitId` (Id, required),
    `durationHours` (Integer, required).
  - Logic: query `Unit__c WHERE Id IN :unitIds WITH SECURITY_ENFORCED`,
    throw `AuraHandledException('Unit not found.')` if any unitId
    doesn't resolve, otherwise set `Unit_Status__c='Blocked'`,
    `Blocked_By__c=UserInfo.getUserId()`,
    `Blocked_Until__c=System.now().addHours(durationHours)`, and
    `Database.update(toUpdate, true)` for all-or-nothing DML.
  - No state-machine (E07) — happy-path only.

- **`TestDataFactory.cls`** — utility (not @IsTest) with 5 static
  builder methods:
  - `createProject(Map<String,Object>)` → `Project__c`
  - `createTower(Id, Map<String,Object>)` → `Tower__c`
  - `createUnit(Id, Map<String,Object>)` → `Unit__c`
  - `createUnits(Id, Integer, Map<String,Object>)` → `List<Unit__c>`
    (bulk helper for 1..N units)
  - `createUser(String, Map<String,Object>)` → `User` (profile
    lookup, millisecond-timestamp unique username)
  - Plus two private helpers: `applyOverrides` and `toInt`.

- **`UnitBlockingServiceTest.cls`** — `@IsTest(SeeAllData=false)`
  with `@TestSetup` (Project + Tower), 4 `@IsTest` methods:
  `testBlockUnit_HappyPath`, `testBlockUnit_UnitNotFound` (uses
  create-then-delete to get a guaranteed-missing Id),
  `testBlockUnit_BulkOperation` (200 units), `testBlockUnit_AlreadyBlocked`.

### Coverage

- `UnitBlockingService`: **100%** (target 90%, actual 18/18 lines).
- `TestDataFactory`: 77% — uncovered lines are `createUser` (not
  exercised by E06c) and the commercial-tower code branch. Will
  rise as other epics exercise those paths.

## Out of scope (deferred)

- **Block_Unit Screen Flow** — Screen Flow XML is too finicky to
  generate reliably on the first pass. Deferred to **E06-layout**
  (the future layout/UX sub-phase that also handles Dynamic Forms
  and page-layout edits). The invocable service is ready to be
  called from any Screen Flow; only the Flow wrapper is deferred.
- **Block_Unit Quick Action on Opportunity** — follows the Flow;
  same deferral.
- **UnitBlockingService state-machine validation** — rejecting
  `Block` calls on already-Booked or Cancelled units, enforcing
  transitions per the Phase 1 spec. Moves to **E07**
  (Unit Status Lifecycle), which is the epic that owns the
  state-machine.

## Decisions locked

- **D-APEX-PATH — flat `classes/` layout.** No subfolders. All
  3 classes live directly under
  `force-app/main/default/classes/`. PROJECT_CONTEXT.md and CLAUDE.md
  are authoritative; any docx reference to `classes/services/` or
  `classes/tests/` is superseded.
- **D-INVOCABLE-API — bulkified.** `blockUnit(List<BlockRequest>)`
  is the project convention (CLAUDE.md non-negotiable #10 — all
  public service methods take `List<SObject>`). Flow Builder calls
  the method one-at-a-time; Apex still takes the list.
- **D-TESTFACTORY-QUERY — parent-derived values computed before insert.**
  Tower__c has a `Tower_Name_Matches_Code` validation rule that
  enforces `Name = Project_Code + "-T" + padded(Tower_Number)`.
  `createTower` queries the parent `Project_Code__c` and computes
  the expected Name before insert. Same pattern applied to
  `createUnit` / `createUnits` for Unit Name (convention, no VR).
- **D-TEST-ISOLATION — @TestSetup for shared parents.** Project
  + Tower created once in @TestSetup; each @IsTest method creates
  its own Unit(s) under that Tower. Salesforce rolls back to the
  setup state between methods, so tests don't interfere.
- **D-FLOW-DEFERRAL — Screen Flow + Quick Action deferred.**
  Per D6/D7; scope of E06c is the Apex deliverable. Flow moves
  to E06-layout.

## Acceptance criteria

1. **3 Apex classes deployed** — `UnitBlockingService`,
   `UnitBlockingServiceTest`, `TestDataFactory` all `Status=Active`
   on the org at API 62. Verified via Tooling API.
2. **All 4 test methods pass** — happy path, not-found error,
   bulk (200), already-blocked. Verified via
   `SELECT Outcome FROM ApexTestResult`.
3. **UnitBlockingService coverage ≥ 90%** — actual 100% (18/18
   lines). Verified via synchronous test run with `--code-coverage`.
4. **Bulk path exercises 200-record DML** — no per-record SOQL
   or DML. Service body has one SOQL, one DML, bulkified for N
   requests.
5. **Service throws `AuraHandledException` on missing Unit** —
   verified in `testBlockUnit_UnitNotFound`.

## Manual verification (post-deploy, E23 rehearsal hook)

- Once E06-layout lands the Block_Unit Screen Flow, launch it from
  an Opportunity record page; confirm a Unit's status flips to
  Blocked in real time and `Blocked_Until` = now+72h.
- Until then, the service can be verified via anonymous Apex:
  ```apex
  Unit__c sample = [SELECT Id FROM Unit__c WHERE Unit_Status__c = 'Available' LIMIT 1];
  UnitBlockingService.BlockRequest r = new UnitBlockingService.BlockRequest();
  r.unitId = sample.Id;
  r.durationHours = 72;
  UnitBlockingService.blockUnit(new List<UnitBlockingService.BlockRequest>{ r });
  ```

## Iteration story

| Attempt | Result | Class |
|---|---|---|
| Dry-run 1 (3 classes) | Green — 3/3 Validated (Deploy ID `0AfHp00003nOUA8KAO`, 3.59s) | — |
| Real deploy 1 with `--test-level RunSpecifiedTests` | CLI emitted "Missing message metadata.transfer:Finalizing" mid-deploy; classes persisted (verified via `sf project deploy report`) but test phase didn't execute. | NEW (gotcha #31) — CLI v2.84.6 bug |
| Async test run 1 | FAILED — 5/5 (setup + 4 tests) hit `Tower_Name_Matches_Code` validation rule because `createTower` didn't compute Name. | NEW (gotcha #30) — TestDataFactory must honour VRs |
| TestDataFactory fix (compute Name on Tower/Unit from parent values) | — | — |
| Redeploy (NoTestRun) | Green — 3/3 Deployed (Deploy ID `0AfHp00003nOU9fKAG`). Same CLI cosmetic error; `deploy report --json` confirmed success. | — |
| Sync test run with coverage | Green — 4/4 passed; UnitBlockingService = 100%; TestDataFactory = 77%; total 4.1s | — |

## Files produced

- `force-app/main/default/classes/UnitBlockingService.cls` +
  `.cls-meta.xml` (API 62.0, Active)
- `force-app/main/default/classes/UnitBlockingServiceTest.cls` +
  `.cls-meta.xml` (API 62.0, Active)
- `force-app/main/default/classes/TestDataFactory.cls` +
  `.cls-meta.xml` (API 62.0, Active)

## Gotchas captured (now in CLAUDE.md)

- **#30** — `TestDataFactory` must compute parent-derived values
  before insert on every object that has a validation rule
  depending on them. Specifically, `Tower__c.Tower_Name_Matches_Code`
  requires `Name = Project_Code + "-T" + paddedTowerNumber`
  (or `-B` for commercial). The naive `new Tower__c(Project__c=...,
  Tower_Type__c=...)` without a computed Name fails at insert with
  `FIELD_CUSTOM_VALIDATION_EXCEPTION`. Pattern: in factories,
  query the parent for its code/name fields and compute the
  derived value in Apex before DML. Applies to any object where
  Name is a plain Text field but a VR enforces a format.

- **#31** — Salesforce CLI v2.84.6 (on this dev machine) has two
  known issues with Apex deploys: (a) during `sf project deploy
  start` with `--test-level RunSpecifiedTests`, the CLI exits with
  "Missing message metadata.transfer:Finalizing for locale en_US"
  while the underlying deploy succeeds — `sf project deploy report
  --job-id <id>` confirms the true status; (b) `sf apex get test -i
  <id>` and `sf apex run test --result-format human` sometimes
  error with `Cannot read properties of null (reading 'Id')`. Workaround:
  query `ApexTestResult` and `ApexCodeCoverageAggregate` directly
  via Tooling API:
  ```bash
  sf data query --use-tooling-api --query "SELECT MethodName, Outcome, Message FROM ApexTestResult WHERE AsyncApexJobId = '<job>' ORDER BY MethodName"
  ```
  Alternatively, run tests with `--synchronous --code-coverage` —
  the human-readable table still prints at the end despite the CLI
  errors being thrown along the way. CLI upgrade (2.84.6 → 2.130.9)
  may resolve but requires testing against this SDO before
  adopting.

## Implemented

**Commits**
See `git log --grep='E06c'` for the commits that implemented this
epic (two: feat for the 6 class files, docs for this file +
CLAUDE.md gotchas #30 and #31).

## Known follow-ups

- **E06-layout** — Block_Unit Screen Flow + Quick Action wrapping
  this service. Also Dynamic Forms flexipage + Path placement on
  Opp record pages.
- **E07** — Unit Status Lifecycle state-machine (validates
  transitions like Blocked → Available / Booked, enforces expiry
  behaviour). UnitBlockingService will be extended rather than
  rewritten; the state-machine guards layer on top.
- **TestDataFactory maturity** — current version covers Project,
  Tower, Unit, Units (bulk), User. As future epics need
  Opportunity, Lead, Account, Booking, Payment Plan, etc., add
  builders here rather than inlining DML in each test class. Keep
  the same Map<String,Object>-override pattern.
- **CLI version upgrade** — gotcha #31. If we upgrade the dev
  machine's CLI, re-run E06c tests against it and delete the
  gotcha if resolved.
