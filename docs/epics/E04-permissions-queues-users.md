# E04 — Permission Sets, Queues, Demo Users

## Objective

Stand up the access layer on top of E03's sharing model. After E04, every
role in the `RECRM_*` hierarchy has a matching permission set granting the
right object/field access, two functional queues (Post-Sales and CP
Manager) are wired to the right objects, and seven demo users exist with
login credentials for the rehearsal demo. Internal users can finally do
work against the org — before E04, only System Admin could touch
anything.

## Dependencies

- **E03** (sharing model) complete — 14 `RECRM_*` roles in the org, OWD
  tightened on 11 objects, 4 sharing rules deployed. All referenced by
  permission-set grants and queue members.
- **E02a + E02b** (data model) complete — every object a permission set
  touches is already deployed.
- **E01** (project setup) complete.

## In scope

### 6 Permission sets (per-persona)
- `RECRM_Inventory_Admin` — CRUD on Project, Tower, Unit, Payment_Plan +
  Milestone, Commission_Rate_Card. Read-only on Booking (dependency).
- `RECRM_CP_Manager` — CRUD on Account (CP RT), all commission objects.
  Read on Contact, Booking, Opportunity, Unit, Tower, Project,
  Payment_Plan.
- `RECRM_RM` — CRUD on Lead, Opportunity, Site_Visit, Concession_Request,
  Notification_Preference. Read on Account, Contact, Unit, Project,
  Tower, Booking, Payment_Plan.
- `RECRM_PSM` — identical object/field scope as `RECRM_RM`; approval-tier
  differences live in E05.
- `RECRM_Sales_Head` — identical object/field scope as `RECRM_RM` and
  `RECRM_PSM`; escalation-tier differences live in E05.
- `RECRM_Post_Sales_Exec` — CRUD on Booking and all its downstream
  children (Demand, Receipt, BPS, Agreement, Possession, Snag,
  Doc_Checklist, junctions, Pricing_Component). Read on Opportunity,
  Account, Contact, Unit, Project, Tower, Payment_Plan.

### 2 Queues
- `Post_Sales_Queue` — Booking__c queue; members `RECRM_Post_Sales_Team_Lead`
  + `RECRM_Post_Sales_Exec` roles.
- `CP_Manager_Queue` — Lead queue; member `RECRM_CP_Manager` role.

### 7 Demo users
One per persona, plus two RMs (PRK + SPL). All on Profile `Minimum Access
- Salesforce`, India locale/timezone, `@recrm-demo.invalid` emails.
Seeded idempotently via `scripts/seed-demo-users.apex`.

## Out of scope (deferred)

- **Assignment rules** — lead/case/booking routing to queues and
  round-robin within queues. **E05**.
- **Approval processes** — concession request approval hierarchy (PSM
  then Sales Head). **E10**.
- **FLS tightening** — for MVP, every permission set grants Read+Edit on
  every field of every accessible object. Production hardening (sensitive
  field masking for specific personas) is a post-MVP concern.
- **Custom app assignments** — `applicationVisibilities`. The apps
  themselves don't exist yet; come with their respective feature epics.
- **Real user emails / SSO / MFA** — .invalid TLD is safe for demo; real
  email and identity wiring is a Phase-2 production concern.
- **Production password policy** — the SDO's org-level password policy
  allows short passwords; fine for demo. Production requires a different
  policy (min 10+ chars, complexity, rotation).

## Acceptance criteria

1. All 6 `RECRM_*` permission sets deployed, each on license `Salesforce`,
   each with `IsOwnedByProfile=false`.
2. Both queues present as `Group` records with `Type='Queue'`, bound to
   the correct `SobjectType` via `QueueSobject`, with role-based
   `GroupMember` entries matching the spec.
3. 7 demo users exist, active, with correct role (or null for
   Inventory_Admin) and Profile. 7 `PermissionSetAssignment` rows bind
   each user to the correct persona permission set.
