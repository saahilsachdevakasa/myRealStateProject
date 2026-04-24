# E14 — Screen Flows and Quick Actions

## Objective

Give every post-sales service (E10–E13) and the site-visit capture a one-click UI entry point. Previously these `@InvocableMethod`s were only callable from Developer Console or other Flow/Apex callers. This epic makes them clickable buttons on record pages.

## Dependencies

- E08–E13 Apex services with `@InvocableMethod` entry points
- E06-layout page layouts (`Booking Layout`, `Receipt Layout`, `Demand Layout`, `Opportunity RE CRM Pre-sales Layout`)

## In-scope artefacts

**6 Screen Flows** (`force-app/main/default/flows/`):
1. `Raise_Demand` — Booking Id input → radio-select a pending `Booking_Payment_Schedule__c` → invoke `DemandService.raiseDemands`
2. `Allocate_Receipt` — Receipt Id input → pick Demand (radio from dynamicChoiceSet), enter amount, pick allocation type → invoke `ReceiptAllocationService.allocateReceipts`
3. `Create_Agreement` — Booking Id input → confirmation → invoke `AgreementService.createAgreements`
4. `Create_Possession` — Booking Id input → confirmation → invoke `PossessionService.createPossessions`
5. `Generate_Demand_Letter` — Demand Id input → confirmation → invoke `DemandLetterService.generateDemandLetters`
6. `Schedule_Site_Visit` — Opportunity Id input → DateTime + Notes inputs → `recordCreates` a `Site_Visit__c` (direct DML, no service)

**6 Flow-type Quick Actions** wrapping each flow:
- `Booking__c/quickActions/Raise_Demand`
- `Booking__c/quickActions/Create_Agreement`
- `Booking__c/quickActions/Create_Possession`
- `Receipt__c/quickActions/Allocate_Receipt`
- `Demand__c/quickActions/Generate_Demand_Letter`
- `Opportunity/quickActions/Schedule_Site_Visit`

