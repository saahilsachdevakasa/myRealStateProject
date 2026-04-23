# E06a — Opportunity Stages and Business Processes

## Objective

Establish Opportunity stage customisation and record-type-scoped
BusinessProcesses for the residential vs commercial pre-sales funnels.
After E06a, RMs creating an Opportunity see only the stages relevant
to their property type, and the org's StandardValueSet carries the
6 demo-narrative stages alongside the SDO's stock stages so other
RTs (SimpleOpportunity, ChannelPartner) keep working as-is.

E06a is the **first** of three E06 sub-phases (E06a stages/BPs,
E06b dynamic forms/validation/Path/concession action,
E06c UnitBlocking Apex/Flow/tests).

## Dependencies

- **E02b** complete — `Pre_sales_Residential` and
  `Pre_sales_Commercial` Opportunity record types already exist with
  the placeholder `Pre_Sales_Process` BP reference.
- **E05b** complete — Admin profile baseline carries FLS on all custom
  Opportunity fields; new picklist values inherit visibility through
  StandardValueSet (no FLS needed on system-standard `StageName`).

## In scope

### StandardValueSet augmentation
- 6 new active values added to `OpportunityStage`:
  - `New` (Pipeline, prob 10)
  - `Qualified` (Pipeline, prob 25)
  - `Site Visit Scheduled` (Pipeline, prob 40)
  - `Site Visit Done` (BestCase, prob 55)
  - `EOI` (BestCase, prob 70)
  - `Token Paid` (Forecast, prob 85)
  - `Closed Won (Booked)` (Closed, prob 100, won=true, closed=true)

### 2 new BusinessProcesses
- `Pre_sales_Residential` — 9 stages: New → Qualified → Site Visit
  Scheduled → Site Visit Done → Negotiation → EOI → Token Paid →
  Closed Won (Booked) → Closed Lost.
- `Pre_sales_Commercial` — 7 stages: New → Qualified → Negotiation →
  EOI → Token Paid → Closed Won (Booked) → Closed Lost (no
  site-visit stages — commercial sales typically skip on-site
  showroom visits).

### 2 RecordType updates
- `Pre_sales_Residential.recordType-meta.xml`:
  `<businessProcess>` ref changed from `Pre_Sales_Process` →
  `Pre_sales_Residential`.
- `Pre_sales_Commercial.recordType-meta.xml`: same pattern with
  `Pre_sales_Commercial`.

### 1 legacy BP deactivated
- `Pre_Sales_Process.businessProcess-meta.xml`:
  `<isActive>true</isActive>` → `<isActive>false</isActive>`. File
  remains in source for traceability; not destructive-deleted.

## Out of scope (deferred to E06b / E06c)

- **Dynamic Forms flexipage** — progressive field disclosure based on
  StageName (E06b).
- **Stage-gate validation rules** — Project required by Site Visit
  Scheduled, Primary Unit by Negotiation, financial fields at Closed
  Won, reason at Closed Lost (E06b).
- **Path component** per record type (E06b).
- **Concession Request Quick Action** on Opportunity (E06b).
- **UnitBlockingService** Apex + Screen Flow + TestDataFactory + tests
  (E06c).

## Decisions locked

- **D-STAGES — Option A (add alongside).** Six new picklist values
  added to the StandardValueSet; the 7 stock SDO stages
  (Discovery, Qualification, Proposal/Quote, Negotiation, Closed
  Won, Closed Lost — all active before E06a) are left in place. Other
  RTs (SimpleOpportunity, ChannelPartner) continue using their stock
  BPs. Per-RT scoping on the residential/commercial RTs hides clutter
  from RMs at runtime via BusinessProcess `<values>` filtering.

- **D-BP-REPLACEMENT — Option C (mark inactive, do not delete).**
  Legacy `Pre_Sales_Process` BP is marked
  `<isActive>false</isActive>` rather than destructive-deleted.
  Cheaper than a destructiveChanges deploy; preserves Sales-Cloud
  reference history if anyone audits the org. Destructive-delete
  remains a future option if and when we batch-clean up legacy
  metadata.

- **D-APEX-PATH — flat `classes/`.** Recorded here for context
  (no Apex in E06a itself); applies to E06c when we land
  `UnitBlockingService.cls` etc.

## Acceptance criteria

1. **13 active OpportunityStage values** post-deploy (6 new + 7 stock
   preserved). Verified via SOQL: 13 rows where `IsActive=true`.
