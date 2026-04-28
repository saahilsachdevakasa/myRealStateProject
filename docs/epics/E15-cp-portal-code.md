# E15 — Channel Partner Portal (Code)

## Goal

The Apex + LWC layer of the CP Portal: a single security utility
(`CP_Scope`), 6 portal Apex controllers, and 6 portal LWCs, all
wired together so that an authenticated portal user only ever sees
data for their own CP Account. Page assembly and Experience Cloud
site creation are E16 (manual SDO setup).

## Architecture — defense in depth

Every portal request goes through three independent isolation
layers:

```
                      Portal user → LWC
                            │
                            ▼  (cacheable @AuraEnabled)
              ┌────────────────────────────────┐
              │   Cp{Page}Controller           │
              │   FIRST line:                  │
              │     Id cpId = CP_Scope         │
              │       .getCpAccountId();       │
              │                                │
              │   SOQL filters: WHERE          │
              │     <link>__c = :cpId          │
              │   AND  WITH SECURITY_ENFORCED  │  ◀── Layer 1
              │                                │
              │   Returns wrapper class        │  ◀── Layer 2
              │     (not raw SObject)          │
              └────────────┬───────────────────┘
                           │
                           ▼
              ┌────────────────────────────────┐
              │   CP_Scope                     │  ◀── Layer 3
              │   User → Contact → Account     │     (Identity
              │   No raw UserInfo in           │      lookup)
              │   business queries             │
              └────────────────────────────────┘
```

- **Layer 1 — SOQL scope**: every business query filters on
  `Source_CP__c = :cpId` (Lead, Booking) or
  `Channel_Partner__c = :cpId` (Ledger, Payout) or
  `Lead__r.Source_CP__c = :cpId OR Opportunity__r.Source_CP__c = :cpId`
  (Site_Visit). `WITH SECURITY_ENFORCED` rejects the query if any
  selected field lacks FLS for the running portal user.
- **Layer 2 — Wrapper classes**: every controller returns a
  controlled inner class (LeadData, VisitData, LedgerData,
  PayoutData, DashboardData, CommissionSummary) — never raw
  SObjects. Adding a sensitive field to the underlying object
  doesn't accidentally expose it through the portal because only
  the wrapper's whitelisted fields cross the LWC boundary.
- **Layer 3 — `CP_Scope.getCpAccountId()`**: the only sanctioned
  way for a portal controller to learn whose data to return. Goes
  User → Contact → Account; throws AuraHandledException if any link
  is missing. Internal users (no ContactId) are rejected.

## Implemented

### Apex (14 classes, 28 files)

- **`CP_Scope.cls`** — `with sharing`, `WITH SECURITY_ENFORCED` on
  the User and Contact lookups. `@TestVisible private static Id
  testCpAccountId` enables tests to inject a CP Id without
  spinning up a real portal user. `getCpAccountId()` honours the
  test override; `currentCpAccountId()` is the real path.

- **6 portal controllers**, all `with sharing`, all start with
  `Id cpId = CP_Scope.getCpAccountId()`, all use
  `WITH SECURITY_ENFORCED` on every SOQL, all return wrapper classes:

  | Controller | Wrapper | Page |
  |---|---|---|
  | `CpDashboardController` | `DashboardData{leadCount, activeBookings, ytdCommission, pendingPayouts}` | Dashboard |
  | `CpLeadListController` | `LeadData[]` | My Leads |
  | `CpSubmitLeadController` | `getActiveProjects() → ProjectOption[]`; `submitLead(...) → Id` | Submit Lead |
  | `CpSiteVisitsController` | `VisitData[]` | Site Visits |
  | `CpCommissionsController` | `CommissionSummary{entries[], totalGross, totalNet, totalAccrued, totalPaid}` | Commissions |
  | `CpPayoutsController` | `PayoutData[]` | Payouts |

  All read-paths are `@AuraEnabled(cacheable=true)`; only the
  write-path (`submitLead`) is non-cacheable.

- **`CpSubmitLeadController.submitLead`** signature:
  `(String firstName, String lastName, String phone, String email,
   Id projectId, List<String> unitPreferences, String notes) → Id`.
  `unitPreferences` is server-side joined with `';'` for the
  `Unit_Type_Preference__c` MultiselectPicklist. `Source_Channel__c`
  is hardcoded to `'CP'`; `Source_CP__c` is set from `CP_Scope`.

