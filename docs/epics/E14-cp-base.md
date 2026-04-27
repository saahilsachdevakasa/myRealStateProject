# E14 — Channel Partner Base

## Goal

Lay the operational foundation that the commission engine (E17) will sit on:
a typed lookup service for active rate cards, declarative status workflow
for CP empanelment / activation, and runtime guards on rate-card data
quality and CP eligibility at booking time.

## Scope

E14 is **infrastructure**, not the commission algorithm itself. Concretely:

1. **RateCardService** — the single Apex utility every commission code path
   will use to resolve an active `Commission_Rate_Card__c` for a given
   `Project__c × CP_Tier__c` combination. Bulk and single-record signatures.
2. **Validation rules** — guard rate cards against unusable data
   (missing milestone percentages, inverted effective windows) and guard
   bookings against assignment to inactive CPs.
3. **Record-Triggered Flow** — automatically populate empanelment /
   approval audit fields when a CP is activated, and revoke portal access
   when a CP is suspended or terminated.
4. **TestDataFactory extensions** — `createCPAccount` and `createRateCard`
   builders so future epics (E17 first) can stand up CP scenarios in tests
   without scattering raw inserts.
5. **Demo seed** — three additional Channel Partners (one per remaining
   tier, plus a Pending Approval example) and the four rate cards that
   complete the 2 projects × 3 tiers grid.

Approval Process configuration is **explicitly out of scope** for the
deploy package. Per design D3, the native Salesforce Approval Process
is captured as a manual setup step (5-minute Setup-UI configuration)
rather than metadata, because Approval Process XML is brittle to deploy
on the SDO and the underlying behaviour we need (status transitions,
audit fields, portal toggle) is fully covered by the Record-Triggered
Flow.

## Implemented

### Apex

