# E03 — Sharing model: OWD, role hierarchy, sharing rules

## Objective

Tighten Organisation-Wide Defaults on the 11 objects that spec calls for,
build the 14-role RECRM hierarchy per Phase 1 Architecture Section 5.2, and
ship the four declarative sharing rules from Section 5.4. After E03, record
visibility is spec-accurate: RMs own leads and opportunities privately,
bookings are private to Post-Sales, the Sales Head sees all bookings
read-only for oversight, and the CP Manager sees CP-sourced records for
attribution.

## Dependencies

- **E02a** (inventory cluster) complete — `Project__c`, `Tower__c`, `Unit__c`
  deployed.
- **E02b** (remaining data model) complete — all objects this epic touches
  (11 OWD targets + 3 sharing rule parents) already exist.
- **E01** (project setup) complete.

## In scope

### Role hierarchy
14 new `RECRM_*` roles built as a standalone tree parallel to the 85
pre-existing stock SDO roles — none of the stock roles are modified,
deleted, or referenced. All new roles share the `RECRM_` prefix for
namespace isolation.

### OWD tightening
11 objects moved off the default `ReadWrite` / `Private` OWD:

| Object | Declared OWD (Internal / External) |
|---|---|
| `Project__c` | Read / Private |
| `Lead` | Private / Private |
| `Account` | Private / Private |
| `Contact` | ControlledByParent / ControlledByParent |
| `Site_Visit__c` | Private / Private |
| `Booking__c` | Private / Private |
| `Payment_Plan__c` | Read / Private |
| `Commission_Rate_Card__c` | Read / Private |
| `Commission_Payout__c` | Private / Private |
| `Notification_Preference__c` | Private / Private |
| `Concession_Request__c` | Private / Private |

The other 15 objects in the data model already had correct OWD from E02a
/ E02b (either by spec or forced by Master-Detail).

### Sharing rules
Four criteria-based sharing rules across three objects:

- `Account.CP_Accounts_Visible_To_RECRM`
- `Booking__c.Bookings_To_Sales_Head`
- `Booking__c.CP_Sourced_Bookings_To_CP_Manager`
- `Opportunity.CP_Sourced_Opps_To_CP_Manager`

## Out of scope (deferred to future epics)

- **Sharing sets for the CP portal** — Section 5.6. Depend on Experience
  Cloud provisioning. **E15**.
- **Apex-managed sharing** — Section 5.5 (three cases: concession
  approver substitution, RM-read on commission ledger, NRI escalation
  desk). Require triggers. **E07–E17**.
- **Permission sets** — **E04**.
- **Tab visibility, profile changes, users, queues** — **E04 / E05**.
- **Per-project refinement of `Bookings_To_Sales_Head`** (Section 5.4
  says "Sales Head's managed projects" — we ship the broader
  "all bookings" version, refined when dashboards land).
- **Agreement / Registration sharing to Legal/Compliance** (Section
  5.4). That role doesn't exist in our 14-role tree; deferred.
- **Manual cross-project RM sharing** — spec explicitly says "manual
  sharing only; no rule". No metadata produced.

## Acceptance criteria

- 14 `RECRM_*` roles present and correctly parented.
- OWD on all 11 targeted objects matches the spec table above (verified
  via declared OWD, since `EntityDefinition` misreports Contact — see
  Implementation notes).
- 4 sharing rules deploy active.
- Deploy completes from source with `--test-level NoTestRun` via
  `./scripts/deploy.sh re-crm-sdo --skip-validate`.
- Role hierarchy does not break any existing stock role or sample-data
  user.

## Non-functional

- Fully redeployable from source on a fresh SDO in a single deploy; no
  manual Setup-UI steps required (Contact OWD quirk resolved in source —
  see deployment story).
- No impact on existing 85 stock roles or their users.

## Artefacts to produce

See **Implemented** below.

## Implementation notes

- **Contact CBP requires both `<sharingModel>` AND
  `<externalSharingModel>` in source XML on external-sharing-enabled
  orgs.** A 5-line file with only `<sharingModel>ControlledByParent
  </sharingModel>` deploys successfully but silently coerces to Private
  because the implied pair (CBP internal, unchanged external = Private)
  is invalid. See CLAUDE.md gotcha #11.
