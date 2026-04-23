# E06b — Validation Rules, Path, and Concession Request Quick Action

## Objective

Add functional stage-gating and UX affordances on top of the E06a
Opportunity stage/BusinessProcess foundation. After E06b, RMs cannot
advance an Opportunity past a given stage without the fields that
downstream automation depends on (Project, Primary Unit, EOI/Token
amounts, Close Reason), the Lightning record page surfaces a guided
Path for each record type, and the "Request Concession" Quick Action
on Opportunity launches the Concession Request creation flow wired
to E05's existing approval process.

E06b is the **second** of three E06 sub-phases (E06a stages/BPs
complete; E06c UnitBlocking Apex/Flow/tests is next).

## Dependencies

- **E06a** complete — 9-stage residential BP and 7-stage commercial BP
  deployed; validation formulas reference the demo-narrative stage
  names (`Site Visit Scheduled`, `EOI`, `Token Paid`,
  `Closed Won (Booked)`) that E06a added to the StandardValueSet.
- **E05b** complete — Admin profile FLS grants allow validation rules
  and the Quick Action layout to reference all Opportunity and
  Concession_Request custom fields.
- **E05** complete — Concession Request approval process exists; the
  Quick Action creates the record that E05's approval wires up to.

## In scope

### 4 ValidationRules on Opportunity

All four fire on `ISCHANGED(StageName)` — only on stage transitions,
not every save.

- **Require_Project_After_Qualified** (renamed from the spec's
  "Require_Project_By_Site_Visit" — name was misleading since the
  rule fires for commercial-RT opps that skip site-visit stages).
  Exempts `New` and `Qualified`; requires `Project__c` once stage
  advances past `Qualified`.
- **Require_Unit_By_Negotiation** — requires `Primary_Unit__c` when
  stage enters `Negotiation`, `EOI`, `Token Paid`, or `Closed Won
  (Booked)`.
- **Closed_Won_Requires_Financials** — requires `EOI_Amount__c`,
  `Token_Amount__c`, and `Primary_Unit__c` on `Closed Won (Booked)`.
- **Closed_Lost_Requires_Reason** — requires `Close_Reason_Lost__c`
  picklist to be non-blank on `Closed Lost`. Formula uses
  `ISBLANK(TEXT(picklist))` because `ISPICKVAL(picklist, '')` does
  not test for blank (it would test for a non-existent empty-string
  value and never fire).

### 2 PathAssistants

