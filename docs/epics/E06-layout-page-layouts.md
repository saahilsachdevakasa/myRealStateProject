# E06-layout — Page Layouts for All Objects

## Objective

Fix the user-visible "empty form" problem across the entire RE CRM
data model. Before E06-layout, every custom object's "New Record"
form showed only required fields (auto-generated default layouts);
every standard object (Lead, Account, Contact, Opportunity) showed
SDO stock layouts without any RE CRM custom fields. After this epic,
**all 26 objects** (22 custom + 4 standard) have explicit page
layouts covering every relevant field.

Page layouts alone solve the immediate "RM can't see the fields they
need to fill" problem. Flexipages with Dynamic Forms (conditional
field visibility, Path component, progressive disclosure) are
**deferred** to a future epic — the immediate fix doesn't need them.

## Dependencies

- **E02a, E02b, E03** — all custom objects with their fields and
  record types deployed. Layouts reference fields by API name.
- **E04** — Admin profile exists; layouts are profile-agnostic but
  assignment (manual Setup) uses Profile → RT mappings.
- **E05b** — Admin profile FLS grants for 289 fields mean every
  field referenced on a layout is also readable/writable for the
  running user. Without FLS, layout fields render as "access
  denied".
- **E06a / E06b / E06c / E07 / E08** — all metadata referenced by
  layouts must exist before layout deploy. Most notably:
  - E06b's `Request_Concession` QuickAction → added to Opportunity
    layout's quickActionList.
  - E07's Unit lifecycle fields (`Blocked_By__c`, `Blocked_Until__c`,
    `Status_History__c`, `Last_Status_Change__c`, `Active_Booking__c`) →
    Unit layouts' Status + Audit sections.
  - E08's `Booking.Project__c` formula, `Days_Since_Booking__c`
    rollups, etc. → Booking layout's Financials and Lifecycle
    sections (read-only).

## In scope

### 29 page layouts total

Split by cluster for batch-by-batch deploys:

#### Inventory cluster (5 layouts)
- `Project__c-Project Layout` — shared across Residential / Commercial RTs
- `Tower__c-Tower Layout` — shared
- `Unit__c-Residential Unit Layout` — Residential-specific (no Frontage/Shop Type)
- `Unit__c-Commercial Shop Layout` — Commercial-specific (adds Frontage + Shop Type)
- `Pricing_Component__c-Pricing Component Layout`

#### Customer cluster (6 layouts)
- `Lead-RE CRM Lead Layout` — shared; based on SDO baseline + 3 new sections (Source & Interest, Buyer Profile, Agent Scoring)
- `Account-RE CRM Buyer Layout` — Buyer RT: KYC & Identity section
- `Account-RE CRM Corporate Buyer Layout` — Corporate RT: Corporate Details
- `Account-RE CRM Channel Partner Layout` — CP RT: CP Registration + KYC sections
- `Contact-RE CRM Contact Layout` — RE CRM Details section (PAN, DOB, NRI, Occupation, Passport)
- `Site_Visit__c-Site Visit Layout`

#### Transactional cluster (18 layouts)
- `Opportunity-RE CRM Pre-sales Layout` — shared; baseline + 3 new sections (Deal, Financials, Outcome) + Request_Concession QuickAction
- `Booking__c-Booking Layout` — 9 sections, 7 related lists (Booking Customers, Payment Schedule, Demands, Receipts, Commission Ledger, Document Checklist, Pricing Components)
- `Booking_Customer__c-Booking Customer Layout`
- `Payment_Plan__c-Payment Plan Layout` — with Milestones related list
- `Payment_Plan_Milestone__c-Payment Plan Milestone Layout`
- `Booking_Payment_Schedule__c-Booking Payment Schedule Layout`
- `Demand__c-Demand Layout` — with Receipt Allocations related list
- `Receipt__c-Receipt Layout` — with Receipt Allocations related list
- `Receipt_Allocation__c-Receipt Allocation Layout`
- `Agreement__c-Agreement Layout`
- `Possession__c-Possession Layout` — with Snag Items related list
- `Snag_Item__c-Snag Item Layout`
- `Commission_Rate_Card__c-Commission Rate Card Layout`
- `Commission_Ledger__c-Commission Ledger Layout`
- `Commission_Payout__c-Commission Payout Layout`
- `Concession_Request__c-Concession Request Layout`
- `Document_Checklist__c-Document Checklist Layout`
- `Notification_Preference__c-Notification Preference Layout`