- **`CpSiteVisitsController`** uses an `OR` clause to scope visits
  via either `Lead__r.Source_CP__c` or `Opportunity__r.Source_CP__c`
  — covers the lead and post-conversion phases of the same buyer
  journey.

### LWC (6 bundles, 20 files)

All target both `lightningCommunity__Page` (portal placement) and
`lightning__RecordPage` (internal review). Targets use the modern
namespace (`lightningCommunity__*`, not `lightning__CommunityPage`
which the SDO doesn't recognize — captured as gotcha #44 below).

| Bundle | Files | Notable technique |
|---|---|---|
| `cpDashboard` | 4 (js+html+css+meta) | 2×2 metric grid with INR formatting |
| `cpLeadList` | 3 (js+html+meta) | `lightning-datatable` + `NavigationMixin` row click → Lead detail |
| `cpSubmitLead` | 3 | Imperative Apex (write), `lightning-checkbox-group` for Unit_Type, `ShowToastEvent`, navigates to created Lead |
| `cpSiteVisits` | 3 | Datatable with date+time formatting |
| `cpCommissions` | 4 (+css) | Summary tiles + datatable, currency type with INR |
| `cpPayouts` | 3 | Datatable with currency columns, UTR field |

### Test coverage — 17 new tests, all isolation-aware

Every controller test class has a baseline test plus an explicit
**bidirectional isolation test** (`testCpIsolation_BothDirections`)
that flips `CP_Scope.testCpAccountId` between two CP accounts and
asserts each only sees its own data. This is the Section 12.2
isolation matrix translated into Apex.

| Test class | Tests | Notes |
|---|---|---|
| `CP_ScopeTest` | 3 | Override path, no-Contact throws, direct call throws |
| `CpDashboardControllerTest` | 2 | Happy path + empty data |
| `CpLeadListControllerTest` | 2 | Baseline + bidirectional isolation |
| `CpSubmitLeadControllerTest` | 4 | Active projects filter, happy path, missing LastName throws, no preferences |
| `CpSiteVisitsControllerTest` | 2 | Baseline + bidirectional isolation |
| `CpCommissionsControllerTest` | 2 | Baseline + bidirectional isolation |
| `CpPayoutsControllerTest` | 2 | Baseline + bidirectional isolation |

**Full regression: 98 / 98 pass** (17 new + 81 existing across all
service test suites).

## Non-obvious decisions

- **`testCpAccountId` override mechanism, not real portal users.**
  Creating a portal user in tests is heavyweight (requires Profile
  + license + Contact under a CP Account). The `@TestVisible`
  static override gives identical isolation semantics without the
  setup cost — tests directly assert that controller queries scope
  correctly, which is the actual security guarantee. Real portal
  users are exercised in E16's manual demo walkthrough.

- **`Site_Visit__c.Source_Channel__c` is a formula** that derives
  from `Lead__r.Source_Channel__c` or `Opportunity__r.Source_Channel__c`
  depending on which parent is populated. Tests can't write to it
  (caught at deploy as `Field is not writeable`); just leave it
  unset and let the formula compute.

- **Modern Experience Cloud target**: `lightningCommunity__Page`
  works, the older `lightning__CommunityPage` does not (gotcha #44).
  The component bundles also include `lightning__RecordPage` so the
  same components can be placed on internal record pages for
  Pre-Sales Manager / Sales Head review without duplicating code.

- **`CpDashboard.YTD` vs `Pending`**: YTD sums Gross_Commission for
  ledger entries with `Milestone_Date__c >= startOfYear` (regardless
  of status — what was earned). Pending sums Net_Payable for
  Accrued/Approved entries (regardless of date — what's owed but
  unpaid). Two different rollups, two different SOQL passes.

- **Wrapper classes have `@AuraEnabled` on the inner class type AND
  every property** — required for the LWC layer to deserialize them.
  Pattern matches the existing E15 internal LWCs.

## E16 — Manual setup walkthrough (deferred to Setup UI)

E15 ships portal *code* but no portal *site*. E16 is a guided
walkthrough in Setup UI that produces:

### 1. Enable Digital Experiences (one-time)

Setup → Digital Experiences → Settings → check **Enable Digital
Experiences**. Choose a domain (e.g., `re-crm-sdo-cp.my.site.com`).

### 2. Create the CP Portal site

Setup → All Sites → New →

- Template: **Build Your Own (LWR)** — modern LWC-first template
- Site name: `CP Portal`
- URL suffix: `cp`

LWR-only because the legacy Aura templates don't accept
`lightningCommunity__Page` LWC bundles natively.

### 3. Configure sharing for portal users

Setup → Sharing Settings →

- **OWD on Account, Contact, Lead, Booking__c, Commission_Ledger__c,
  Commission_Payout__c, Site_Visit__c**: Private (internal),
  Private (external).
- **Sharing Sets** (Setup → Digital Experiences → All Sites → CP
  Portal → Workspaces → Administration → Sharing Sets):
  - One sharing set per object (Lead, Booking, etc.) granting Read
    access where `Object.Source_CP__c = $User.Contact.AccountId`.
  - Avoids per-record sharing rules (which scale poorly to 100s
    of CPs).
- These sharing sets are the *infrastructure* layer; CP_Scope's
  SOQL filter is the *application* layer; `WITH SECURITY_ENFORCED`
  is the *FLS* layer. All three must hold for the portal to be
  secure.

### 4. Place LWCs on portal pages

In Experience Builder, create 6 pages and drop the matching LWC
into each:

| Page URL | Component |
|---|---|
| `/dashboard` | `cpDashboard` |
| `/my-leads` | `cpLeadList` |
| `/submit-lead` | `cpSubmitLead` |
| `/site-visits` | `cpSiteVisits` |
| `/commissions` | `cpCommissions` |
| `/payouts` | `cpPayouts` |

Add a navigation menu linking the 6 pages.

### 5. Create a Channel Partner Permission Set

A new permset `CP_Portal_User` granting:
- Read access on Account, Contact, Lead, Booking__c, Site_Visit__c,
  Commission_Ledger__c, Commission_Payout__c, Project__c
- Create access on Lead (for the submitLead flow)
- FLS read on every field listed in the controller wrapper classes
  (LeadData fields, BookingData fields, etc.) — explicit, not
  default. Per gotcha #27, custom fields default to no FLS even on
  Admin.
- Apex class access for `CpDashboardController`,
  `CpLeadListController`, `CpSubmitLeadController`,
  `CpSiteVisitsController`, `CpCommissionsController`,
  `CpPayoutsController`, `CP_Scope`.

### 6. Create the demo CP portal user

Setup → Users → New User on the **Acme Realty Advisors** Account
→ create a Contact → enable as Customer Community User →
license type "Customer Community Plus" (or whichever the SDO has).
Assign the `CP_Portal_User` permission set.

Login URL: the site's domain. Demo: log in as Acme's portal user
and verify the dashboard shows Acme's 1 booking and 3 ledger
entries seeded in E17.

### 7. CP isolation smoke test

Create a second portal user under **Prime Properties** Account.
Log in as Prime — dashboard should show **0 leads, 0 bookings,
0 commissions**. This is the live equivalent of the test-class
isolation tests.

## Out of scope

- **PDF download for payout statements** (`Statement_PDF_Id__c` on
  Commission_Payout) — UI button + ContentVersion download wiring
  is E23 polish.
- **Lead handoff notification** to Pre-Sales when a CP submits a
  lead — currently the Lead is created with `Status='New'` and
  ownership defaults; routing/assignment rules are E16 polish.
- **Custom branding** (logo, color palette) — Setup-UI step in
  Experience Builder, deferred to E16 walkthrough.
- **Per-CP rate transparency** — the cpCommissions component shows
  rates already applied to the CP's own ledger entries. A "browse
  rate cards" page (showing the CP what they could earn on
  hypothetical bookings) is a future enhancement.

## New gotcha to capture (#44)

- **`lightning__CommunityPage` target name is rejected** by the
  Lightning component bundle XSD on this SDO; the modern target
  name is `lightningCommunity__Page` (note the namespace separator
  underscore is *single*, not double). Same applies to
  `lightningCommunity__Default`. Existing internal LWCs only use
  `lightning__RecordPage` so this didn't surface until E15 first
  declared a community target. If a deploy fails with
  `lightning__CommunityPage is not a valid TARGETS`, sed-replace
  to `lightningCommunity__Page` across all `*.js-meta.xml` files
  in the bundle.