4. Seed and delete scripts are idempotent — re-running either produces
   no duplicate records or missed cleanups.

## Non-functional

- Single-deploy redeployability: all metadata in `force-app/` can be
  redeployed on a fresh SDO in one shot. Apex scripts run separately
  (they're anonymous Apex, not metadata).
- Seed script run on a fresh post-deploy SDO completes in seconds.

## Artefacts produced

See **Implemented** below.

## Implementation notes

### Design decisions (locked before execution)

- **Profile strategy.** All 7 internal demo users use the stock `Minimum
  Access - Salesforce` profile. No custom profiles. All capabilities come
  from permission sets. Reason: stock profile is redeployable from
  source-free; eliminates one moving part.
- **Permission-set granularity.** Per-persona (6 sets) rather than
  atomic + permission-set-group. Tradeoff: per-persona is simpler to
  reason about and assign, costs some duplication; PSG model is better
  for production-scale multi-dimensional composition. MVP-appropriate.
- **License.** `Salesforce` (the full user license tied to the
  `Minimum Access - Salesforce` profile). Not `Salesforce Platform` or
  `Chatter Only` — those would restrict custom object access.
- **Demo user strategy.** Apex anonymous script (not metadata-declared
  `User` records, which Salesforce doesn't support anyway). Idempotent:
  check-before-insert on both Users and PermissionSetAssignments. Paired
  with a delete script that deactivates + renames (Users can't be
  hard-deleted).
- **Email policy.** `.invalid` TLD per RFC 2606 — DNS-level
  non-deliverable, safe for committed repos. Welcome-email suppression is
  belt-and-suspenders via `Database.DMLOptions.emailHeader.triggerUserEmail=false`.
- **Password capture.** `System.resetPassword(userId, false)` returns the
  generated password without sending an email. Logged once for the demo
  team's first login. See `docs/manual-setup-steps.md`.
- **Queues metadata schema.** Retrieved a live sample from the SDO
  (`SDO_Sales_West_Leads.queue`) before generating to confirm the wrapper
  structure. See gotcha #19.

### 7 gotchas caught during E04 (now formalised in CLAUDE.md)

1. #13 — `PermissionSet.RecordTypeVisibility` rejects `<default>`.
2. #14 — Read on MD-child requires Read on MD-parent (re-walk on
   late additions).
3. #15 — Required fields have implicit FLS; permission sets must omit
   them.
4. #16 — Walk required-Lookup targets on every Read AND Edit object.
5. #17 — Account→Contact CBP pair: parent Read requires child Read.
6. #18 — `PermissionSet.description` 255-char limit.
7. #19 — Queue XML schema: nested `<roles><role>X</role></roles>`,
   `<queueSobject>` (not `<supportedObjects>`), no `<queueSortOrder>`.

## Implemented

**Commits**
See `git log --grep='E04'` for the commits that implemented this epic.
(SHAs not embedded — amending a commit changes its SHA, so embedded SHAs
would always be stale. Convention adopted in E03.)

### Files produced

**6 Permission Sets** — `force-app/main/default/permissionsets/`:
- `RECRM_Inventory_Admin.permissionset-meta.xml` — 49 field perms, 6
  objects, 6 RTs, 5 tabs.
- `RECRM_CP_Manager.permissionset-meta.xml` — 117 field perms, 11
  objects, 11 RTs, 8 tabs.
- `RECRM_RM.permissionset-meta.xml` — 138 field perms, 12 objects, 14
  RTs, 7 tabs.
- `RECRM_PSM.permissionset-meta.xml` — identical structure to RM.
- `RECRM_Sales_Head.permissionset-meta.xml` — identical structure to RM.
- `RECRM_Post_Sales_Exec.permissionset-meta.xml` — 180 field perms, 18
  objects, 13 RTs, 9 tabs.

**2 Queues** — `force-app/main/default/queues/`:
- `Post_Sales_Queue.queue-meta.xml` — Booking__c; 2 role members
  (Post_Sales_Team_Lead + Post_Sales_Exec).
- `CP_Manager_Queue.queue-meta.xml` — Lead; 1 role member (CP_Manager).

**2 Apex scripts** — `scripts/` (anonymous Apex, not metadata):
- `seed-demo-users.apex` — idempotent 7-user seed.
- `delete-demo-users.apex` — deactivate + rename, idempotent.

### Iteration story

**Permission-set deploys — 14 attempts across 6 sets** (ordered smallest-
to-largest; pre-flight checklist sharpened after each miss):

| Set | Attempts | Failures encountered |
|---|---|---|
| RECRM_Inventory_Admin | 5 | #13 `<default>` in RT, #14 Pricing_Component MD-dep, #15 required fields (×2 passes to catch all) |
| RECRM_CP_Manager | 3 | #17 Account→Contact, #14 Unit→Tower late addition |
| RECRM_RM | 1 | first-try green (4-check pre-flight matured) |
| RECRM_PSM | 2 | #18 description >255 |
| RECRM_Sales_Head | 2 | #18 description >255 |
| RECRM_Post_Sales_Exec | 1 | first-try green |

**Queue deploys — 2 attempts:**
1. XML used the documented external pattern (`<roles>X</roles>` flat,
   `<supportedObjects>`, `<queueSortOrder>`). Salesforce rejected:
   `<queueSortOrder>` invalid, `<roles>` duplicated, `<supportedObjects>`
   wrong element name. Fixed by pulling a live queue sample from the SDO
   (`SDO_Sales_West_Leads`) and matching its schema exactly.
2. Fixed deploy: green.

**Seed script run — 1 attempt, green.** All 7 users created, all 7 PSAs
assigned on first run.

### Deviations from spec

1. **Pricing_Component__c reassigned from `RECRM_Inventory_Admin` to
   `RECRM_Post_Sales_Exec`.** Rationale: Pricing_Component__c is
   Master-Detail child of Booking__c. Salesforce's MD-dependency rule
   requires Read on parent before Read on child — granting
   Pricing_Component CRUD to Inventory_Admin without Booking access
   failed deploy. The spec put Pricing_Component in Inventory_Admin's
   scope on the assumption it was master pricing data, but it's actually
   per-booking line items snapshotted at booking time. Post-Sales owns
   bookings and all their line items; moving this object there matches
   both the technical constraint and the semantic ownership.

2. **`RECRM_PSM` and `RECRM_Sales_Head` permission sets are exact clones
   of `RECRM_RM`** at the object/field level. The persona differences
   (first-tier vs escalation-tier concession approvers, managed-team
   scope) materialize via approval-process assignment and queue/share
   membership, not via permission-set FLS or CRUD. This is intentional
   and noted in each permission set's `<description>`.

### Manual Setup steps (if any)

One — the temp passwords captured at seed time need to live in
`docs/manual-setup-steps.md` under the E04 section so the demo team
can log in on first launch. See that file for the full first-login
procedure.

### Known follow-ups for later epics

- **E05**: assignment rules (lead routing by `Source_Channel__c` to
  `CP_Manager_Queue` or RM queues; booking auto-creation trigger that
  transfers ownership to `Post_Sales_Queue`). Round-robin within the
  Post_Sales_Queue for Post-Sales Exec assignment.
- **E10**: concession approval process (PSM tier → Sales Head tier).
- **FLS tightening epic**: scope TBD. Restrict sensitive field access
  (e.g., Commission amounts hidden from non-commission-owners) once
  product owners define the matrix.
- **Password rotation for production**: `System.resetPassword` returning
  short passwords under the SDO policy is fine for demo; production
  needs the org policy tightened and the seed script replaced with SSO
  wiring.
- **Profile stock assumption**: if Salesforce renames or removes the
  stock `Minimum Access - Salesforce` profile, the seed script breaks.
  Low probability, but pinned here as a known dependency.
