# E05b — System Administrator FLS and Tab Visibility Closeout

## Objective

Close the user-visible gap discovered post-E05 where the System
Administrator profile (DeveloperName=Admin) had no `fieldPermissions`
on any custom field and no `tabVisibilities` on any custom tab. Symptom
that surfaced the gap: `SELECT Project_Code_Text__c FROM Lead` returned
`No such column` even though the field deployed cleanly in E05 and
the user holds `ModifyAllData`. ModifyAllData/ViewAllData bypass FLS
at the API for object-level CRUD but **do not** bypass FLS for field
visibility on Lightning record pages or for SOQL field selection.

After E05b, all 289 FLS-grantable custom fields are accessible to
System Admin via SOQL and rendered on record pages, and all 14 custom
tabs appear DefaultOn in the App Launcher full tab list.

## Dependencies

- **E02a, E02b** complete — 21 custom objects deployed, totalling 354
  custom field XML files.
- **E03** complete — sharing model in place; Admin role is `RECRM_CEO`
  (top of hierarchy).
- **E04** complete — 6 persona permission sets carry FLS for their
  respective scopes; Admin profile augmentation is independent of those.
- **E05** complete — `Lead.Project_Code_Text__c` formula field exists
  (the field that surfaced this gap).

## In scope

- **Admin profile augmentation:** 289 `<fieldPermissions>` entries
  (254 regular fields with `editable=true` + 35 formula fields with
  `editable=false`).
- **14 `<tabVisibilities>`** entries with `<visibility>DefaultOn</visibility>`
  for every custom-tab object.
- **userPermissions baseline preserved** — 260 entries unchanged from the
  retrieved baseline.
- **One-time utility script** (NOT committed): `/tmp/build_admin_profile.py`
  — generates the splice. Lives in `/tmp/` so it isn't accidentally
  shipped; can be promoted to `scripts/` if SDO refresh requires it.

## Out of scope (deferred)

- **Persona permission set FLS re-audit** — defer until a persona gap
  surfaces in E06+. The Admin gap is the immediate blocker; persona
  perm sets were FLS-audited in E04 and are presumed correct until
  proven otherwise.
- **Required field FLS grants** — Salesforce rejects by design across
  all tested types (Text, Lookup, Picklist). Verified empirically with
  3 single-field dry-runs.
- **Object permissions / record type visibilities on Admin profile** —
  covered by `ModifyAllData` user permission already in the baseline;
  no augmentation needed at the object/RT level.

## Iteration story

This epic ran in two phases because of an incorrect architectural
assumption that surfaced mid-stream.

### Phase 1 — discovery and initial deploy (254 regular fields)

1. **Step 1 discovery** — retrieved baseline `Admin.profile-meta.xml`.
   0 fieldPermissions, 0 tabVisibilities, 260 userPermissions.
2. **Step 2a enumeration** — categorised all 354 custom field XMLs:
   254 grantable, 100 excluded across 5 categories (Required, Formula,
   MasterDetail, RollupSummary, AutoNumber).