## Out of scope (deferred)

- **Lightning Record Pages (flexipages) with Dynamic Forms** —
  progressive field disclosure by stage/status, Path component
  placement, record-page tab structure. Page layouts alone are
  sufficient for the demo's create/edit flows; flexipages polish
  the record view experience.
- **Layout assignments** (per-RT-per-profile) — requires editing
  Admin profile's `<layoutAssignments>` metadata (fragile at this
  volume) or Setup UI clicks. Documented as manual Setup steps
  below; Sahil assigns via Setup UI.
- **Block Unit Screen Flow + Quick Action** (deferred from E06c) —
  Screen Flow XML is finicky; defer to a dedicated Flow epic when
  UI work gets batch attention.
- **Currency locale** — Setup → Company Information → Currency →
  INR. Manual step documented below.

## Decisions locked

- **Path A — 1 shared layout per object unless field sets genuinely
  differ.** Account gets 3 layouts (Buyer / Corporate / CP have
  different KYC/CP fields). Unit gets 2 layouts (Commercial adds
  Frontage + Shop Type). All other RT-bearing objects (Project,
  Tower, Lead, Opportunity, Booking) use 1 shared layout covering
  all fields from both RTs.

- **Standard-object layouts: extend, don't replace.** For Lead,
  Account, Contact, Opportunity — retrieved SDO baseline layouts
  and inserted RE CRM custom-field sections at the end of the
  `<layoutSections>` block. All standard fields, standard related
  lists, and standard platform actions preserved. Created new
  layouts with names `{Object}-RE CRM {Layout Name}` so the SDO
  default stays untouched as a fallback.

- **Custom-object layouts: generated from scratch.** 24 layouts
  written from templates with consistent section structure:
  Identity → Details → Financials → Lifecycle → Notes → System
  Information.

- **Formula / RollUp / AutoNumber fields → `<behavior>Readonly</behavior>`.**
  Required by Salesforce XSD; see gotcha #33.

- **AutoNumber Name fields → Readonly (not Required).**
  Required by Salesforce XSD; see gotcha #34.

- **MD children omit OwnerId from System Information.** Objects
  with `<sharingModel>ControlledByParent</sharingModel>` inherit
  ownership from parent and have no OwnerId field.

- **Related lists use `{ChildObject}.{LookupField}` format** —
  not `{relationshipName}` and not `{relationshipName}__r`. See
  gotcha #32.

## Acceptance criteria

1. **29 layouts deployed** and visible in Setup → Object Manager
   → Page Layouts for each object. Verified.
2. **New Record forms show all custom fields** for every object —
   manual Sahil verification at next SDO login.
3. **Standard fields preserved on Lead/Account/Contact/Opportunity
   layouts** — baseline sections intact, new sections appended.
4. **Opportunity layout has `Request_Concession` QuickAction** —
   verified in the layout XML's quickActionList.
5. **Related lists present on parent layouts** — Project → Towers,
   Tower → Units, Unit → Bookings, Booking → 7 children,
   Payment_Plan → Milestones, Demand → Receipt Allocations,
   Receipt → Receipt Allocations, Possession → Snag Items.

## Manual Setup steps (post-deploy)

### Layout assignments — per-RT-per-profile (required for layouts to appear)

For each record-typed object:

1. Setup → Object Manager → `<Object>` → Page Layouts → Page Layout Assignment
2. Click "Edit Assignment"
3. Map each (Profile × Record Type) cell to the correct layout:

**Project__c** (2 RTs, same layout):
- Residential / System Administrator → Project Layout
- Commercial / System Administrator → Project Layout
- Same for all persona permission set users (RM, PSM, Sales Head, etc.)

**Tower__c**: Both RTs → Tower Layout (single layout for all)

**Unit__c**:
- Residential_Unit / * → Residential Unit Layout
- Commercial_Shop / * → Commercial Shop Layout

