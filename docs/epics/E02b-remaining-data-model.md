# E02b — Remaining data model: Customer, Transactional, CP, Supporting

## Objective

Land every remaining custom object, field, record type, and validation rule
in the Phase 1 data model. After E02b, the full object graph from Lead →
Opportunity → Booking → Demand → Receipt → Agreement → Possession, plus the
Channel Partner commission loop, plus the supporting objects, is in source
and deployed to `re-crm-sdo`. E03 can then apply sharing. E02c can then
apply permissions.

## Dependencies

- **E02a** (inventory cluster) complete — `Project__c`, `Tower__c`, `Unit__c`
  already deployed.
- **E01** (project setup) complete.

## In scope

### Customer/Lead cluster (Section 3.3)

- `Lead` — extend with 15 custom fields; add record types `Residential_Lead`,
  `Commercial_Lead`.
- `Account` — extend with 18 custom fields; add record types `Buyer`,
  `Corporate_Buyer`, `Channel_Partner`.
- `Contact` — extend with 6 custom fields (see Deviation #1 — not enumerated
  in the arch doc; best-judgment fields chosen).
- `Site_Visit__c` — new custom object, 15 custom fields + auto-number Name,
  custom tab.

### Transactional cluster (Section 3.4)

- `Opportunity` — extend with 12 custom fields; add record types
  `Pre-sales_Residential`, `Pre-sales_Commercial`.