3. **Check 1 (Required field FLS)** — empirically tested 3 Required
   field types (Text: `Payment_Plan__c.Plan_Code__c`; Lookup:
   `Booking__c.Unit__c`; Picklist: `Booking__c.Booking_Status__c`).
   All 3 dry-runs rejected with identical error: `You cannot deploy
   to a required field`. Required exclusion is load-bearing across
   all field types. (Refines E04 gotcha #15.)
4. **Check 2 (Formula field FLS) — initial reasoning was wrong.**
   Hypothesised that formula fields would inherit FLS from underlying
   referenced fields and didn't need explicit grants. Excluded all 35
   formulas from the grantable set.
5. **Step 2b/2c/3** — generated profile (254 fieldPermissions + 14
   tabVisibilities), dry-run green, real deploy green
   (Deploy ID `0AfHp00003nOU82KAG`, State=Changed).
6. **Step 4 verification** — `SELECT Project_Code_Text__c FROM Lead`
   STILL returned `No such column`. Counter-test:
   `SELECT Project_Interest__c FROM Lead` succeeded — confirming the
   254 explicit grants worked, and isolating the failure to formula
   fields specifically.

### Phase 2 — formula-field FLS test and second deploy (35 formulas)

7. **Step A (formula FLS empirical test)** — tested both
   `editable=true` + `readable=true` and `editable=false` + `readable=true`
   in single-field dry-runs against `Lead.Project_Code_Text__c`. Both
   accepted by Salesforce dry-run validation. Chose `editable=false`
   as semantically correct (formula fields are immutable by definition).
8. **Step B regeneration** — modified `/tmp/build_admin_profile.py`
   to also parse `excluded.txt` for `FORMULA` entries and emit
   `editable=false` for them. Total fieldPermissions: 289 (254 editable
   + 35 read-only), alphabetically interleaved.
9. **Step B' / B'' / B'''** — dry-run, real deploy
   (Deploy ID `0AfHp00003nOU8MKAW`, State=Changed, 6.31s),
   verification all green. `SELECT Project_Code_Text__c FROM Lead`
   now returns 1 row (value `null`, but the column resolves cleanly).
   `FieldDefinition` for the same field returns 1 row (was 0 before
   the second deploy).

## Files produced

- `force-app/main/default/profiles/Admin.profile-meta.xml` — new file,
  2551 lines (1050 baseline + 1445 fieldPermissions blocks + 56
  tabVisibilities blocks).

## Files NOT committed (one-time utilities)

- `/tmp/build_admin_profile.py` — generator script
- `/tmp/grantable.txt` — 254 grantable field references
- `/tmp/excluded.txt` — 100 excluded fields tagged by category
- `/tmp/e05b-baseline/` — retrieved baseline (preserved for diff
  reference during the epic; can be discarded post-commit)

## Acceptance criteria

1. Admin profile has 254 editable + 35 read-only `fieldPermissions`,
   14 DefaultOn `tabVisibilities`, 260 `userPermissions` unchanged
   from baseline. (Verified via `grep -c` on the deployed file.)
2. `SELECT Id, Project_Code_Text__c FROM Lead` returns without error.
   (Verified — 1 row returned post-deploy.)
3. `FieldDefinition` returns 1 row for `Lead.Project_Code_Text__c`.
   (Verified — was 0 rows before, 1 row after.)
4. Sample-test SOQL on a regular grantable field
   (`Lead.Project_Interest__c`) and on two more formula fields across
   different objects (`Unit__c.Base_Price__c`, `Tower__c.Tower_Code__c`)
   all resolve without error.
5. Deploy reports State=Changed (not Created) — confirms the existing
   System Administrator profile was updated, not a new profile created.

## Manual verification needed post-deploy

Reproducible by Sahil at his next SDO login:

1. Log into `re-crm-sdo` as System Admin (Sahil's identity), open the
   App Launcher, click **View All**, confirm 14 custom tabs appear in
   the full tab list (Agreement, Booking, Commission Ledger,
   Commission Payout, Commission Rate Card, Concession Request,
   Demand, Payment Plan, Possession, Project, Receipt, Site Visit,
   Tower, Unit).
2. Open a record page on Lead, Project, Booking — confirm custom
   fields render on the layout (vs empty page sections, which was
   the symptom of the FLS gap).

These are visual confirmations only — no scripted verification possible.
Will be re-run during the E23 demo rehearsal as a coverage check.

## Gotchas captured (now in CLAUDE.md)

- **#24** — Profile UI Label ≠ DeveloperName. "System Administrator"
  is the Label; `Admin` is the DeveloperName / API name. Metadata API
  uses DeveloperName for retrieve/deploy keying. Filename
  `Admin.profile-meta.xml` updates Label "System Administrator".
- **#25** — Formula fields require explicit `<fieldPermissions>`
  grants for SOQL/API visibility. The "formula inherits from
  referenced fields" heuristic applies only to record-page rendering
  and DML on the field's value, not to the field's own selectability
  in SOQL or its appearance in `FieldDefinition`. Use
  `<editable>false</editable>` + `<readable>true</readable>` since
  formulas are inherently immutable.
- **#26** — Required fields reject `<fieldPermissions>` grants across
  all types (Text, Lookup, Picklist verified empirically; presumed
  same for Date/Number/etc.). Salesforce enforces "required = always
  visible and editable when the user has object access" at the
  Metadata API level. Refines (doesn't replace) E04 gotcha #15 —
  #15 said the rule existed; #26 confirms it's universal across all
  Required field types and not type-conditional.
- **#27** — Metadata-deployed custom fields default to no FLS on any
  profile, **including Admin**. Setup UI bypasses FLS for admins (so
  the field appears configurable in Object Manager), but SOQL and
  Lightning record pages enforce FLS. Result: a freshly-deployed
  field appears to exist in some surfaces (Object Manager, Tooling
  API `CustomField` query) and not-exist in others (SOQL, standard
  `FieldDefinition` query). Always grant FLS at field deploy time
  via permission sets or via a profile augmentation pass like E05b.
  See also #21 (the persona-perm-set framing of the same root cause).

## Implemented

**Commits**
See `git log --grep='E05b'` for the commits that implemented this
epic (typically two: feat for the profile, docs for this file +
CLAUDE.md gotchas update).

### Deploy iteration story

| Attempt | Failure | Class |
|---|---|---|
| Deploy 1 (254 regular fields + 14 tabs) | — | Green (1/1 components, State=Changed); but post-deploy SOQL on `Project_Code_Text__c` failed |
| Deploy 2 (after adding 35 formula fields with `editable=false`) | — | Green (1/1 components, State=Changed); SOQL on `Project_Code_Text__c` now returns 1 row |

Note: between Deploy 1 (green) and the SOQL failure, no Salesforce
error fired. The bug was a silent omission caused by the wrong
exclusion rule, not a deploy failure. The empirical SOQL test in
verification was the only thing that surfaced it — reinforces the
discipline of always running the read-back test even when deploys
report green.

### Demo-time tests (for E23 rehearsal)

| Scenario | Expected behaviour |
|---|---|
| App Launcher → View All as System Admin | All 14 custom tabs visible |
| Open Lead record page | Custom fields render (not empty sections) |
| Open Project record page | Custom fields render |
| Open Booking record page | Custom fields render |
| SOQL `SELECT Project_Code_Text__c, Project_Interest__c FROM Lead` | Both columns resolve, no errors |
| Workbench / Inspector field tree on Lead | All ~64 custom fields visible |

### Manual Setup steps

None.

### Known follow-ups for later epics

- **E06+ field deploys** — when new fields land, ensure the Admin
  profile is updated in the **same commit** as the field metadata.
  Avoid repeating the E05b pattern (deploy field, discover
  invisibility, do a closeout pass). The build script can be
  promoted to `scripts/` if this becomes recurrent.
- **Persona permission sets** may have similar gaps on the 35
  formula fields — they were FLS-granted at E04 time before any
  formula fields existed for some scopes. Investigate when persona
  testing begins (E23 rehearsal or earlier if a persona-side bug
  surfaces).
- **`/tmp/build_admin_profile.py`** could be preserved as
  `scripts/build_admin_profile.py` for future SDO refreshes; defer
  unless we actually refresh the SDO. Current intent: keep in
  `/tmp/` (disposable), regenerate from the manual procedure
  documented in this epic if the SDO is rebuilt.
