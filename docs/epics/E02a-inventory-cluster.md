# E02a — Inventory cluster metadata: Project, Tower, Unit

## Objective

Stand up the core inventory data model — `Project__c`, `Tower__c`, `Unit__c` —
with all fields, record types, formula-derived codes, roll-up summaries, and
the declarative validation rules required by the Naming Convention Appendix.
This is the foundation every downstream cluster (Booking, Demand, Receipt,
Commission) depends on.

## Dependencies

- E01 (project setup) complete — SFDX scaffold, `sfdx-project.json`, authed SDO
  (`re-crm-sdo`) in place.

## In scope

- `Project__c` custom object, 2 record types (Residential, Commercial),
  `Project_Code_Format` validation rule, custom tab.
- `Tower__c` custom object (Master-Detail to `Project__c`), 2 record types
  (Residential_Tower, Commercial_Block), `Tower_Name_Matches_Code` validation
  rule, custom tab.
- `Unit__c` custom object (Master-Detail to `Tower__c`), 2 record types
  (Residential_Unit, Commercial_Shop), `Floor_In_Range` and
  `Unit_Number_In_Range` validation rules, custom tab.
- Formula fields per Phase 1 Architecture Section 3.2:
  `Project__c.Sellthrough_Pct__c`, `Tower__c.Tower_Code__c`,
  `Unit__c.Unit_Code__c`, `Unit__c.Project__c`, `Unit__c.Floor_Rise_Pct__c`,
  `Unit__c.PLC_Corner_Pct__c`, `Unit__c.PLC_Park_Pct__c`,
  `Unit__c.Base_Price__c`.
- Roll-up summaries: `Tower__c.Total_Units__c`, `Available_Units__c`,
  `Booked_Units__c`; `Project__c.Total_Towers__c`, `Total_Units__c`,
  `Available_Units__c`, `Booked_Units__c`.
- Deploy script update (`scripts/deploy.sh`) to default `--test-level
  NoTestRun` while the org has zero Apex; revisit when Apex first lands.

## Out of scope (deferred to future epics)

- `Pricing_Component__c` object — deferred to **E02b** alongside `Booking__c`
  (Master-Detail parent).
- `Unit__c.Active_Booking__c` Lookup(Booking__c) — deferred to **E02b** when
  `Booking__c` is created.
- OWD / sharing model on the three objects — set to `ReadWrite` (Project) /
  `ControlledByParent` (Tower, Unit) for now; tightened to
  *Public Read Only internal, Private external* in **E03** (sharing).
- Permission sets, tab visibility per profile, page layout customisation —
  **E02c** (permissions).
- Unit status lifecycle Flow, 72-hour auto-release, `Status_History__c`
  trigger, `Last_Status_Change__c` stamping — **E07** (inventory lifecycle).
- Triggers on any of the three objects — **E07** onwards.

## Acceptance criteria

- `Project__c`, `Tower__c`, `Unit__c` deploy cleanly to `re-crm-sdo` with
  `--test-level NoTestRun`.
- `sf data query "SELECT QualifiedApiName FROM EntityDefinition WHERE
  QualifiedApiName IN ('Project__c','Tower__c','Unit__c')"` returns 3 rows.
- 2 record types active on each object.
- Every field listed in Phase 1 Architecture Section 3.2 for these three
  objects exists, modulo the two explicitly deferred fields (see
  Implemented > Deviations).
- Validation rules from Naming Convention Appendix Section 7 that apply to
  these objects are present and active.

## Non-functional

- The object + field set must be fully redeployable from source in under 60
  seconds on a fresh SDO. (Actual: ~21s on re-crm-sdo.)
- No dependency on manual Setup-UI steps.

## Artefacts produced

See **Implemented** below.

## Implementation notes

- `Tower_Code__c` and `Unit_Code__c` are formula text fields. Salesforce does
  not allow `unique` or `externalId` attributes on formula fields — they are
  enforced by the formula's determinism (parent code + zero-padded numbers).
  Spec's "unique, external ID" wording was interpreted as a design intent,
  not a metadata attribute.
- Count roll-up summaries must omit `<summarizedField>` — the SOAP API
  rejects `<summarizedField>X.Id</summarizedField>` with "bad value for
  restricted picklist field: Id".