- `Booking__c` — new, 33 custom fields + Text Name (trigger-populated later)
  + 1 auxiliary field for `Joint_Booking__c` formula (see Deviation #5),
  record types `Residential_Booking`, `Commercial_Booking`, validation rule
  `Unit_Must_Be_Blocked_At_Booking`, custom tab.
- `Booking_Customer__c` — junction, 7 custom fields + auto-number Name.
- `Payment_Plan__c` — new, 6 custom fields + Text Name, validation rule
  `Active_Plan_Total_Pct_Must_Be_100`, custom tab.
- `Payment_Plan_Milestone__c` — new child of Payment_Plan, 8 custom fields
  + auto-number Name.
- `Booking_Payment_Schedule__c` — new child of Booking, 13 custom fields +
  auto-number Name.
- `Demand__c` — new child of Booking, 21 custom fields + Text Name
  (trigger-populated later), custom tab.
- `Receipt__c` — new child of Booking, 15 custom fields + auto-number Name,
  custom tab.
- `Receipt_Allocation__c` — junction, 5 custom fields + auto-number Name.
- `Agreement__c` — new child of Booking (1:1), 17 custom fields + Text Name,
  custom tab.
- `Possession__c` — new child of Booking (1:1), 15 custom fields + Text Name,
  custom tab.
- `Snag_Item__c` — new child of Possession, 9 custom fields + auto-number
  Name.
- `Pricing_Component__c` — new child of Booking, 11 custom fields +
  auto-number Name. (Deferred from E02a; lands now alongside Booking.)
- `Unit__c.Active_Booking__c` — Lookup(Booking__c) added to close out the
  E02a deferral.

### Channel Partner cluster (Section 3.5)

- `Commission_Rate_Card__c` — 10 custom fields + auto-number Name, custom
  tab.
- `Commission_Ledger__c` — 15 custom fields + Text Name (trigger-populated
  later), custom tab.
- `Commission_Payout__c` — 11 custom fields + auto-number Name, custom tab.

### Supporting cluster (Section 3.6)

- `Notification_Preference__c` — 8 custom fields + auto-number Name.
- `Concession_Request__c` — 12 custom fields + auto-number Name, custom tab.
- `Document_Checklist__c` — 9 custom fields + auto-number Name.

## Out of scope (deferred to future epics)

- Permission sets, tab visibility per profile, app-level tab assignments —
  **E02c**.
- OWD tightening per Section 5.1 (Phase 1 sharing spec) — **E03**.
- Triggers that populate `Name` on Booking/Demand/Agreement/Possession/
  Commission_Ledger, roll-up-via-Lookup trigger logic (e.g.,
  `Demand.Amount_Received__c`, `Commission_Payout` roll-ups) — **E05–E17**.
- Approval processes for `Concession_Request__c` — **E10**.
- Flow enforcing "exactly one primary buyer per Booking" and "sum of
  Ownership_Pct = 100 per Booking" on `Booking_Customer__c` — **E08**
  (declarative validation can't enforce cross-row rules).
- Unit-status-on-Booking trigger that transitions Unit to Booked — **E07**.
- Agentforce fields population (`Lead_Score__c`, `Suggested_Units__c`,
  etc.) by the Lead Qualification Agent — **E20**.

## Acceptance criteria

- `sf data query "SELECT QualifiedApiName FROM EntityDefinition WHERE
  QualifiedApiName IN (...19 new object names...)"` returns 19 rows.
- 9 record types deployed (Lead 2, Account 3, Opportunity 2, Booking 2).
- All validation rules deploy active.
- Deploy completes from clean source with `--test-level NoTestRun` via
  `./scripts/deploy.sh re-crm-sdo --skip-validate`.

## Non-functional

- Full repo redeployable to a fresh SDO in a single deploy (E02a + E02b
  together, since they share no conflicts).
- Dependency ordering is handled by Salesforce deploy in one transaction;
  no manual ordering required.

## Artefacts to produce

See **Implemented** section (populated post-build).

## Implementation notes

### Lessons carried from E02a

- **Formula fields cannot be `<unique>` or `<externalId>`.** Applies here
  to `Unit_Code`-style derived fields (none in this batch) and to any
  `Plan_Code__c`-style field (which *is* data-entry text, so CAN be unique
  + external ID).
- **Count roll-up summaries** must omit `<summarizedField>` entirely.
- **Picklist values use spaces**, not underscores. RT developer names use
  underscores; picklist values match the CLAUDE.md rule.
- **OWD** — every new custom object in E02b ships with `sharingModel =
  ReadWrite` (or `ControlledByParent` for Master-Detail children). E03
  tightens per Section 5.1.

### Formula strategy

Cross-object formulas traverse via `Booking__r.`, `Unit__r.`,
`Payment_Plan__r.`, etc. Specific formulas and their rationale:

- `Booking__c.Project__c` — `Formula(Text)` returning
  `Unit__r.Tower__r.Project__r.Project_Code__c` (Section 3.4 calls it
  `Formula(Lookup)`; not supported — per Sahil's pre-approval).
- `Booking__c.Agreement_Value__c` — interpreted as `Quoted_Gross_Value__c`
  for MVP. Cross-referenced by Commission_Ledger and Agreement objects.
- `Booking__c.Total_Consideration__c` = `Quoted_Gross_Value__c +
  GST_Amount__c`.
- `Booking__c.Total_Outstanding__c` = `Total_Consideration__c -
  Total_Paid__c`.
- `Booking__c.Agreement_Due_Date__c` = `Booking_Date__c + 45` (RERA
  window).
- `Booking__c.NRI_Booking__c` = `Primary_Buyer__r.NRI_Status__c`.
- `Booking__c.Joint_Booking__c` = `Customer_Count__c > 1` — requires a
  supporting roll-up `Customer_Count__c` (not enumerated in spec, added).
- `Booking__c.Days_Since_Booking__c` = `TODAY() - Booking_Date__c`.
- `Demand__c.Net_Payable__c` = `Principal_Amount__c + GST_Amount__c -
  TDS_Amount__c`.
- `Demand__c.Days_Overdue__c` = `IF(TODAY() > Due_Date__c, TODAY() -
  Due_Date__c, 0)`.
- `Agreement__c.Agreement_Value__c` = `Booking__r.Agreement_Value__c`.
- `Possession__c.All_Dues_Cleared__c` = `Booking__r.Total_Outstanding__c
  = 0`.
- `Commission_Rate_Card__c.Active__c` = `AND(TODAY() >=
  Effective_From__c, OR(ISBLANK(Effective_To__c), TODAY() <=
  Effective_To__c))`.
- `Commission_Ledger__c.Gross_Commission__c` = `Agreement_Value_Basis__c *
  Rate_Pct__c`. `Rate_Pct__c` is data-entry `Percent(4,2)` — stored as
  decimal (5% → 0.05), so no `/100` needed.
- `Site_Visit__c.Source_Channel__c` — `Formula(Text)` pulling from
  Opportunity first, else Lead.

### Roll-up summary strategy

Only Master-Detail parents can use native roll-up summaries. Lookup-based
"roll-ups" mentioned in spec (`Demand.Amount_Received__c`,
`Commission_Payout` counts/sums from `Commission_Ledger`) are implemented
as plain Currency/Number fields — they'll be populated by triggers in
later epics.

Native roll-ups included:

- `Receipt__c.Amount_Allocated__c` — SUM of
  `Receipt_Allocation__c.Amount_Allocated__c` (MD parent).
- `Payment_Plan__c.Milestone_Count__c` — COUNT of
  `Payment_Plan_Milestone__c` (MD parent).
- `Payment_Plan__c.Total_Pct_Check__c` — SUM of
  `Payment_Plan_Milestone__c.Percentage__c`.
- `Booking__c.Total_Paid__c` — SUM of `Receipt__c.Amount__c` (MD parent).
- `Booking__c.Customer_Count__c` — COUNT of `Booking_Customer__c`
  (supports `Joint_Booking__c` formula).
- `Possession__c.Snag_Count__c` — COUNT of `Snag_Item__c` (MD parent).
- `Possession__c.Open_Snag_Count__c` — COUNT of `Snag_Item__c` filtered
  `Status__c = Open`.

### Validation rules produced

- `Booking__c.Unit_Must_Be_Blocked_At_Booking` — prevents booking on a
  Unit that isn't in `Blocked` status (Naming Convention §7).
- `Payment_Plan__c.Active_Plan_Total_Pct_Must_Be_100` — active plans must
  have milestone percentages summing to 100 (Naming Convention §7).

## Deviations from spec (draft list — finalised post-build)

1. **Contact custom fields not enumerated in arch doc Section 3.3.** User
   brief says "6 custom fields". Chosen: `PAN__c` (Text 10), `Aadhaar_Last4__c`
   (Text 4), `DOB__c` (Date), `NRI_Status__c` (Checkbox),
   `Passport_Number__c` (Text 20, for NRI co-buyers), `Occupation__c`
   (Text 80). Rationale: Contact represents the individual in a joint-buyer
   scenario; Account carries the household/entity-level KYC, but co-buyers
   still have their own PAN/Aadhaar/DOB. Surface to Sahil on review.
2. **`Booking__c.Project__c` is `Formula(Text)`**, not `Formula(Lookup)`.
   Pre-approved: formula fields cannot return reference types.
3. **`Booking__c.Source_Channel__c` is plain Picklist.** Arch doc says
   `Picklist (Copied from Opp, locked)`; the copy-and-lock lives in a
   trigger in later epics.
4. **`Opportunity.Source_Channel__c` is plain Picklist**, not `Formula`.
   No Lead reference exists post-conversion, so a formula can't point back
   to Lead. Trigger copies on conversion — deferred epic.
5. **`Booking__c.Customer_Count__c` added (not in spec).** Supports the
   `Joint_Booking__c` formula, which the spec requires but can't be
   computed without a child count.
6. **"Linked Unit must be Blocked" validation rule on Booking__c is
   ISNEW-only.** The full status-transition enforcement lives in E07.
7. **Lookup-based "roll-ups" implemented as plain fields.** Salesforce
   native roll-ups require Master-Detail; spec fields like
   `Demand.Amount_Received__c`, `Commission_Payout.Entry_Count__c`, etc.,
   are plain Currency/Number and will be populated by triggers later.
8. **OWD on all new objects is `ReadWrite` (or `ControlledByParent` for
   MD children).** E03 applies the production OWD.
9. **`Unit__c.Active_Booking__c` Lookup(Booking__c)** — closing out the
   E02a deferral. No trigger yet to populate/null-out on Booking
   status changes — E07.
10. **Picklists not enumerated in spec populated with reasonable values.**
    E.g., `Booking_Customer__c.Relationship__c` uses the 6 values listed
    in Section 3.4; `Cancellation_Reason__c` populated with common
    reasons since spec leaves values open.

## Implemented

Populated post-deploy.
