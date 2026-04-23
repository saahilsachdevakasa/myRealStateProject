# E06-apps — Lightning Apps (persona-scoped)

## Objective

Create the 4 internal Lightning Apps defined in Phase 1 Architecture
Section 4.3. Each app is a persona-scoped nav-bar layout grouping the
tabs relevant to one user type (RM/PSM, Post-Sales Exec, CP Manager,
Inventory Admin). After this epic, the App Launcher presents 4
purpose-built apps instead of a single generic one.

## Dependencies

- **E02a, E02b** — all 14 custom tabs exist (plus 2 more created in
  this epic: Booking_Payment_Schedule and Pricing_Component).
- **E04** — persona permission sets exist (app-visibility
  restrictions per profile/permset are deferred, so no hard
  dependency on the permission set structure; the apps deploy
  visible to all profiles with Admin access).
- **E06-layout** — page layouts + flexipages render correctly inside
  the apps. Without layouts, the app tabs would open empty forms.

## In scope

### 4 Lightning Apps

All 4 use:
- `<navType>Standard</navType>` (standard nav bar, not console)
- `<formFactors>Large, Small</formFactors>` (desktop + mobile)
- `<defaultLandingTab>standard-home</defaultLandingTab>`
- `<uiType>Lightning</uiType>`

| App DeveloperName | Label | Tabs |
|---|---|---|
| `RE_CRM` | Real Estate CRM | Home, Lead, Opportunity, Site Visit, Project, Unit, Booking, Demand, Receipt, Report, Dashboard |
| `Post_Sales_CRM` | Post-Sales CRM | Home, Booking, Booking Payment Schedule, Demand, Receipt, Agreement, Possession, Concession Request, Report |
| `Channel_Partner_Mgmt` | Channel Partners (Mgmt) | Home, Account, Commission Rate Card, Commission Ledger, Commission Payout, Report |
| `Inventory_and_Pricing` | Inventory & Pricing | Home, Project, Tower, Unit, Pricing Component, Payment Plan |

### 2 new Custom Tabs (required by the apps above)

- `Booking_Payment_Schedule__c` — referenced by Post_Sales_CRM
- `Pricing_Component__c` — referenced by Inventory_and_Pricing

Discovery found that these two custom-object tabs didn't exist
(only 14 tabs in source, per E05b's discovery). Created as minimal
5-line CustomTab XML (customObject=true, motif=Custom25: Case,
matching the pattern of existing tabs). Deployed alongside the apps.

## Out of scope (deferred)

- **CP Portal app** (Experience Cloud) — separate epic
  (E15 or E16 in the planned architecture). Not a Lightning App;
  it's an Experience Builder site.
- **App visibility restrictions per profile/permset** — currently
  all 4 apps are visible to any profile with Lightning access (i.e.,
  every user). Scoping apps to personas (e.g., only Post-Sales Execs
  can see Post_Sales_CRM) is a Setup UI step via
  `Setup → Apps → App Manager → <App> → Edit → User Profiles`.
  Deferred to E23 polish pass.
- **App branding** (`<brand>` with logo + header colour) — SDO
  default colours are fine for demo; custom branding is a
  polish item.
- **`actionOverrides` on apps** — SDO apps override record-detail
  views to custom flexipages per app. For our simple apps,
  the default Org-Default flexipages (from E06-layout Phase 2) are
  sufficient; no per-app override needed.
- **Admin profile tab visibility update for the 2 new tabs** — the
  tabs deploy with default visibility (Available-but-not-DefaultOn).
  To appear pre-selected in the nav bar, they'd need to be added
  to Admin profile's `tabVisibilities` block (like the 14 E05b
  tabs). Manual Setup alternative: open each app, click the pencil
  icon on the nav bar, drag the tab in. Documented below.

## Iteration story

Single deploy pass:

| Step | Outcome |
|---|---|
| Dry-run (4 apps + 2 tabs) | Green — 6/6 Created, 4.03s |
| Real deploy | Green — 6/6 Created (CLI cosmetic "Missing message" error per gotcha #31; `deploy report --json` confirmed Status=Succeeded, 0 errors) |
| Verification | `SELECT FROM CustomApplication` returned all 4 apps with correct labels |

No retries. Clean end-to-end.

## Files produced

- `force-app/main/default/applications/RE_CRM.app-meta.xml`
- `force-app/main/default/applications/Post_Sales_CRM.app-meta.xml`
- `force-app/main/default/applications/Channel_Partner_Mgmt.app-meta.xml`
- `force-app/main/default/applications/Inventory_and_Pricing.app-meta.xml`
- `force-app/main/default/tabs/Booking_Payment_Schedule__c.tab-meta.xml`
- `force-app/main/default/tabs/Pricing_Component__c.tab-meta.xml`

## Acceptance criteria

1. **4 apps deployed** — verified via Tooling API
   (`SELECT DeveloperName, Label FROM CustomApplication WHERE
   DeveloperName IN (4 values)`), returned 4 rows with correct
   Labels.
2. **2 new custom tabs deployed** — implicitly verified by app
   deploy (apps would fail on non-existent tab references).
3. **No existing app/tab clobbered** — all 6 components show
   State=Created, no Changed/Deleted.
4. **Apps appear in App Launcher** — manual verification by Sahil.

## Manual Setup steps (post-deploy)

### Verify app navigation
1. Sahil: log in to re-crm-sdo.
2. Click the App Launcher (9-dot grid, top-left).
3. Confirm the 4 RE CRM apps appear:
   Real Estate CRM, Post-Sales CRM, Channel Partners (Mgmt),
   Inventory & Pricing.
4. Click each, verify:
   - The tabs appear in the nav bar (in the order defined).
   - Clicking a custom tab (e.g., Booking) opens the list view.
   - Home tab renders correctly (standard Home component).

### Tab visibility (if custom tabs don't appear in nav bar)

If the 2 new tabs (Booking Payment Schedule, Pricing Component)
don't appear in the Post_Sales_CRM / Inventory_and_Pricing nav bars:

- **Option A (per-user):** click the pencil icon on the nav bar in
  the app, "Add More Items", drag the tab in, save.
- **Option B (admin profile):** Setup → Profiles → System
  Administrator → Object Settings → `<Object>` → Tab Settings →
  "Default On". (Adds them to the default nav bar for all users
  with Admin profile.)
- **Option C (metadata):** add `<tabVisibilities>` blocks to
  `Admin.profile-meta.xml` for the 2 new tabs. Same pattern as
  the 14 E05b tabs. Defer to when touching the Admin profile
  again for other reasons.

### App visibility per profile/permset (E23 polish)

For the full persona scoping (e.g., RM only sees RE_CRM,
Post-Sales Exec only sees Post_Sales_CRM):

Setup → Apps → App Manager → `<App>` → Edit → User Profiles →
check the profiles that should see this app, uncheck others.

Defer until E23 demo rehearsal. For MVP demo, all personas seeing
all 4 apps is acceptable (users can self-select the right one).

## Implemented

**Commits**
See `git log --grep='E06-apps'` for the commits that implemented
this epic (two: feat for the 6 components, docs for this file).

## Known follow-ups

- **App visibility per persona** — deferred to E23.
- **Admin profile tabVisibilities update** for the 2 new tabs —
  deferred; fold into the next Admin profile edit.
- **App branding** — polish pass; SDO default branding is fine
  for demo.
- **CP Portal Experience Cloud site** — E15/E16.