- **`EntityDefinition.InternalSharingModel` misreports Contact OWD.**
  For Contact specifically, it surfaces the *effective* sharing after
  Account-parent propagation, not the declared OWD. Setup UI is
  authoritative. See CLAUDE.md gotcha #12.
- **`RecordTypeId` sharing rule criteria expect the RT *Label*, not the
  DeveloperName.** Our Account Channel_Partner RT has Label `Channel
  Partner` (space) and DeveloperName `Channel_Partner` (underscore).
  The sharing rule value is the space-form.
- **Cross-object formula fields are ineligible for sharing rule
  criteria.** `Booking__c.Project__c` is `Formula(Text)` traversing
  `Unit__r.Tower__r.Project__r.Project_Code__c` — Salesforce rejects it
  with "not valid workflow field".
- **Lookup-to-Account fields are ineligible for sharing rule criteria.**
  Both `Booking__c.Source_CP__c` and `Opportunity.Source_CP__c` are
  Lookup(Account) and get the same "not valid workflow field"
  rejection. The Picklist `Source_Channel__c` with value `CP` is the
  substitute — semantic scope is identical because every CP-sourced
  record has that value set.
- **`EntityDefinition.InternalSharingModel` reads are cached 30–60s
  after a metadata deploy.** Post-deploy verification queries run
  immediately can show stale values. Poll with a short loop rather than
  trusting the first read.

## Implemented

**Commits**
See `git log --grep='E03'` for the commits that implemented this epic.
(SHAs not embedded — amending a commit changes its SHA, so embedded SHAs would always be stale.)

**Deployed to** `re-crm-sdo` on 2026-04-22 across one full-batch deploy
and one follow-up Contact-only deploy. Verified via SOQL
(`EntityDefinition`, `UserRole`) and Setup UI (Contact OWD).

### Files produced

**Roles — 14 files** under `force-app/main/default/roles/` (each with
`caseAccessLevel=Edit`, `contactAccessLevel=Edit`,
`opportunityAccessLevel=Read`, `mayForecastManagerShare=false`):

- `RECRM_CEO.role-meta.xml` (no parent — top of tree)
- `RECRM_VP_Sales.role-meta.xml` (parent `RECRM_CEO`)
- `RECRM_Sales_Head.role-meta.xml` (parent `RECRM_VP_Sales`)
- `RECRM_PSM_PRK.role-meta.xml` (parent `RECRM_Sales_Head`)
- `RECRM_RM_Team_PRK.role-meta.xml` (parent `RECRM_PSM_PRK`)
- `RECRM_PSM_SPL.role-meta.xml` (parent `RECRM_Sales_Head`)
- `RECRM_RM_Team_SPL.role-meta.xml` (parent `RECRM_PSM_SPL`)
- `RECRM_PSM_Commercial.role-meta.xml` (parent `RECRM_Sales_Head`)
- `RECRM_RM_Team_Commercial.role-meta.xml` (parent `RECRM_PSM_Commercial`)
- `RECRM_Head_Of_Post_Sales.role-meta.xml` (parent `RECRM_VP_Sales`)
- `RECRM_Post_Sales_Team_Lead.role-meta.xml` (parent `RECRM_Head_Of_Post_Sales`)
- `RECRM_Post_Sales_Exec.role-meta.xml` (parent `RECRM_Post_Sales_Team_Lead`)
- `RECRM_Head_Of_CPs.role-meta.xml` (parent `RECRM_VP_Sales`)
- `RECRM_CP_Manager.role-meta.xml` (parent `RECRM_Head_Of_CPs`)

Rationale for the standalone tree: per Step 1 discovery, no stock SDO
role (Omega/Ohana/Zenith/VP Sales/West Sales/etc.) needs visibility to
RE CRM data. Coexisting cleanly beats either deleting 85 roles (breaks
stock sample-data users) or grafting onto a stock parent (muddies the
hierarchy).

**OWD — 11 object XMLs:**