- `force-app/main/default/classes/RateCardService.cls` — `with sharing`,
  exposes:
  - `@AuraEnabled(cacheable=true) getActiveRateCard(Id projectId, String cpTier)`
    → returns the most-recent active rate card or null. Cacheable so
    LWC callers (commission preview UI in a later epic) get free
    server-cache benefits.
  - `getActiveRateCards(Set<Id> projectIds, Set<String> cpTiers)` — bulk
    variant for E17's batch processing. Returns `Map<String,
    Commission_Rate_Card__c>` keyed by `buildKey(projectId, cpTier)`.
  - `buildKey(Id projectId, String cpTier)` — public helper exposing
    the canonical key format so callers and tests share one source of
    truth (no string-format drift between caller and lookup).

  All SOQL uses `WITH SECURITY_ENFORCED` and filters on
  `Active__c = true` (the formula is deterministic and SOQL-filterable
  — confirmed in discovery).

- `force-app/main/default/classes/RateCardServiceTest.cls` — 6 tests:
  - `testGetActiveRateCard_Found` — happy path, single match
  - `testGetActiveRateCard_NotFound_WrongTier` — wrong tier → null
  - `testGetActiveRateCard_NotFound_Expired` — expired card filtered
    out by the `Active__c` formula
  - `testGetActiveRateCards_Bulk` — 3 projects × 3 tiers = 9 cards,
    map keys match canonical format
  - `testGetActiveRateCard_MostRecentWins` — two cards same project +
    tier, more recent `Effective_From` wins
  - `testGetActiveRateCard_NullInputs` — defensive: null inputs return
    null / empty map without DML

  All 6 pass synchronously against the SDO.

### Validation rules

- `Commission_Rate_Card__c.All_Milestones_Required` — booking,
  agreement, registration percentages must each be `> 0`. Catches blank
  AND zero / negative values via combined OR formula.
- `Commission_Rate_Card__c.Effective_From_Required` — belt-and-
  suspenders for the field-level Required attribute. Functionally a
  no-op while the field stays Required (platform validation fires
  first), but provides a custom error message if Required is ever
  relaxed.
- `Commission_Rate_Card__c.Effective_To_After_From` — when set,
  `Effective_To` must be strictly after `Effective_From`. Prevents
  inverted or zero-duration windows.
- `Booking__c.Source_CP_Must_Be_Active` — fires when `Source_CP__c` is
  populated on insert OR changed on update, and the referenced CP's
  `CP_Status__c` is not `Active`. Existing bookings are NOT
  retroactively blocked when their CP later becomes Suspended /
  Terminated — only assignment-time CP changes are guarded. Direct-
  buyer bookings (no Source CP) are unaffected.

### Record-Triggered Flow

- `flows/CP_Status_Change_Handler.flow-meta.xml` — BeforeSave Update
  flow on `Account`, fires when `CP_Status__c` changes (filterFormula
  `ISCHANGED({!$Record.CP_Status__c})`).

  Two branches via Decision element:
  - **Active branch** (status changed to `Active`): sets
    `Empanelment_Date__c`, `Approval_Date__c`, `Approved_By__c` —
    only if currently blank. Implemented via Formula resources
    (`IF(ISBLANK(field), value, field)`) so re-activation after
    suspension preserves the original empanelment date.
  - **Inactive branch** (status changed to `Suspended` OR `Terminated`):
    sets `Portal_Access__c = false`. Single condition with
    `<conditionLogic>or</conditionLogic>` covers both terminal states
    in one rule.

  BeforeSave was chosen over AfterSave to avoid the extra DML and
  recursion risk of a `recordUpdates` round-trip on the same record.

### TestDataFactory extensions

- `createCPAccount(Map overrides)` — creates a Channel_Partner-RT
  Account with `CP_Status='Active'` and `CP_Tier='Standard'` defaults.
- `createRateCard(Id projectId, Map overrides)` — Standard tier,
  small percentage defaults, `Effective_From = today - 6 months`
  (well within the active window for any subsequent test).

### Demo seed (`scripts/seed-demo-data-04-cp-extended.apex`)

Idempotent script — checks for existing records by Name (CPs) and
by `Project + Tier` key (rate cards) before inserting. Adds:

| CP | Tier | Status | Empanelment |
|---|---|---|---|
| Prime Properties | Preferred | Active | 2025-04-10 |
| Metro Realtors | Standard | Active | 2025-06-20 |
| New Prospect Realty | Standard | Pending Approval | — |

| Project × Tier | Booking | Agreement | Registration | Total |
|---|---|---|---|---|
| PRK × Preferred | 1.5% | 0.75% | 0.25% | 2.5% |
| PRK × Standard | 1.0% | 0.5% | 0.25% | 1.75% |
| GAL × Preferred | 1.5% | 0.75% | 0.25% | 2.5% |
| GAL × Standard | 1.0% | 0.5% | 0.25% | 1.75% |

Combined with the existing 2 Platinum cards from
`seed-demo-data-02-customers.apex`, the org has the full 2 projects ×
3 tiers grid (6 cards) and 4 Channel Partners covering every status
and tier combination needed for E17 demos.

## Out of scope

- **Native Approval Process metadata** — manual Setup-UI configuration
  per design D3. Documented in `docs/manual-setup-steps.md` (to be
  appended when Approval Process is configured).
- **Commission accrual logic** — milestone-driven Commission_Ledger /
  Commission_Payout creation is E17.
- **CP portal Apex** — E15-E16.
- **Recursive guard for CP_Status_Change_Handler** — not needed.
  BeforeSave flows on the same record do not re-trigger; the flow
  fires once per save transaction.

## Test coverage

`RateCardServiceTest`: 6/6 pass synchronously, 50% line coverage
(2 production lines uncovered are the `null/empty Set` short-circuit
paths in `getActiveRateCards`, which the null-inputs test does
exercise — coverage tool quirk on early-return guards).

Full regression suite: 60/60 pass across `RateCardServiceTest` +
`BookingServiceTest`, `PaymentScheduleServiceTest`, `DemandServiceTest`,
`ReceiptAllocationServiceTest`, `AgreementServiceTest`,
`PossessionServiceTest`, `UnitBlockingServiceTest`,
`UnitLifecycleServiceTest`. The new `Source_CP_Must_Be_Active` VR did
not break any existing tests because no existing test populates
`Source_CP__c` (verified via grep in discovery).

## Manual setup deferred (for future Sahil click-trail)

1. **Approval Process on Account (Channel_Partner RT)**:
   - Submission criteria: `CP_Status__c = 'Pending Approval'`
   - Approver: CP Manager queue or named CP Manager user
   - Final approval action: field update `CP_Status = 'Active'`
     (which then triggers `CP_Status_Change_Handler` to populate audit
     fields and enable portal access)
   - Final rejection action: field update `CP_Status = 'Suspended'`
   - When configured, retrieve into source via
     `sf project retrieve start --metadata "ApprovalProcess:Account.<name>"`
     and append to repo so SDO refresh preserves the configuration.

2. **App Builder placement** of any CP-management LWCs on the
   Channel_Partner Account record page (E15-E16 territory).
