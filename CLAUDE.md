# Claude Code — System Context for RE Developer CRM

You are the implementation partner on a Salesforce Real Estate CRM for Indian residential developers. You produce metadata, Apex, LWC, Flow, and configuration artefacts in response to epic specifications in `docs/epics/`.

## Target environment

**Salesforce SDO (Simple Demo Org).** Not a scratch org. Consequences:

- Deploy via `sf project deploy start --target-org <SDO alias>`. Never `sf org create scratch`.
- The SDO may be refreshed or rebuilt without warning. **The repo is the source of truth** — every piece of metadata must be in `force-app/` so the entire org can be rebuilt in one deploy.
- Do not rely on any manual Setup-UI configuration that is not reflected in source. If a click-trail is needed once (e.g., activating a feature), it must be recorded in `docs/manual-setup-steps.md` so it can be reproduced on the next SDO.
- No sandboxes, no scratch orgs, no packaging. One SDO, one repo.

## Non-negotiables

1. **Read `PROJECT_CONTEXT.md` first on every session.** Names, patterns, and architecture decisions there are authoritative. Do not invent new conventions or deviate from existing ones.

2. **Read `docs/epics/E{nn}-*.md` before starting an epic.** Everything in there is a constraint, not a suggestion.

3. **Respect the Flow-vs-Apex decision matrix** in Section 7 of `docs/phase1-architecture.docx`. Default to Flow. Apex only where specified.

4. **Respect the naming convention** in `docs/naming-convention.docx` section 4. Every auto-number field format, every object API name, every trigger class name follows it.

5. **Trigger framework**: one trigger per object, handler pattern. No business logic in trigger bodies. Handler routes to service classes.

6. **Integrations are interface-first.** `IESignService`, `IKYCService`, etc. MVP ships with the Stub implementation. Phase 2 adapters come later.

7. **CP portal isolation**: every Apex controller method used by the portal scopes its SOQL to the current user's Account via the `CP_Scope` utility. No exceptions. Security review rejects any LWC controller without this.

8. **Apex tests**: 85% coverage target; every class has a companion test class. Use `Test.startTest()`/`stopTest()`. Use `@IsTest(SeeAllData=false)`. Use `TestDataFactory` patterns, not raw inserts scattered in tests.

9. **LWC**: use `@api` for public properties, `@wire` for server data, `@track` sparingly. Use `@salesforce/schema` imports. Never hardcode field names as strings when `@salesforce/schema` is available.

10. **SOQL**: bulkified, selective, no nested queries in loops. `WITH SECURITY_ENFORCED` where feasible. Use `Database.getQueryLocator` for batch classes.

## Repository conventions

### File layout

Standard Salesforce Extensions scaffold (flat classes directory):

```
force-app/main/default/
├── classes/         ← all Apex classes (flat, no subfolders)
├── triggers/        ← one trigger file per object
├── objects/         ← custom objects, fields, validation rules
├── recordTypes/
├── permissionsets/
├── flows/
├── lwc/             ← Lightning Web Components
├── pages/           ← VF PDF pages
├── customMetadata/
├── sharingRules/
└── experiences/     ← CP portal experience bundle
```

Apex class naming disambiguates the flat structure:

- **Triggers**: `<Object>Trigger.trigger` (in `triggers/`)
- **Handlers**: `<Object>TriggerHandler.cls` (in `classes/`)
- **Services**: `<Domain>Service.cls` (e.g., `BookingService.cls`, `CommissionService.cls`)
- **Integration interfaces**: `I<Service>.cls` (e.g., `IESignService.cls`)
- **Integration stubs**: `<Service>Stub.cls` (e.g., `ESignServiceStub.cls`)
- **Integration adapters**: `<Service><Vendor>.cls` (e.g., `ESignServiceLeegality.cls`)
- **Agentforce actions**: `<Action>Action.cls` (e.g., `MatchInventoryAction.cls`)
- **Controllers (for portal LWCs)**: `<Scope>Controller.cls` (e.g., `CpPortalLeadsController.cls`)
- **Batch classes**: `<Purpose>Batch.cls` (e.g., `CommissionPayoutBatch.cls`)
- **Test classes**: `<ClassUnderTest>Test.cls` (e.g., `BookingServiceTest.cls`)
- **Utilities**: meaningful name (`CP_Scope.cls`, `RecursionGuard.cls`, `TestDataFactory.cls`)