**Account**:
- Buyer / * → RE CRM Buyer Layout
- Corporate_Buyer / * → RE CRM Corporate Buyer Layout
- Channel_Partner / * → RE CRM Channel Partner Layout

**Lead**: Both RTs → RE CRM Lead Layout

**Opportunity**: Both RTs → RE CRM Pre-sales Layout

**Booking__c**: Both RTs → Booking Layout

**Contact**: Default → RE CRM Contact Layout

### Currency locale

Setup → Company Information → Currency Locale → **English (India)** (renders ₹ correctly)
Setup → Company Information → Default Currency → **INR** (if not already)

### Assignment automation alternative

If manual assignment is error-prone across 7 RT-bearing objects × N
profiles, a metadata-based approach would edit
`Admin.profile-meta.xml` (and each persona perm set) to include:

```xml
<layoutAssignments>
    <layout>Unit__c-Residential Unit Layout</layout>
    <recordType>Unit__c.Residential_Unit</recordType>
</layoutAssignments>
```

Deferred because: (a) modifying the 2551-line Admin profile is
risky at this volume, (b) the assignment Setup UI is straightforward
for a one-time setup, (c) Sahil will do this once and won't need
to repeat unless the SDO is rebuilt.

## Iteration story

| Batch | Layouts | Outcome |
|---|---|---|
| 1 (Inventory) | 5 | Dry-run 1 failed (5 errors); fixed Name-Required-on-AutoNumber, Formula-must-be-Readonly, related-list syntax. Dry-run 2 + real deploy green. |
| 2 (Customer) | 6 | Dry-run 1 failed (5 errors); fixed XML element ordering (layoutSections must precede quickActionList/relatedContent/relatedLists). Dry-run 2 + real deploy green. |
| 3 (Transactional) | 18 | Dry-run 1 failed (10 errors); fixed 10+ invented field names across 8 objects. Dry-run 2 + real deploy green. |

Total deploys: 3 dry-run retries + 3 real deploys. All 29 layouts
now live on the SDO.

## Files produced

29 new `.layout-meta.xml` files in
`force-app/main/default/layouts/`:

**Inventory:**
- `Project__c-Project Layout.layout-meta.xml`
- `Tower__c-Tower Layout.layout-meta.xml`
- `Unit__c-Residential Unit Layout.layout-meta.xml`
- `Unit__c-Commercial Shop Layout.layout-meta.xml`
- `Pricing_Component__c-Pricing Component Layout.layout-meta.xml`

**Customer:**
- `Lead-RE CRM Lead Layout.layout-meta.xml`
- `Account-RE CRM Buyer Layout.layout-meta.xml`
- `Account-RE CRM Corporate Buyer Layout.layout-meta.xml`
- `Account-RE CRM Channel Partner Layout.layout-meta.xml`
- `Contact-RE CRM Contact Layout.layout-meta.xml`
- `Site_Visit__c-Site Visit Layout.layout-meta.xml`

**Transactional (18):**
- `Opportunity-RE CRM Pre-sales Layout.layout-meta.xml`
- `Booking__c-Booking Layout.layout-meta.xml`
- `Booking_Customer__c-Booking Customer Layout.layout-meta.xml`
- `Payment_Plan__c-Payment Plan Layout.layout-meta.xml`
- `Payment_Plan_Milestone__c-Payment Plan Milestone Layout.layout-meta.xml`
- `Booking_Payment_Schedule__c-Booking Payment Schedule Layout.layout-meta.xml`
- `Demand__c-Demand Layout.layout-meta.xml`
- `Receipt__c-Receipt Layout.layout-meta.xml`
- `Receipt_Allocation__c-Receipt Allocation Layout.layout-meta.xml`
- `Agreement__c-Agreement Layout.layout-meta.xml`
- `Possession__c-Possession Layout.layout-meta.xml`
- `Snag_Item__c-Snag Item Layout.layout-meta.xml`
- `Commission_Rate_Card__c-Commission Rate Card Layout.layout-meta.xml`
- `Commission_Ledger__c-Commission Ledger Layout.layout-meta.xml`
- `Commission_Payout__c-Commission Payout Layout.layout-meta.xml`
- `Concession_Request__c-Concession Request Layout.layout-meta.xml`
- `Document_Checklist__c-Document Checklist Layout.layout-meta.xml`
- `Notification_Preference__c-Notification Preference Layout.layout-meta.xml`