2. **2 new BPs active.** Verified — `Pre_sales_Residential` Id
   `019Hp000000gC0YIAU`, `Pre_sales_Commercial` Id
   `019Hp000000gC0XIAU`, both `IsActive=true`.
3. **RT → BP refs correctly updated.** Verified — both
   `Pre_sales_*` RTs have BusinessProcessId matching the right new BP.
4. **Legacy `Pre_Sales_Process` BP marked inactive.** Verified — SOQL
   returns `IsActive=false`. Still in repo; not deleted.
5. **`won=true` permitted on both `Closed Won` and `Closed Won
   (Booked)`.** No "two won stages" forecasting rejection at deploy.
   Documented as a confirmed-OK pattern for any future
   `Closed Won (Cancelled)` etc. additions.

## Manual verification (post-deploy, E23 rehearsal hook)

These cannot be scripted — Sahil to spot-check at next SDO login:

1. New Opportunity with RecordType=`Pre_sales_Residential` → stage
   dropdown shows exactly: New, Qualified, Site Visit Scheduled,
   Site Visit Done, Negotiation, EOI, Token Paid, Closed Won
   (Booked), Closed Lost. Should NOT show: Discovery, Qualification,
   Proposal/Quote, Closed Won.
2. Same with RecordType=`Pre_sales_Commercial` → stage dropdown
   shows the same set MINUS Site Visit Scheduled and Site Visit Done.
3. Existing `SimpleOpportunity` and `ChannelPartner` RT stage
   dropdowns are unchanged.

## Iteration story

| Phase | Components | Outcome |
|---|---|---|
| Phase 1 — primary deploy (SVS + 2 BPs + 2 RT updates) | 18/18 (2 Created, 3 Changed, 13 Unchanged-by-side-effect) | Green (Deploy ID `0AfHp00003nOU8WKAW`, 7.61s) |
| Phase 2 — mark legacy BP inactive | 1/1 Changed | Green (Deploy ID `0AfHp00003nOU8gKAG`, 3.09s) |

No deploy retries needed. Both phases dry-runned green on first try.

## Files produced / modified

- **New:**
  - `force-app/main/default/standardValueSets/OpportunityStage.standardValueSet-meta.xml`
  - `force-app/main/default/objects/Opportunity/businessProcesses/Pre_sales_Residential.businessProcess-meta.xml`
  - `force-app/main/default/objects/Opportunity/businessProcesses/Pre_sales_Commercial.businessProcess-meta.xml`

- **Modified:**
  - `force-app/main/default/objects/Opportunity/recordTypes/Pre_sales_Residential.recordType-meta.xml` (BP ref)
  - `force-app/main/default/objects/Opportunity/recordTypes/Pre_sales_Commercial.recordType-meta.xml` (BP ref)
  - `force-app/main/default/objects/Opportunity/businessProcesses/Pre_Sales_Process.businessProcess-meta.xml` (`isActive` flipped)

## Gotcha captured (now in CLAUDE.md)

- **#28** — Metadata API normalisation on unchanged components.
  Phase 1 deploy reported `Pre_Sales_Process` BP as State=Changed
  even though the source file was untouched. Salesforce's serialised
  org-side XML differs cosmetically from the source-format file
  (whitespace / attribute order / omitted-default fields). Functionally
  a no-op; safe to accept. `git diff` post-deploy confirms zero
  semantic delta in our source.

## Implemented

**Commits**
See `git log --grep='E06a'` for the commits that implemented this
epic (typically two: feat for the metadata, docs for this file +
CLAUDE.md gotcha update).

## Known follow-ups

- **Destructive-delete of inactive `Pre_Sales_Process` BP** — deferred.
  Queue for a future cleanup mini-epic when we have a batch of
  destructive changes to make. Until then, the inactive BP is harmless.
- **E06b** — Dynamic Forms flexipage, validation rules, Path,
  Concession Quick Action.
- **E06c** — UnitBlockingService.cls + Block_Unit_For_Opportunity
  Screen Flow + Block_Unit Quick Action + TestDataFactory.cls +
  UnitBlockingServiceTest.cls.
- **Phase 1 cosmetic deploy hits.** When the next epic edits anything
  in `force-app/main/default/objects/Opportunity/`, expect
  `Pre_Sales_Process` and possibly other unchanged-by-us components
  to re-appear as State=Changed in the deploy report. Acceptable per
  gotcha #28.