Custom-object edits (8 files):
- `Project__c/Project__c.object-meta.xml` — `Read / Private`
- `Site_Visit__c/Site_Visit__c.object-meta.xml` — `Private / Private`
- `Booking__c/Booking__c.object-meta.xml` — `Private / Private`
- `Payment_Plan__c/Payment_Plan__c.object-meta.xml` — `Read / Private`
- `Commission_Rate_Card__c/Commission_Rate_Card__c.object-meta.xml` — `Read / Private`
- `Commission_Payout__c/Commission_Payout__c.object-meta.xml` — `Private / Private`
- `Notification_Preference__c/Notification_Preference__c.object-meta.xml` — `Private / Private`
- `Concession_Request__c/Concession_Request__c.object-meta.xml` — `Private / Private`

Standard-object new OWD-only XMLs (3 files):
- `Lead/Lead.object-meta.xml` — `Private / Private`
- `Account/Account.object-meta.xml` — `Private / Private`
- `Contact/Contact.object-meta.xml` — `ControlledByParent / ControlledByParent`

**Sharing rules — 3 files** under `force-app/main/default/sharingRules/`:

- `Account.sharingRules-meta.xml` — 1 rule (`CP_Accounts_Visible_To_RECRM`):
  - Criteria: `RecordTypeId equals 'Channel Partner'` (Label, not DeveloperName)
  - `sharedTo`: `roleAndSubordinates = RECRM_CEO`
  - Access: Read
  - `accountSettings`: caseAccess=None, contactAccess=Read, opportunityAccess=None
  - Rationale: Account OWD is Private to protect Buyer records; this rule re-opens CP-record-type Accounts to the entire RECRM hierarchy since CP master is internal reference data.