## Gotchas captured (now in CLAUDE.md)

- **#32** — Layout `<relatedList>` reference format
- **#33** — Formula/RollUp/AutoNumber fields require `Readonly` behavior
- **#34** — AutoNumber Name fields must not be Required on layouts
- **#35** — Layout XSD enforces strict element ordering

Detailed wording in CLAUDE.md.

## Implemented

**Commits**
See `git log --grep='E06-layout'` for the commits that implemented
this epic (two: feat for the 29 layouts, docs for this file +
CLAUDE.md gotchas).

## Phase 2 — Lightning Record Pages (Flexipages)

Phase 1 delivered page layouts for all 26 objects. Phase 2 adds
**Lightning Record Pages (flexipages)** for the 22 custom objects,
so each object has a proper record view with header + tabbed
content + related lists (rather than relying on Salesforce's
auto-generated record page).

### In scope

22 custom-object flexipages, all using `flexipage:recordHomeTemplateDesktop`
as the base template. Each page has:

- **Header** region — `force:highlightsPanel`
- **Main** region — `flexipage:tabset` pointing to a tab facet with:
  - **Details** tab → `force:detailPanel` (renders the page layout
    we deployed in Phase 1)
  - **Related** tab → `force:relatedListContainer`
  - **Activity** tab (only on 6 objects where RMs log activities) →
    `runtime_sales_activities:activityPanel`

**Objects with Activity tab (6):** Booking__c, Demand__c,
Agreement__c, Possession__c, Concession_Request__c, Site_Visit__c.

**Objects without Activity tab (16):** Project__c, Tower__c,
Unit__c, Pricing_Component__c, Booking_Customer__c, Payment_Plan__c,
Payment_Plan_Milestone__c, Booking_Payment_Schedule__c, Receipt__c,
Receipt_Allocation__c, Snag_Item__c, Commission_Rate_Card__c,
Commission_Ledger__c, Commission_Payout__c, Document_Checklist__c,
Notification_Preference__c.

### Out of scope (deferred)

- **Dynamic Forms** (stage/status-based conditional section
  visibility on Opportunity, Booking, Unit, Agreement, Possession).
  The page layouts deployed in Phase 1 are rendered via Record
  Detail; Dynamic Forms rewires that to per-section Field visibility
  rules. Value: cleaner UX. Cost: flexipage XML balloons to
  400-800 lines per object with `<visibilityRule>` + `<criteria>`
  chains. Defer to a UX polish epic.