### General conventions

- **API names**: PascalCase with underscores for multi-word fields. E.g., `Unit__c`, `Source_CP__c`.
- **Picklist values**: Title Case, speak-able (e.g., "Under Construction", not "UNDER_CONSTRUCTION").
- **Boolean fields**: end with a state-indicating noun or flag. `Is_Primary__c`, `NRI_Flag__c`, `Park_Facing__c`. Not `Has_Park`.
- **Commit messages**: conventional (`feat:`, `fix:`, `chore:`, `docs:`); reference epic ID (e.g., `feat(E07): unit status lifecycle flow`).

## Epic execution protocol

When given an epic ID (e.g., "start E07"):

1. Read `docs/epics/E07-*.md`.
2. List the artefacts to produce (objects, fields, flows, classes, tests).
3. Confirm prior epics' deployed state. Query the SDO if needed: `sf data query --query "SELECT QualifiedApiName FROM EntityDefinition WHERE ..."`.
4. Produce artefacts in order: metadata first, then Apex, then tests.
5. Run tests locally against the SDO before commit: `sf apex run test --target-org <alias> --class-names <TestClass> --result-format human --code-coverage`.
6. Deploy: `sf project deploy start --target-org <alias>`.
7. Update `docs/epics/E07-*.md` with an "Implemented" section listing what was produced.

## What NOT to do

- Do not auto-upgrade dependencies.
- Do not touch metadata outside the epic's scope without confirmation.
- Do not introduce new libraries or managed packages without review.
- Do not add Apex sharing unless explicitly listed in Section 5.5 of the Phase 1 doc.
- Do not call external APIs; use the Stub implementations.
- Do not commit secrets, credentials, or named credentials with real values.
- Do not create scratch orgs. The target is the SDO.
- Do not modify metadata directly in Setup UI without reflecting the change in source — the next SDO refresh will wipe it.

## When in doubt

Stop and ask. Sahil is the Product Owner. Ambiguity in the epic spec is a defect in the spec — surface it rather than guess.

## Reference documents (in this repo)

- `docs/phase0-brief.docx` — vision, scope, personas, capability matrix
- `docs/naming-convention.docx` — every ID format and validation rule
- `docs/phase1-architecture.docx` — full architecture (object model, sharing, automation, commission, CP portal, Agentforce)
- `docs/epics/` — per-epic specifications (drafted as each epic approaches)
- `docs/manual-setup-steps.md` — any one-time Setup-UI steps that must be reproduced on SDO refresh

## Salesforce metadata gotchas learned from E02a and E02b

These are Salesforce metadata-schema quirks discovered during metadata generation. Apply them to all future metadata epics.

1. **Formula fields cannot carry `<unique>` or `<externalId>` attributes.** Salesforce rejects them at deploy time. Uniqueness on formula fields is inherent in formula determinism.

2. **Count roll-up summary fields must omit `<summarizedField>` entirely.** That element is only valid for SUM / MIN / MAX roll-ups on numeric fields, not COUNT.

3. **Formula fields cannot return a reference type (Lookup).** If the spec calls for "Formula(Lookup to X)", implement as Formula(Text) returning the most useful denormalized value — typically a code field from the target record.