- **Pre_sales_Residential_Path** — 9 steps matching the BP stages,
  each with 1-sentence guidance text (e.g., *"Collect Expression
  of Interest amount. Confirm unit selection."*). Scoped to the
  `Pre_sales_Residential` record type.
- **Pre_sales_Commercial_Path** — 7 steps matching the commercial
  BP, no Site Visit stages. Scoped to `Pre_sales_Commercial`.

### 1 QuickAction on Opportunity

- **Request_Concession** — `type=Create`, target
  `Concession_Request__c`. Layout is 2×3 (two columns, three items
  each):
  - Left: Requested_Pct (Required), Requested_Amount, Unit
  - Right: Justification, Expiry_Date, Requested_By
  - `Status__c` gets its default value (`Draft`) from the picklist
    definition's `<default>true</default>` — no pre-fill needed.
  - `Opportunity__c` auto-populates via Salesforce's standard
    Create-Quick-Action record-context behaviour when launched from
    an Opportunity record page (no explicit `<fieldOverrides>`
    needed).

## Out of scope (deferred)

- **Dynamic Forms flexipage** — progressive field disclosure based
  on StageName. Moved to a dedicated layout epic (E06-layout or
  similar) that will cover all objects' record pages in one pass.
- **Page layout addition of the Quick Action to Opp layouts** — the
  Quick Action is deployed but not yet wired onto `Pre_sales_*`
  layouts. Layout edits are covered by the same future layout epic.
- **Concession Request approval-process invocation from the Quick
  Action** — the action creates the record in `Status=Draft`; user
  clicks Submit for Approval separately (per E05 D6). No auto-submit.
- **Flow-based rule exemptions** — e.g., skipping validation when a
  specific user role (Admin) advances stages for historical cleanup.
  Validation rules always fire; admin override is via the global
  `Override Validation Rules` user permission (not in scope here).

## Decisions locked

- **D1 — 4 validation rules, all active.** Concerns raised and
  resolved before STEP 2: (a) Rule 4 formula corrected from
  `ISPICKVAL(picklist, '')` to `ISBLANK(TEXT(picklist))`;
  (b) Rule 1 renamed to `Require_Project_After_Qualified` to match
  its cross-RT behaviour.
- **D2 — 2 PathAssistants, RT-scoped.** Commercial path omits Site
  Visit stages per E06a BP definition.
- **D3 — QuickAction, no `<fieldOverrides>`.** Original spec had
  predefined field values for `Opportunity__c`, `Unit__c`,
  `Requested_By__c`. Salesforce rejected `<fieldOverrides>` with
  formula `Id` on a Lookup(Opportunity) field — type mismatch
  (formula returns Text, field expects Lookup). Resolved per Option 1:
  remove all three fieldOverrides. Opportunity__c auto-populates from
  the hosting record page; Unit__c and Requested_By__c are added as
  editable fields on the action layout for user entry. Gotcha #29
  captured.
- **D4 — No Dynamic Forms here.** Deferred to E06-layout to keep
  this epic bounded to functional automation + the concession
  entry-point.
- **D5 — No new fields.** All referenced fields exist from E02b;
  Admin profile FLS (E05b) already covers them. No profile update
  needed in E06b.

## Acceptance criteria

1. **4 validation rules active** on Opportunity. Verified via
   Tooling API — all 4 `ValidationName` rows with `Active=true`.
2. **2 PathAssistants active** — `Pre_sales_Residential_Path` and
   `Pre_sales_Commercial_Path` both `IsActive=true` in the org's
   11 PathAssistants (including SDO stock ones).
3. **Request_Concession Quick Action exists** — Type=Create, target
   object correct, resolves via Tooling API
   `QuickActionDefinition` query.
4. **Quick Action deploys without `<fieldOverrides>`** — relies on
   standard record-context auto-population for the parent lookup.
5. **Validation formulas reference only existing fields and active
   picklist values.** No broken references; all rules deployed
   on the first retry after the QuickAction fix.

## Manual verification (post-deploy, E23 rehearsal hook)

Cannot be scripted — Sahil to confirm at next SDO login:

1. Open a Pre_sales_Residential Opportunity, set StageName to
   `Site Visit Scheduled`, clear Project — save should fail with
   the rule's error message.
2. Set stage to `Negotiation` without `Primary_Unit__c` — save
   should fail with Rule 2's message.
3. Set stage to `Closed Won (Booked)` without financials — save
   should fail with Rule 3's message.
4. Set stage to `Closed Lost` without a Close Reason — save should
   fail with Rule 4's message. Then set a reason — save succeeds.
5. Open any Pre_sales_* Opportunity, confirm Path component renders
   on the record page with the 9 (residential) or 7 (commercial)
   stages and correct guidance text.
6. Click "Request Concession" Quick Action — form opens with 6
   visible fields, Requested_Pct marked Required. Submit the form,
   confirm a `Concession_Request__c` record is created with
   `Opportunity__c` populated to the parent Opp and
   `Status__c='Draft'`.

## Iteration story

| Attempt | Result | Class |
|---|---|---|
| Dry-run 1 (all 7 components) | FAILED — 1 error on Request_Concession QuickAction: `Formula result is data type (Text), incompatible with expected data type (Lookup(Opportunity))` on the `<fieldOverrides>` for `Opportunity__c` | NEW (gotcha #29) |
| Dry-run 2 (after removing all 3 `<fieldOverrides>` and adding Unit + Requested_By as editable layout fields) | Green — 7/7 components Created (Deploy ID `0AfHp00003nOU9jKAG`, 5.65s) | — |
| Real deploy | Green — 7/7 Created (Deploy ID `0AfHp00003nOU9oKAG`, 5.80s) | — |

## Files produced

- `force-app/main/default/objects/Opportunity/validationRules/Require_Project_After_Qualified.validationRule-meta.xml`
- `force-app/main/default/objects/Opportunity/validationRules/Require_Unit_By_Negotiation.validationRule-meta.xml`
- `force-app/main/default/objects/Opportunity/validationRules/Closed_Won_Requires_Financials.validationRule-meta.xml`
- `force-app/main/default/objects/Opportunity/validationRules/Closed_Lost_Requires_Reason.validationRule-meta.xml`
- `force-app/main/default/pathAssistants/Pre_sales_Residential_Path.pathAssistant-meta.xml`
- `force-app/main/default/pathAssistants/Pre_sales_Commercial_Path.pathAssistant-meta.xml`
- `force-app/main/default/objects/Opportunity/quickActions/Request_Concession.quickAction-meta.xml`

## Gotcha captured (now in CLAUDE.md)

- **#29** — Quick Action `<fieldOverrides>` with formula `Id` fails
  on Lookup fields with *"Formula result is data type (Text),
  incompatible with expected data type (Lookup(<Object>))"*. Reason:
  the Salesforce type system enforces Lookup-typed values in
  `<fieldOverrides>`, but raw Id formulas return Text. The formula
  engine doesn't have a Lookup-cast for this context. Workaround:
  remove `<fieldOverrides>` for the parent Lookup and rely on
  Salesforce's automatic parent-record auto-population in Create
  Quick Actions launched from a parent record page (the hosting
  record's Id populates the Lookup to that object implicitly).
  For non-parent Lookups (e.g., `Unit__c` Lookup to a different
  object, `Requested_By__c` Lookup to User), add the field as an
  editable layout item for user entry instead.

## Implemented

**Commits**
See `git log --grep='E06b'` for the commits that implemented this
epic (two: feat for the metadata, docs for this file + CLAUDE.md
gotcha #29).

## Known follow-ups

- **E06-layout (deferred)** — Dynamic Forms for progressive field
  disclosure; add the `Request_Concession` action to both Pre_sales_*
  page layouts; Path component placement on the record page.
- **E06c (next)** — UnitBlockingService Apex, Block_Unit Screen Flow,
  Quick Action, TestDataFactory, UnitBlockingServiceTest.
- **Concession `Expiry_Date__c` default value** — currently no field
  default; user sets manually on the Quick Action form. Adding a
  `defaultValue=TODAY()+7` to the field XML would simplify, but
  wasn't in E06b scope. Queue for a field-default polish commit.
- **Validation-rule bypass** — for demo data seeding, the seed
  scripts will need to either honour the validation rules (populate
  all required fields in sequence) or use the admin's
  `ModifyAllData` context to insert in bulk and activate rules
  afterwards. Revisit when we seed Opportunity records for the demo.
