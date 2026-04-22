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