4. **Required Lookup fields (`<required>true</required>`) must specify delete behavior.** Add `<deleteConstraint>Restrict</deleteConstraint>` (typical for references that shouldn't orphan) or `<deleteConstraint>Cascade</deleteConstraint>` (for tight parent-child). Without either, deploy fails with "must specify either cascade delete or restrict delete for required lookup foreign key".

5. **Use `BusinessProcess`, not `SalesProcess`.** The correct metadata for restricting Lead statuses or Opportunity stages per record type is `BusinessProcess`, placed at `force-app/main/default/objects/<Object>/businessProcesses/<Name>.businessProcess-meta.xml`. Do NOT use the top-level `salesProcesses/` directory with `.salesProcess-meta.xml` suffix — the Salesforce CLI type inference fails on it.

6. **BusinessProcess XML schema quirks:**
   - Root element: `<BusinessProcess xmlns="http://soap.sforce.com/2006/04/metadata">`
   - Each entry uses `<fullName>` (not `<name>`)
   - Use `<isActive>` (not `<active>`)
   - Lead BusinessProcess requires `<default>true</default>` on exactly one status value
   - Opportunity BusinessProcess REJECTS `<default>` inside `<values>` entirely — omit it

7. **BusinessProcess `<values>` must reference existing picklist values in the target org's StandardValueSet.** Before generating BusinessProcess XML, query the org:

   ```bash
   sf data query --query "SELECT MasterLabel FROM LeadStatus ORDER BY SortOrder" --target-org <alias>
   sf data query --query "SELECT MasterLabel, IsActive FROM OpportunityStage ORDER BY SortOrder" --target-org <alias>
   ```

   Only reference `MasterLabel` values where `IsActive = true`. Do not invent stage names that aren't in the org.

8. **MultiselectPicklist fields require `<visibleLines>` greater than 3.** Setting it to 2 or 3 causes deploy failure with "Visible lines must be greater than 3".

9. **The standard Name field is declared inside the object XML's `<nameField>` block, not as a separate field file.** When counting custom fields per object, expect spec's total = count of files in `fields/` folder + 1 (for Name).

10. **When a record type references a BusinessProcess, both must deploy in the same deploy and the BusinessProcess's `<values>` must include every stage the record type picklist filter exposes.** Mismatches produce "no BusinessProcess named X.Y found" errors even when the BusinessProcess is in the same deploy.

11. **Standard-object OWD XMLs on external-sharing-enabled orgs must declare both `<sharingModel>` AND `<externalSharingModel>`.** A file with only `<sharingModel>ControlledByParent</sharingModel>` deploys successfully (Salesforce reports "Changed") but silently coerces to Private because the implied pair (CBP internal / Private external) is invalid. Always write both elements together.

12. **`EntityDefinition.InternalSharingModel` misreports Contact OWD.** For Contact specifically, it surfaces the *effective* sharing (after Account-parent propagation) rather than the *declared* OWD. When Account is Private and Contact is CBP'd to Account, EntityDefinition reports Contact as Private even though the declared OWD in Setup → Sharing Settings is Controlled by Parent. For verification of Contact OWD, use Setup UI, not SOQL. Other standard and custom objects report correctly.

## E04 gotchas (permission sets, queues, users)

13. **`PermissionSet.RecordTypeVisibility` rejects `<default>`.** That element is Profile-only. Permission set RT visibility uses only `<recordType>` and `<visible>`. Salesforce's deploy error: `Element 'default' invalid at this location in type PermissionSetRecordTypeVisibility`.

14. **Read access on a Master-Detail child requires Read on the parent in the same PermissionSet.** Walk this dependency for every object in the persona's scope, **including objects added later in the design**. Late additions are the most common miss — re-run the MD-parent walk whenever an object is added to a persona's scope. Salesforce error: `Permission Read X depends on permission(s): Read Y`.

15. **Required fields have implicit FLS — permission sets must NOT declare `<fieldPermissions>` for them.** Salesforce rejects with `You cannot deploy to a required field: X.Y`. Audit: `grep -l '<required>true</required>' force-app/main/default/objects/<Obj>/fields/*.field-meta.xml`. Also applies (same audit pattern) to MasterDetail, Formula, RollUp, AutoNumber fields — all four categories carry implicit FLS and must be excluded from explicit `<fieldPermissions>` blocks.

16. **Walk required-Lookup targets on every object the persona can READ AND can CREATE/EDIT.** Both surfaces break at runtime without target Read access — read surfaces break record-page rendering (IDs instead of names), edit surfaces break the Lookup picker. **OWD ControlledByParent does NOT substitute for object-level permissions** — OWD governs record-level sharing; the permission set still needs to grant the target object at least Read.

17. **Granting Read on Account requires Read on Contact in the same permission set.** Salesforce-enforced standard-pair rule (Contact OWD = ControlledByParent from Account triggers a bidirectional dependency). Custom MD parent→child dependencies are NOT similarly enforced based on empirical evidence across CP_Manager, Inventory_Admin, and Post_Sales_Exec deploys — granting Read on a custom MD-parent does not require granting Read on its custom MD-children. The rule appears specific to the Account-Contact standard pair. If other standard objects with CBP-from-parent OWD are added to permission sets later (Notes, Tasks, custom-to-standard pairs), test empirically rather than assuming.

18. **`PermissionSet.description` has a 255-character limit.** Unlike most text fields in our metadata, permission set descriptions are short-form. Treat them like UI-surface tooltips, not documentation blocks. Check char count before deploy: `grep '<description>' file | sed 's/.*<description>\(.*\)<\/description>.*/\1/' | awk '{print length}'`.

19. **Queue metadata schema** — three independent quirks in one file:
    - `<queueMembers>` contains **one** `<roles>` wrapper with multiple `<role>DeveloperName</role>` children (NOT multiple `<roles>` blocks).
    - Queue-to-object binding uses `<queueSobject><sobjectType>ObjectApiName</sobjectType></queueSobject>`, NOT `<supportedObjects><object>...</object></supportedObjects>`.
    - `<queueSortOrder>` is not a valid direct child of `<Queue>` despite being mentioned in some external docs.
    Source format (`.queue-meta.xml`) and MDAPI format (`.queue`) use the same inner element schema. When retrieving a live sample for schema discovery, choose the most complex case available — single-role samples don't reveal the multi-`<role>` nesting rule.

## E05 gotchas (assignment rules, approval processes, flows)

20. **ApprovalStep `<assignedApprover>` requires `<whenMultipleApprovers>` (FirstResponse | Unanimous) even with a single approver.** Salesforce's deploy error is exactly: `Because approval step X has multiple approvers, the assignedApprover requires a whenMultipleApprovers value.` Misleading wording — it fires even when there's only one `<approver>` child. The element is structurally required; the value is irrelevant when only one approver exists. Use `FirstResponse` as the safe default.

21. **Newly-deployed fields have no FLS by default.** Setup UI bypasses FLS for admins; SOQL via API does not. Symptoms: Setup UI shows the field, `FieldDefinition` and direct SOQL both return "as if not there". Distinguish from missing-field by checking Setup UI. Mitigation: grant FLS in persona permission sets at field deploy time. Assignment rules and other metadata-validation contexts don't require FLS on the deploying user — this bites SOQL verification queries, not metadata deploy validation.

22. **ApprovalStep requires `<rejectBehavior><type>RejectRequest|RejectStep</type></rejectBehavior>`.** No default. Same polymorphic-container pattern as #20. For 2-tier binary approvals with no kickback, `RejectRequest` on every step is correct. Element position: alphabetical, between `<name>` and `</approvalStep>`.

23. **Assignment rule criteria cannot traverse Lookup `__r` references.** Symptom: `In field: field - no CustomField named X.Y__r.Z__c found`. Workaround: create a Formula(Text) field on the source object that returns the cross-object value (e.g., `Project_Code_Text__c = Project_Interest__r.Project_Code__c` on Lead), deploy that field first as a mini-deploy, then route assignment-rule criteria on the formula field. Same workaround applies to other workflow-style criteria contexts that share the same field-validation engine.

## E05b gotchas (Admin profile FLS and tab visibility)

24. **Profile UI Label ≠ DeveloperName.** "System Administrator" is the Label visible in Setup; `Admin` is the DeveloperName / API name. The Metadata API uses DeveloperName for retrieve/deploy keying — `sf project retrieve start --metadata "Profile:System Administrator"` returns "Entity ... cannot be found", while `Profile:Admin` resolves correctly. Filename convention: `<DeveloperName>.profile-meta.xml`. So `Admin.profile-meta.xml` updates the existing System Administrator profile (deploy reports State=Changed). To verify which DeveloperName a Label maps to: `sf data query --query "SELECT Id, Name FROM Profile WHERE Name = '<Label>'"` returns the Id; the DeveloperName is then queryable via Tooling API or inferred from the standard list (Admin, Standard, MarketingProfile, etc.).

25. **Formula fields require explicit `<fieldPermissions>` grants for SOQL/API visibility.** The intuition that "formula fields inherit FLS from referenced fields" is wrong for SOQL field selection and `FieldDefinition` queries. It applies only at record-page rendering (where the formula's runtime *value* derives from underlying fields) and at DML on the field's value (which is forbidden anyway since formulas are read-only). For the field's own visibility surface — selectability in SOQL, presence in `FieldDefinition`, appearance in describes — the formula needs an explicit `<fieldPermissions>` grant. Use `<editable>false</editable>` + `<readable>true</readable>` (semantically accurate; both `editable=true` and `editable=false` deploy successfully but `false` matches the field's inherent immutability).

26. **Required fields reject `<fieldPermissions>` grants across all types.** Salesforce enforces the "required = always visible and editable when the user has object access" rule at the Metadata API level, not just for one type. Verified empirically with 3 single-field dry-runs: Required Text (`Payment_Plan__c.Plan_Code__c`), Required Lookup (`Booking__c.Unit__c`), Required Picklist (`Booking__c.Booking_Status__c`) — all rejected with the identical error `You cannot deploy to a required field: <Object>.<Field>`. Refines (doesn't replace) gotcha #15: #15 said the rule existed; #26 confirms it's universal across all Required field types and not type-conditional. Audit: `grep -l '<required>true</required>' force-app/main/default/objects/<Obj>/fields/*.field-meta.xml` and exclude every match from any `<fieldPermissions>` block.

27. **Metadata-deployed custom fields default to no FLS on any profile, including the System Administrator profile.** Setup UI bypasses FLS for admins (so the field appears in Object Manager and is configurable there), and `ModifyAllData`/`ViewAllData` user permissions bypass FLS for object-level CRUD — but neither bypasses FLS for *field* selectability in SOQL or for *field* rendering on Lightning record pages. Result: a freshly-deployed custom field is visible in some surfaces (Object Manager UI, Tooling API `CustomField` query) and invisible in others (standard SOQL, `FieldDefinition` query, record-page layouts) — for the same user, in the same session. The mitigation is to grant FLS at field deploy time via permission sets *and* the Admin profile, in the same commit as the field metadata. Failure mode this enables: deploy succeeds green, persona perm sets get FLS via dedicated commits, but Admin's read-back tests fail mysteriously because Admin was never explicitly granted. See also #21 (the persona-perm-set framing of the same root cause; #21 covers users without elevated perms, #27 specifically covers why even Admin is affected).

## E06a gotchas (Opportunity stages and business processes)

28. **Metadata API normalisation on unchanged components.** When deploying a metadata-containing directory (e.g., `--source-dir` for a whole object), Salesforce may report `State=Changed` on components you didn't edit because its internal XML serialisation differs from your source file (whitespace, attribute order, or omitted-default fields). This is a no-op — the bytes deployed match what's already in the org semantically. Safe to accept. If you want to confirm no semantic change leaked into repo, run `git diff <file>` post-deploy — a clean diff means the normalisation is purely cosmetic at the Salesforce serialisation layer, not in our source. Empirical example: E06a Phase 1 deploy reported `Pre_Sales_Process` BP as Changed despite zero edits to the file; `git diff` post-deploy was clean.

## E06b gotchas (validation rules, path, quick actions)

29. **Quick Action `<fieldOverrides>` with formula `Id` (or any Id-returning formula) fails on Lookup fields.** Deploy error: `Formula result is data type (Text), incompatible with expected data type (Lookup(<Object>))`. The Salesforce type system enforces Lookup-typed values in `<fieldOverrides>`, but raw Id formulas return Text — the formula engine has no Lookup cast in this context. Workaround: remove the `<fieldOverrides>` for the parent-Lookup and rely on Salesforce's standard parent-record auto-population for Create Quick Actions launched from the parent record page (the hosting record's Id implicitly populates the Lookup to that object). For non-parent Lookups (e.g., a `Unit__c` Lookup on `Concession_Request__c`, or a `Requested_By__c` Lookup to User), add the field as an editable layout item for user entry instead. Empirical: E06b first-dry-run failed on `Request_Concession` Quick Action's `<fieldOverrides>` for `Opportunity__c = Id`; removing all three `<fieldOverrides>` blocks and relying on auto-population + editable layout items deployed green on retry.

## E06c gotchas (Apex, TestDataFactory, CLI quirks)

30. **TestDataFactory must compute parent-derived values before insert when a validation rule enforces them.** Specifically: `Tower__c.Tower_Name_Matches_Code` requires `Name = Project_Code + "-T" + leftPad(Tower_Number, 2, '0')` (or `-B` for `Commercial Block`). A naive `new Tower__c(Project__c=..., Tower_Type__c=...)` without a pre-computed Name fails at insert with `FIELD_CUSTOM_VALIDATION_EXCEPTION: Tower Name must match the derived Tower Code format`. Pattern: in the factory method, query the parent for its code/name fields, compute the expected derived value in Apex, set it on the record *before* `applyOverrides`, then insert. This applies to any object where the Name is a plain Text field but a VR enforces a format. Before adding a new factory builder, audit the target object's `validationRules/` directory for Name-format or cross-field constraints and honour them.

31. **Salesforce CLI v2.84.6 has two known Apex-deploy reporting bugs on this SDO.** (a) `sf project deploy start` with `--test-level RunSpecifiedTests` exits with `MetadataTransferError: Missing message metadata.transfer:Finalizing for locale en_US` while the underlying deploy succeeds — `sf project deploy report --job-id <id> --json` confirms the true status. (b) `sf apex get test -i <job>` and `sf apex run test --result-format human --code-coverage` sometimes throw `TypeError: Cannot read properties of null (reading 'Id')` during async-result retrieval. Workaround: query Tooling API directly — `SELECT MethodName, Outcome, Message FROM ApexTestResult WHERE AsyncApexJobId = '<job>'` and `SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate WHERE ApexClassOrTrigger.Name = '<class>'`. Alternatively, `sf apex run test --synchronous --code-coverage` prints a readable coverage table even when async variants error. May be fixed by CLI upgrade (2.84.6 → 2.130.9); test before adopting. Until then, default to NoTestRun deploy + separate synchronous test run + Tooling-API coverage query.

## E06-layout gotchas (page layouts)

32. **Layout `<relatedList>` references use `{ChildObject}.{LookupField}` format for custom relationships, NOT `{relationshipName}` and NOT `{relationshipName}__r`.** Both `<relatedList>Towers</relatedList>` and `<relatedList>Towers__r</relatedList>` fail with `Cannot find related list:Towers` / `Towers__r`. The correct form is `<relatedList>Tower__c.Project__c</relatedList>` — child object API name + dot + lookup/MD field API name on the child. The `__r` suffix is for SOQL relationship traversal only (not layout metadata). Plain relationshipName (`Contacts`, `Opportunities`) works only for standard relationships on standard objects. Audit pattern: for each related list, identify the parent-to-child lookup field on the child object, then use `<ChildObject>.<LookupField>`. Retrieving the child's `<relationshipName>` from its `.field-meta.xml` is useful context but not the value you write in the layout.

33. **Formula, RollUp Summary, and AutoNumber fields on layouts MUST use `<behavior>Readonly</behavior>`.** Salesforce rejects `Edit` with `Field:<FieldName> must be Readonly`. Applies to: `<formula>...</formula>`, `<type>Summary</type>`, `<type>AutoNumber</type>`, and likely other data-layer-immutable field types (audit/system fields like CreatedById too). Audit before generating a layout: `grep -lE '<formula>|<type>Summary</type>|<type>AutoNumber</type>' force-app/main/default/objects/<Obj>/fields/*.field-meta.xml` — every match must be Readonly on the layout. Related: some layout validators ALSO reject `Required` on these fields (same root cause — you can't require a read-only field). When in doubt, use Readonly.

34. **AutoNumber `Name` fields must NOT use `<behavior>Required</behavior>` on page layouts.** Salesforce rejects with `Field:Name must not be Required`. AutoNumber names are system-populated; requiring them is semantically meaningless and metadata-API-forbidden. Use `Readonly` (semantically accurate) or `Edit` (accepted but visually odd since the user can't edit). Audit: `grep -A4 '<nameField>' force-app/main/default/objects/<Obj>/<Obj>.object-meta.xml` — if `<type>AutoNumber</type>`, set `Name` to Readonly on every layout for that object. Related: #33 (same "data-layer read-only ⇒ layout read-only" invariant).

35. **Layout XSD enforces strict element ordering: `<layoutSections>` must appear before `<platformActionList>`, `<quickActionList>`, `<relatedContent>`, and `<relatedLists>`.** Inserting new `<layoutSections>` blocks after any of those later elements produces the misleading error `Element layoutSections is duplicated at this location in type Layout`. The error says "duplicated" but the actual violation is wrong position — not a duplicate. Resolution: insert new sections immediately after the LAST existing `</layoutSections>` block. Audit pattern: `grep -n '</layoutSections>' <file> | tail -1` gives the insertion line; append new sections after that line. This is especially important when extending retrieved baseline layouts (Lead, Account, Contact, Opportunity) which already contain `<relatedContent>` / `<quickActionList>` / `<relatedLists>` blocks further down the file.

## E06-layout Phase 2 gotchas (Lightning Record Pages / flexipages)

36. **Flexipage DeveloperName (filename stem) cannot contain `__c`.** Salesforce parses the DeveloperName for a namespace separator on each underscore pair; `Booking__c_Record_Page` is read as `namespace=Booking`, name=`c_Record_Page`, and deploy rejects with `Cannot create a new component with the namespace: Booking. Only components in the same namespace as the organization can be created through the API`. Correct naming: drop the `__c` suffix → `Booking_Record_Page.flexipage-meta.xml`. The `<sobjectType>Booking__c</sobjectType>` element INSIDE the XML still references the object correctly; only the filename needs to be namespace-safe. Applies to all custom-object flexipages.

37. **`<mode>Replace</mode>` on flexipage regions only works when the page has a `<parentFlexiPage>` element pointing to a parent template.** Standalone flexipages (no parent inheritance) can't use `<mode>` at all — deploy rejects with `The '<region>' region specifies mode 'REPLACE' but a parent region enabling that mode doesn't exist`. The error is misleading — it fires even though no parent is referenced. Resolution: omit `<mode>` entirely from all `<flexiPageRegions>` blocks in standalone flexipages. The implicit mode is "add" (regions are additive, not overriding). Only add `<mode>Replace</mode>` back when the flexipage explicitly declares `<parentFlexiPage>sfa__SomeTemplate</parentFlexiPage>`.

38. **Facet regions never accept `<mode>Replace</mode>`**, even on inherited flexipages with a valid `<parentFlexiPage>`. Facets are pure content containers (referenced by `<componentInstanceProperties>` like `body=detailTabContent`) — they don't override anything in the parent template. Error is the same as #37, which compounds the diagnostic difficulty: in a chain of Region + Facet blocks all with `<mode>Replace</mode>`, Salesforce reports the first failure and doesn't indicate whether it's a Facet-specific rule or a no-parent issue. Resolution: strip `<mode>` from all Facet blocks unconditionally; revisit `<mode>` on Regions only in the context of #37.

## E06-apps gotchas (Lightning Apps)

39. **Newly deployed Lightning Apps (`CustomApplication`) default to invisible on all profiles, including the System Administrator profile.** They appear in `SELECT FROM CustomApplication` and exist in Setup → App Manager, but won't show in any user's App Launcher until at least one profile or permission set grants `<applicationVisibilities>` for them. The Admin profile must explicitly include an `<applicationVisibilities>` block per app with `<visible>true</visible>`, and exactly one app per profile may be `<default>true</default>` (the auto-launched app). Pattern: bundle the `<applicationVisibilities>` profile update in the SAME commit as the app metadata to avoid the "deploy succeeded but user can't see the app" failure mode. Insertion point in profile XML: alphabetical, before `<custom>` (i.e., at the very top of the Profile element body, since `applicationVisibilities` comes first alphabetically). For permission sets: `<applicationVisibilities>` is a permset element too, useful when persona-scoping apps without modifying the catch-all Admin profile — but profile-only is sufficient for MVP.

## E09 gotchas (MD rollup VR interaction)

40. **MD child DML triggers parent rollup recalc, which re-evaluates parent VRs with partially-committed rollup state.** A VR like `AND(Active__c, Milestone_Count__c > 0, Total_Pct_Check__c <> 100)` fails on every child insert when the parent is `Active__c=true`, because each individual child insert (or even a bulk insert of all children) updates the rollup to a non-100% intermediate value before the full set has been processed. No single-transaction workaround exists — even bulk-inserting all children fires the rollup recalc per parent and re-evaluates the parent VR mid-batch. Cross-transaction workarounds also fail because rollup commits are async and can take seconds-to-minutes to settle on the parent's stored field value. Pattern: seed parent records in a permissive state (e.g., `Active__c = false`), insert all children, then activate the parent in a SEPARATE manual step (Setup UI edit, or API call after sufficient time has elapsed for rollups to commit). Apply this to TestDataFactory builders too — `createPaymentPlan` defaults `Active__c=false` so subsequent `createPaymentPlanMilestone` calls don't fire the parent VR. Tests that need active plans override via the Map. Production seed scripts follow the same pattern with manual UI activation documented as a one-time post-seed step.

## E14 gotchas (Screen Flows and Flow-type Quick Actions)

41. **Flow-type Quick Actions MUST be listed in `<platformActionList>`, NOT `<quickActionList>`.** Layout deploy rejects a Flow-type QA in `<quickActionList>` with `You can't add QuickActionType Flow to a QuickActionList.` Flow QAs render in the Lightning highlights panel and are driven by the `<platformActionList>` element:
    ```xml
    <platformActionList>
        <actionListContext>Record</actionListContext>
        <platformActionListItems>
            <actionName>My_Flow_QA</actionName>
            <actionType>QuickAction</actionType>
            <sortOrder>0</sortOrder>
        </platformActionListItems>
    </platformActionList>
    ```
    `<quickActionList>` is only for `type=Create`, `type=Update`, `type=VisualforcePage`, feed-item actions (`FeedItem.TextPost` etc.), and `SendEmail` — the old-style mobile/Chatter publisher actions. XSD ordering per gotcha #35 still applies: `<platformActionList>` goes after all `<layoutSections>` and before `<quickActionList>`. If a layout has no existing `<platformActionList>`, create one; if it has one for standard buttons, append new `<platformActionListItems>` with incrementing `sortOrder`. The `actionListContext=Record` value is correct for record-page QAs (vs `Related`, `ListView`, `Chatter`, etc.). `TargetSobjectType=null` on a Flow-type `QuickActionDefinition` query is normal — the target object is inferred from the layout's parent object, not from the QA definition.

42. **Screen Flow field output → `@InvocableMethod Id` parameter needs an intermediate `<assignments>` element for String→Id coercion.** When a `<screens>` RadioButton with `<dataType>String</dataType>` binds to a `<dynamicChoiceSets>` whose `<valueField>Id</valueField>` returns record Ids as Strings, passing that screen-field output directly into an `@InvocableVariable` typed as `Id` fails deploy with `field integrity exception: unknown (The type for the input parameter "<Param Label>" doesn't match the type for the assigned value.)`. The type mismatch happens only at screen-field → action-input boundaries; regular String variables → Id parameters coerce implicitly. **Workaround**: declare a standalone `<variables>` entry (dataType=String, isInput=false), add an `<assignments>` element between the screen and the action call that copies the screen-field output to that variable, then reference the variable in the action's `<inputParameters>`. Flow's implicit coercion kicks in at variable-reference time. Also note: screen-field outputs are referenced by the field name directly, NOT as `ScreenName.FieldName` — `<elementReference>ScreenName.FieldName</elementReference>` fails with `field integrity exception: unknown (The element has an invalid reference to "ScreenName.FieldName".)`. The correct form is `<elementReference>FieldName</elementReference>`. This mirrors how variables are referenced — Flow treats every named element (variable, screen field, assignment target) as a first-class entry in a flat namespace.