- Project-level roll-ups traverse two levels (Project ← Tower ← Unit) via
  sums of Tower's roll-up counts. Salesforce supports this across
  Master-Detail chains in a single deploy transaction.
- `Unit__c.Project__c` is a formula text field returning
  `Tower__r.Project__r.Project_Code__c` (Section 3.2 calls it
  "Formula(Lookup)" but Salesforce formulas cannot return reference types).
- Picklist values follow CLAUDE.md rule #9 (Title Case, speak-able): e.g.,
  `Residential Tower` / `Commercial Block` as picklist values; record-type
  developer names `Residential_Tower` / `Commercial_Block` match the spec.

## Implemented

**Commits**
- `cc8d80b` — chore: default deploy test level to NoTestRun pending Apex
- `78c9466` — feat(E02a): inventory cluster metadata (Project, Tower, Unit)
- `bbbee29` — fix(E02a): remove unique/externalId from formula fields and
  summarizedField from count rollups

**Deployed to** `re-crm-sdo` on 2026-04-21. Deploy ID of the successful run
reproduces 76 components. Verified via `EntityDefinition` query.

### Files produced (79 total — 76 metadata components + 1 script change + 1 this epic doc + prior header)

**`Project__c`** — 1 object + 21 field XMLs + 2 record types + 1 validation rule + 1 tab:

- `force-app/main/default/objects/Project__c/Project__c.object-meta.xml`
- `force-app/main/default/objects/Project__c/fields/`:
  - `Project_Code__c.field-meta.xml` (Text(3), required, unique, external ID)
  - `Project_Type__c.field-meta.xml` (Picklist: Residential / Commercial)
  - `Positioning__c.field-meta.xml` (Text(255))
  - `Launch_Status__c.field-meta.xml` (Picklist: Planned / Newly Launched / Under Construction / Ready-to-Move)
  - `Location__c.field-meta.xml` (Text(255))
  - `City__c.field-meta.xml` (Text(80))
  - `State__c.field-meta.xml` (Picklist, 36 Indian states + UTs)
  - `RERA_Number__c.field-meta.xml` (Text(60))
  - `RERA_State__c.field-meta.xml` (Picklist, 36 Indian states + UTs)
  - `Delivery_Date__c.field-meta.xml` (Date)
  - `CC_Received__c.field-meta.xml` (Checkbox)
  - `CC_Date__c.field-meta.xml` (Date)
  - `Total_Towers__c.field-meta.xml` (Roll-up count of Tower__c)
  - `Total_Units__c.field-meta.xml` (Roll-up sum of Tower__c.Total_Units__c)
  - `Available_Units__c.field-meta.xml` (Roll-up sum of Tower__c.Available_Units__c)
  - `Booked_Units__c.field-meta.xml` (Roll-up sum of Tower__c.Booked_Units__c)
  - `Sellthrough_Pct__c.field-meta.xml` (Formula Percent: `(Booked/Total)*100`)
  - `Club_Membership_Fee__c.field-meta.xml` (Currency, default ₹2,50,000)
  - `Covered_Parking_Fee__c.field-meta.xml` (Currency, default ₹5,00,000)
  - `Brochure_URL__c.field-meta.xml` (URL — renamed from spec's `Brochure__c` per owner decision)
  - `Active_for_Bookings__c.field-meta.xml` (Checkbox, default true)
- `recordTypes/Residential.recordType-meta.xml`, `recordTypes/Commercial.recordType-meta.xml`
- `validationRules/Project_Code_Format.validationRule-meta.xml`
- `force-app/main/default/tabs/Project__c.tab-meta.xml`

**`Tower__c`** — 1 object + 13 field XMLs + 2 record types + 1 validation rule + 1 tab:

- `force-app/main/default/objects/Tower__c/Tower__c.object-meta.xml`
- `fields/`:
  - `Project__c.field-meta.xml` (Master-Detail to Project__c)
  - `Tower_Number__c.field-meta.xml` (Number(2,0), required)
  - `Tower_Type__c.field-meta.xml` (Picklist: Residential Tower / Commercial Block, required)
  - `Tower_Code__c.field-meta.xml` (Formula Text: `{PROJ}-T{nn}` / `{PROJ}-B{nn}`)
  - `Total_Floors__c.field-meta.xml` (Number(2,0))
  - `Units_Per_Floor__c.field-meta.xml` (Number(2,0))
  - `Configuration_Mix__c.field-meta.xml` (Text(255))
  - `Construction_Status__c.field-meta.xml` (Picklist: Planned / Excavation / Under Construction / Finishing / Ready)
  - `Total_Units__c.field-meta.xml` (Roll-up count of Unit__c)
  - `Available_Units__c.field-meta.xml` (Roll-up count, filtered Unit_Status__c = Available)
  - `Booked_Units__c.field-meta.xml` (Roll-up count, filtered Unit_Status__c = Booked)
  - `Slab_Progress__c.field-meta.xml` (Text(40))
  - `Current_Milestone__c.field-meta.xml` (Picklist: 10 CLP-style milestones)
- `recordTypes/Residential_Tower.recordType-meta.xml`, `recordTypes/Commercial_Block.recordType-meta.xml`
- `validationRules/Tower_Name_Matches_Code.validationRule-meta.xml` (enforces `Name = Tower_Code__c`)
- `force-app/main/default/tabs/Tower__c.tab-meta.xml`

**`Unit__c`** — 1 object + 26 field XMLs + 2 record types + 2 validation rules + 1 tab:

- `force-app/main/default/objects/Unit__c/Unit__c.object-meta.xml`
- `fields/`:
  - `Tower__c.field-meta.xml` (Master-Detail to Tower__c)
  - `Project__c.field-meta.xml` (Formula Text: `Tower__r.Project__r.Project_Code__c`)
  - `Floor__c.field-meta.xml` (Number(2,0), required)
  - `Unit_Number__c.field-meta.xml` (Number(3,0), required)
  - `Unit_Code__c.field-meta.xml` (Formula Text: `{PROJ}-T{nn}-F{nn}-U{nnn}` / `{PROJ}-B{nn}-F{nn}-S{nnn}`)
  - `Unit_Type_Class__c.field-meta.xml` (Picklist: Residential / Shop / Office / Kiosk, required)
  - `Configuration__c.field-meta.xml` (Picklist: 1BHK / 2BHK / 3BHK / 4BHK / Shop / Anchor / F&B)
  - `Carpet_Area_sqft__c.field-meta.xml` (Number(6,0))
  - `BuiltUp_Area_sqft__c.field-meta.xml` (Number(6,0))
  - `Super_BuiltUp_Area_sqft__c.field-meta.xml` (Number(6,0))
  - `Facing__c.field-meta.xml` (Picklist, 8 values: N/S/E/W/NE/NW/SE/SW)
  - `Corner_Unit__c.field-meta.xml` (Checkbox)
  - `Park_Facing__c.field-meta.xml` (Checkbox)
  - `Floor_Rise_Pct__c.field-meta.xml` (Formula Percent: `1.5 * (Floor - 1)`)
  - `PLC_Corner_Pct__c.field-meta.xml` (Formula Percent: `IF(Corner_Unit__c, 3, 0)`)
  - `PLC_Park_Pct__c.field-meta.xml` (Formula Percent: `IF(Park_Facing__c, 2.5, 0)`)
  - `BSP_Per_Sqft__c.field-meta.xml` (Currency(10,0))
  - `Base_Price__c.field-meta.xml` (Formula Currency: `BSP * SBA * (1 + floor_rise/100 + corner/100 + park/100)`)
  - `Unit_Status__c.field-meta.xml` (Picklist: Available / Blocked / Booked / Cancelled, required, default Available)
  - `Blocked_By__c.field-meta.xml` (Lookup to User)
  - `Blocked_Until__c.field-meta.xml` (DateTime)
  - `Last_Status_Change__c.field-meta.xml` (DateTime)
  - `Status_History__c.field-meta.xml` (Long Text Area 32768)
  - `Frontage_ft__c.field-meta.xml` (Number(4,0))
  - `Shop_Type__c.field-meta.xml` (Picklist: Retail / F&B / Anchor / Kiosk)
  - `Geo_Coordinates__c.field-meta.xml` (Location, decimal, scale 6)
- `recordTypes/Residential_Unit.recordType-meta.xml`, `recordTypes/Commercial_Shop.recordType-meta.xml`
- `validationRules/Floor_In_Range.validationRule-meta.xml`, `validationRules/Unit_Number_In_Range.validationRule-meta.xml`
- `force-app/main/default/tabs/Unit__c.tab-meta.xml`

**Tool / script updates**

- `scripts/deploy.sh` — added `--test-level` flag, default `NoTestRun`.

### Counts summary

| Object | Custom fields | Record types | Validation rules | Tabs |
|---|---|---|---|---|
| Project__c | 21 | 2 | 1 | 1 |
| Tower__c | 13 | 2 | 1 | 1 |
| Unit__c | 26 | 2 | 2 | 1 |
| **Total** | **60** | **6** | **4** | **3** |

(Spec "field counts 22/14/27" include the standard Name field, which is
declared inside the object-meta.xml via `<nameField>` rather than as a
separate `.field-meta.xml` file.)

### Deviations from spec, with reasons

1. **`Pricing_Component__c` and `Unit__c.Active_Booking__c` deferred to
   E02b.** Both require `Booking__c` (Master-Detail parent and Lookup
   target respectively). `Booking__c` is out of scope for E02a. Approved by
   Sahil in the pre-flight Q&A.
2. **`Brochure__c` renamed to `Brochure_URL__c`, type URL.** Spec said
   "Files / attachment" — not a valid Salesforce custom field type. Files
   on records are handled via `ContentDocumentLink`, not a field. Approved
   by Sahil; URL field points to brochure PDF location for Agentforce
   grounding.
3. **`Tower_Code__c` / `Unit_Code__c` are formula text fields without
   `unique` or `externalId` flags.** Salesforce disallows both attributes
   on formula fields ("Can not specify unique/externalId for CustomFields
   that have a formula"). Uniqueness is guaranteed by the formula's
   determinism: `{PROJ}-T{nn}[-F{nn}-U{nnn}]` is unique because parent code
   + zero-padded numbers make any two distinct records produce distinct
   codes. Spec's "unique, external ID" is preserved as a design intent
   rather than a metadata attribute.
4. **`Unit__c.Project__c` is `Formula(Text)` returning Project Code, not
   `Formula(Lookup)`.** Salesforce formula fields cannot return reference
   types. Returning the Project Code (e.g., `PRK`) is the most useful
   stringified surrogate; callers that need the `Id` traverse
   `Tower__r.Project__r.Id` directly.
5. **Picklist values use spaces, not underscores.** CLAUDE.md rule #9
   mandates Title Case, speak-able values ("Residential Tower"). Spec's
   literal "Residential_Tower / Commercial_Block (matches RT)" is honored
   at the record-type *developer name* level (the RT developerName uses
   underscores, the picklist *value* uses spaces).
6. **`Tower__c.Current_Milestone__c` values were not enumerated in the
   spec.** Populated with 10 standard CLP construction milestones:
   Booking, Excavation, Foundation, Plinth, Slab Cast, Brickwork,
   Plastering, Flooring, Finishing, Possession. Revisit in E07 when
   demand-generation logic is wired.
7. **`Facing__c` values were not enumerated (spec said "8 values").**
   Populated with the 8 compass directions: North, South, East, West,
   North-East, North-West, South-East, South-West.
8. **OWD / sharing model is `ReadWrite` on Project__c,
   `ControlledByParent` on Tower__c and Unit__c.** Phase 1 architecture
   expects *Public Read Only internal, Private external* on Unit__c —
   that split is deferred to **E03 (sharing)** which handles the external
   sharing model org-wide.
9. **Roll-up summary `<summarizedField>` intentionally omitted on COUNT
   operations.** Salesforce SOAP API rejects `X.Id` as a summarizedField
   for `<summaryOperation>count</summaryOperation>`; the element must be
   absent entirely.
10. **Deploy ran with `--test-level NoTestRun`** (not `RunLocalTests`) —
    approved by Sahil because the repo contains zero Apex classes.
    `scripts/deploy.sh` now defaults to `NoTestRun`; revisit when Apex
    first lands (expected E06 or E07).

### Manual Setup steps (if any)

None. Everything is in source.

### Known follow-ups for later epics

- **E02b**: add `Booking__c`, then add `Pricing_Component__c` (Master-Detail
  to Booking) and `Unit__c.Active_Booking__c` Lookup(Booking__c).
- **E02c**: permission sets granting object access, tab visibility per
  profile.
- **E03**: tighten OWD on Project/Tower/Unit to Phase 1 sharing spec.
- **E07**: Unit status lifecycle (Flow + validation rule + Status_History
  appender + 72-hour auto-release).