- **Path component on Opportunity** (shows the current stage visually).
  PathAssistants already exist from E06b, but placing the Path
  component requires either modifying the SDO's existing
  `Opportunity_Record_Page` flexipage (risky — it has SDO-specific
  components we don't want to lose) or creating a new Opportunity
  flexipage and assigning it as org default (overwrites the SDO
  default). Defer; may render automatically on the SDO's default
  Opp page if the SDO template includes a Path region.
- **Standard-object flexipages** (Lead, Account, Contact,
  Opportunity) — the SDO's existing flexipages for these objects
  already render our updated page layouts via their embedded
  Record Detail / force:detailPanel components. No flexipage work
  needed.

### Files produced

22 new flexipages in `force-app/main/default/flexipages/`:
`Agreement_Record_Page`, `Booking_Customer_Record_Page`,
`Booking_Payment_Schedule_Record_Page`, `Booking_Record_Page`,
`Commission_Ledger_Record_Page`, `Commission_Payout_Record_Page`,
`Commission_Rate_Card_Record_Page`, `Concession_Request_Record_Page`,
`Demand_Record_Page`, `Document_Checklist_Record_Page`,
`Notification_Preference_Record_Page`,
`Payment_Plan_Milestone_Record_Page`, `Payment_Plan_Record_Page`,
`Possession_Record_Page`, `Pricing_Component_Record_Page`,
`Project_Record_Page`, `Receipt_Allocation_Record_Page`,
`Receipt_Record_Page`, `Site_Visit_Record_Page`,
`Snag_Item_Record_Page`, `Tower_Record_Page`, `Unit_Record_Page`.

All 114 lines (16 simple) or 143 lines (6 with Activity tab).

### Iteration story (Phase 2)

Four dry-run retries to get the flexipage XML right:

| Attempt | Failure | Fix |
|---|---|---|
| Dry-run 1 | All 22 rejected: `Cannot create a new component with the namespace: Booking_Customer` | Filename `{Object}__c_Record_Page.flexipage-meta.xml` parses the `__c` as a namespace separator. Renamed to `{Object}_Record_Page` (no `__c`). Gotcha #36. |
| Dry-run 2 | All 22 rejected: `The 'sidebar' region specifies mode 'REPLACE' but a parent region enabling that mode doesn't exist` | Template `recordHomeTemplateDesktop` doesn't expose a `sidebar` region to write. Removed sidebar block entirely. |
| Dry-run 3 | All 22 rejected: same error, now on `detailTabContent` Facet | Facets don't support `<mode>Replace</mode>` at all — it's only meaningful for overriding a parent template's regions. Removed `<mode>` from all Facets. |
| Dry-run 4 | All 22 rejected: same error, now on `header` Region | Standalone flexipages (no `<parentFlexiPage>`) can't use `<mode>Replace</mode>` on any region, including top-level Regions. Removed `<mode>` from all regions. Gotchas #37 + #38. |
| Dry-run 5 | — | Green: 22/22 Created |
| Real deploy | — | Green: 22/22 Created, 8.5s |

### Manual Setup steps (Phase 2 addendum)

For each of the 22 custom objects, a one-time Setup UI step to
activate the flexipage as the org-default record page:

1. Setup → Object Manager → `<Object>` → **Lightning Record Pages**
2. Click the `{Object} Record Page` entry
3. Click **Activation** (button at top right)
4. Tab: **Org Default**
5. Click **Assign as Org Default**
6. Select both **Desktop** and **Phone** form factors, click Next → Save
7. Repeat for each of the 22 custom objects

Alternative (if time-permitting): an Apex script using the Tooling
API can programmatically assign each flexipage as org default.
Deferred — 22 Setup UI clicks is a one-time cost per SDO refresh.

### Acceptance criteria (Phase 2 additions)

6. **22 custom-object flexipages deployed** — verified via Tooling
   API query (`FlexiPage` table, 22 new rows with
   `DeveloperName LIKE '%_Record_Page'`).
7. **Each flexipage renders its object's page layout** via
   `force:detailPanel` — manual Sahil verification post-Setup UI
   assignment.
8. **Activity tab renders on the 6 activity-enabled objects** —
   manual verification. Activities must be enabled on the object
   for the tab to work (`<enableActivities>true</enableActivities>`
   in the object XML — verify before trusting Activity tab).

## Known follow-ups

- **Flexipage Dynamic Forms** (dedicated future epic) —
  Opportunity, Booking, Unit, Agreement, Possession get conditional
  section visibility. Also: Path component placement on
  Opportunity record pages (Path exists from E06b, not yet placed).
- **Block Unit Screen Flow + Quick Action** (still deferred
  from E06c).
- **Persona permission set layout visibility audit** — E05b handled
  Admin FLS; personas may need explicit `<recordTypeVisibilities>`
  tightening if they see layouts for RTs outside their scope.
  Verify at E23 rehearsal.
- **Layout deploy cadence for new fields** — any future epic that
  adds a field to an object MUST also update that object's layout
  in the same commit. Otherwise the field deploys but isn't visible
  until a separate layout deploy. Codifies the "deploy field + FLS +
  layout together" discipline from E05b (gotcha #27).
- **Currency locale** and other org-level settings — manual Setup
  step, done once per SDO refresh.
- **Flexipage assignment automation** — if the 22-click manual
  assignment becomes painful at SDO refresh time, write a one-off
  Apex/Tooling-API script to batch-assign flexipages as org defaults.
  `scripts/assign-flexipages.apex` is the obvious landing spot.