- `Booking__c.sharingRules-meta.xml` — 2 rules:
  - `Bookings_To_Sales_Head`
    - Criteria: `Booking_Date__c notEqual null` (matches every Booking since Booking_Date is required; originally spec'd as `Project__c notEqual null` but Project__c is a cross-object formula — see deviations)
    - `sharedTo`: `roleAndSubordinates = RECRM_Sales_Head`
    - Access: Read
  - `CP_Sourced_Bookings_To_CP_Manager`
    - Criteria: `Source_Channel__c equals 'CP'` (originally spec'd as `Source_CP__c notEqual null` but Lookup-to-Account is ineligible — see deviations)
    - `sharedTo`: `roleAndSubordinates = RECRM_CP_Manager`
    - Access: Read

- `Opportunity.sharingRules-meta.xml` — 1 rule:
  - `CP_Sourced_Opps_To_CP_Manager`
    - Criteria: `Source_Channel__c equals 'CP'` (originally spec'd as `Source_CP__c notEqual null`)
    - `sharedTo`: `roleAndSubordinates = RECRM_CP_Manager`
    - Access: Read

### Counts summary

| Category | Count |
|---|---|
| Roles | 14 |
| OWD XMLs touched | 11 (8 custom-object edits + 3 new standard-object OWD-only files) |
| Sharing rule metadata files | 3 |
| Sharing rules (total) | 4 |
| Public groups | 0 (dropped — see deviations) |

### Deployment story

Three deploy attempts to reach green.

**Attempt 1 — 432/437 components, 5 failures:**
1. `Group.All_Internal_Users` — `<roles>` element invalid in source-format Group XML. Group membership isn't serialised in `.group-meta.xml` — it's set via Setup UI or separately.
2. `Account.CP_Accounts_Visible_To_Internal` — failed downstream of #1 (Group not found).
3. `Booking__c.Bookings_To_Sales_Head` — `Project__c` is a cross-object `Formula(Text)`; ineligible for sharing rule criteria.
4. `Booking__c.CP_Sourced_Bookings_To_CP_Manager` — `Source_CP__c` is Lookup(Account); ineligible.
5. `Opportunity.CP_Sourced_Opps_To_CP_Manager` — same Lookup issue.

**Attempt 2 — 435/436 components, 1 failure:**
- `Account.CP_Accounts_Visible_To_RECRM` — `Picklist value does not exist` on `<value>Channel_Partner</value>`. Fix: use the RT Label `Channel Partner` (space) instead of the DeveloperName `Channel_Partner` (underscore). Sharing rule criteria on `RecordTypeId` expect the Label.

**Attempt 3 — green.** All 437+ components deployed.

**Attempt 4 — Contact-only follow-up.** Post-green, `EntityDefinition`
showed Contact as `Private / Private` instead of the spec'd CBP / CBP.
Root cause: the original `Contact.object-meta.xml` declared only
`<sharingModel>ControlledByParent</sharingModel>`; on an
external-sharing-enabled org this implied the pair (CBP internal,
unchanged external = Private), which is invalid, and Salesforce
silently coerced the internal side to Private. Adding
`<externalSharingModel>ControlledByParent</externalSharingModel>`
resolved it. Setup UI confirmed Contact OWD as Controlled by Parent /
Controlled by Parent post-fix — `EntityDefinition` continues to show
Private because it surfaces effective sharing after Account-parent
propagation, not declared OWD.

### Deviations from spec

1. **Public Group dropped in favour of `roleAndSubordinates=RECRM_CEO`
   on the `CP_Accounts_Visible_To_RECRM` rule.** Rationale:
   `force-app/main/default/groups/<Name>.group-meta.xml` doesn't
   support role-membership declaration in source format. A group file
   with `<roles>` entries fails to deploy; a bare group file
   (doesIncludeBosses + name only) deploys but requires manual Setup
   UI clicks to add members — that's a manual-setup-step we can avoid
   entirely by using `roleAndSubordinates = RECRM_CEO`, which cascades
   to all 13 descendant roles. Same effective scope, zero
   manual-setup-steps, fully redeployable.

2. **`Bookings_To_Sales_Head` criterion changed from
   `Project__c notEqual null` to `Booking_Date__c notEqual null`.**
   Both match every Booking (Project__c is always derived,
   Booking_Date__c is required), but the original uses a cross-object
   formula field which sharing rules reject. Booking_Date__c is a real
   Date field and eligible.

3. **`CP_Sourced_Bookings_To_CP_Manager` and
   `CP_Sourced_Opps_To_CP_Manager` criteria changed from
   `Source_CP__c notEqual null` to `Source_Channel__c equals 'CP'`.**
   `Source_CP__c` is Lookup(Account); sharing rules reject Lookup-to-
   Account fields in criteria. `Source_Channel__c` is a Picklist with
   `CP` as one of its 10 values (per E02b Lead Source Taxonomy); every
   CP-sourced record has that exact value set. Semantic scope is
   identical.

4. **`CP_Accounts_Visible_To_Internal` renamed to
   `CP_Accounts_Visible_To_RECRM`** to reflect the shared-to change
   (RECRM hierarchy root `RECRM_CEO` rather than a generic "All
   Internal Users" group).

5. **`CP_Accounts_Visible_To_RECRM` RT criterion uses the Label
   `Channel Partner` (with space), not the DeveloperName
   `Channel_Partner` (with underscore).** Sharing rule criteria on
   `RecordTypeId` expect the Label for the `<value>` element.
   Undocumented Salesforce quirk.

6. **Contact OWD XML ships with both `<sharingModel>` AND
   `<externalSharingModel>` explicitly.** Required on external-
   sharing-enabled orgs to avoid silent coercion to Private.

7. **`EntityDefinition.InternalSharingModel` misreports Contact.**
   Declared OWD on Contact is Controlled by Parent (verified in Setup
   UI); EntityDefinition reports Private. This is a Contact-specific
   reporting quirk — the query returns effective sharing after
   Account-parent propagation, not the declared OWD. All 10 other
   OWD targets in this epic report correctly.

### Manual Setup steps (if any)

None.

### Known follow-ups for later epics

- **E04**: permission sets per persona (RM, PSM, Sales Head, Post-Sales
  Exec, CP Manager, Inventory Admin).
- **E05**: assignment rules + queues (Post-Sales queue on Booking,
  CP Manager queue on Lead).
- **E07–E17**: Apex-managed sharing for the three Section 5.5 cases.
- **E15**: Sharing Sets + LWC SOQL isolation for the CP portal.
- **E20 or later**: refine `Bookings_To_Sales_Head` from all-bookings
  to per-project once Sales Head → managed-projects mapping exists.
- **Future**: Agreement / Registration sharing to Legal/Compliance role
  once that role is added to the hierarchy.
