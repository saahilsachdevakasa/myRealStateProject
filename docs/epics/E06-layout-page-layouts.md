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

## Known follow-ups

- **Flexipages with Dynamic Forms** (dedicated future epic) —
  Opportunity, Booking, Unit, Agreement, Possession get conditional
  section visibility. Also: Path component placement on
  Opportunity record pages.
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