**4 page layout updates** — added new Flow QAs to `<platformActionList>` (see gotcha #41):
- Booking layout — added `Raise_Demand`, `Create_Agreement`, `Create_Possession`
- Receipt layout — added `Allocate_Receipt`
- Demand layout — added `Generate_Demand_Letter`
- Opportunity RE CRM Pre-sales Layout — appended `Schedule_Site_Visit` to existing `<platformActionList>`

## Locked design decisions

**D1. Screen Flows, not AutoLaunched.** Users need a confirmation screen + (for Flows 1/2/6) input fields. Screen Flows are the only Flow type with a UI; AutoLaunched runs headlessly.

**D2. Simplest-first pilot.** Built `Create_Agreement` first — pure confirmation + single `actionCall` to a Booking Id InvocableMethod. Deployed green first attempt. Used its XML as the template for Flows 4 and 5 (mechanical substitution). Flow 6 added `recordCreates` + user input fields. Flows 1 and 2 added `dynamicChoiceSets` (the highest-risk pattern).

**D3. Flow API version 62.0** (project standard), `<processType>Flow</processType>`, `<status>Active</status>`.

**D4. No `<processMetadataValues>` workaround** — the retrieved SDO template (`SDO_Service_WEM_Absence_Request`) includes `BuilderType=LightningFlowBuilder` + `CanvasMode=AUTO_LAYOUT_CANVAS`. We replicated both for Builder-compatibility — without them, the flow deploys but opens in a different Builder experience.

**D5. Dynamic choice sets vs. empty-check decisions.** Spec suggested a `<decisions>` element to check if the schedule-list is empty before showing the radio screen. Rejected — Flow doesn't have a clean `isEmpty` operator for collections without a pre-lookup + assignment, which adds 20+ lines of XML. Instead, the selection screen's Display Text tells the user "If no options appear, all milestones already have demands." Same UX outcome, simpler XML, one less moving part.

**D6. Lookup-to-Unit omitted from Flow 6.** Spec suggested a Lookup field for `Primary_Unit__c` on the Schedule Site Visit screen. Rejected for MVP — Flow screen Lookup fields require the `extensionName=flowruntime:lookup` / `ComponentInstance` pattern which adds ~30 lines and multiple failure modes. User picks the unit on the Site Visit record after creation. Can be added in a polish pass.

**D7. Flow-type QAs surface via `<platformActionList>`, not `<quickActionList>`.** Discovered at dry-run (see gotcha #41). All 4 layouts use `<platformActionList>` for the Flow QAs.

## Iteration story

- **STEP 1 discovery** — Retrieved `SDO_Service_WEM_Absence_Request.flow-meta.xml` (227 lines) from the SDO as structural template. No Screen Flow existed in the repo.
- **STEP 2 pilot** — `Create_Agreement` deployed green on first dry-run attempt.
- **STEP 3 batch 1** — `Create_Possession`, `Generate_Demand_Letter` deployed green first attempt.
- **STEP 3 batch 2** — `Schedule_Site_Visit` (recordCreates + DateTime/TextArea inputs) deployed green first attempt.
- **STEP 3 batch 3** — `Raise_Demand` needed **3 dry-run attempts**:
  - Attempt 1: Type mismatch — screen RadioButton (dataType=String) bound to dynamicChoiceSet (valueField=Id) → passed directly to `@InvocableVariable Id` fails. Workaround: added intermediate `<assignments>` element to copy via a String variable, letting Flow's implicit String→Id coercion kick in at variable-reference time.
  - Attempt 2: Wrong reference syntax — `<elementReference>Select_Screen.Selected_Schedule</elementReference>` rejected. The correct form references the screen field by its name directly: `<elementReference>Selected_Schedule</elementReference>`.
  - Attempt 3: Green.
- `Allocate_Receipt` applied the Flow 1 lessons preemptively; green first attempt despite being the most complex (static choice set + dynamic choice set + 3 screen input fields + 4 action parameters).
- **STEP 4** — 6 Quick Actions deployed in one batch, no issues.
- **STEP 5** — Layout deploy failed first attempt with `"You can't add QuickActionType Flow to a QuickActionList"`. Moved Flow QAs to `<platformActionList>`. Green on retry.

## Files produced

```
force-app/main/default/flows/
├── Allocate_Receipt.flow-meta.xml
├── Create_Agreement.flow-meta.xml         (pilot)
├── Create_Possession.flow-meta.xml
├── Generate_Demand_Letter.flow-meta.xml
├── Raise_Demand.flow-meta.xml
└── Schedule_Site_Visit.flow-meta.xml

force-app/main/default/objects/Booking__c/quickActions/
├── Create_Agreement.quickAction-meta.xml
├── Create_Possession.quickAction-meta.xml
└── Raise_Demand.quickAction-meta.xml

force-app/main/default/objects/Receipt__c/quickActions/
└── Allocate_Receipt.quickAction-meta.xml

force-app/main/default/objects/Demand__c/quickActions/
└── Generate_Demand_Letter.quickAction-meta.xml

force-app/main/default/objects/Opportunity/quickActions/
└── Schedule_Site_Visit.quickAction-meta.xml   (Request_Concession already existed)

force-app/main/default/layouts/
├── Booking__c-Booking Layout.layout-meta.xml        (MODIFIED — platformActionList added)
├── Receipt__c-Receipt Layout.layout-meta.xml        (MODIFIED — platformActionList added)
├── Demand__c-Demand Layout.layout-meta.xml          (MODIFIED — platformActionList added)
└── Opportunity-RE CRM Pre-sales Layout.layout-meta.xml  (MODIFIED — Schedule_Site_Visit appended to existing platformActionList)
```

## Verification

```
SELECT DeveloperName, Type, TargetSobjectType FROM QuickActionDefinition
WHERE DeveloperName IN (<all 6>)

Allocate_Receipt        Flow
Create_Agreement        Flow
Create_Possession       Flow
Generate_Demand_Letter  Flow
Raise_Demand            Flow
Schedule_Site_Visit     Flow
```

All 6 in org, type=Flow. `TargetSobjectType=null` is normal for Flow-type QAs — the host object is determined by the layout's parent object.

## Gotchas surfaced

Two new entries for CLAUDE.md. See `#41` and `#42` in that file.

## Known follow-ups

- **Flow 6 Unit Lookup** — add `extensionName=flowruntime:lookup` Lookup field for `Primary_Unit__c` with a filter on `Project__c` matching the Opportunity's Project.
- **Flow 1 and 2 display enhancement** — the dynamic-choice-set radio currently displays a single field (`Milestone_Trigger__c` / `Demand.Name`). Salesforce supports concatenated display via `Picklist_Choice_Formula` in Flow Builder; can't be hand-authored reliably in XML. Acceptable for MVP.
- **Error handling** — all 6 flows assume the InvocableMethod succeeds. If an `AuraHandledException` fires (e.g., Agreement already exists), the user sees a generic Salesforce error toast. Fault paths with dedicated error screens are a polish pass.
- **Bulk-select on Flow 1** — currently raises one demand at a time. A future enhancement would allow multi-select + batch raise.
- **Receipt Allocation on Lightning Experience** — ReceiptAllocationService supports multi-demand per receipt; Flow 2 only allows one allocation per invocation. Re-run the QA for additional allocations.
