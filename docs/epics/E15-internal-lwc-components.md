# E15 — Internal LWC Components for Record Pages

## Objective

Make the demo record pages visually rich and data-dense. Standard Record Detail panels are functional but plain — this epic adds 6 LWC components embedded on key record pages (Booking, Unit, Project, Account) to surface lifecycle progress, payment status, inventory health, and buyer identity at a glance.

This is the FIRST set of LWCs in the project. Establishes patterns for E16-E17 (CP Portal LWCs).

## Dependencies

- E08–E13 — Booking, Demand, Receipt, Agreement, Possession objects with their lifecycle data
- E14 — Quick Actions referenced from page layouts (not flexipages, but parallel UX surface)
- E06-layout / flexipages — Booking_Record_Page, Unit_Record_Page, Project_Record_Page already exist as org defaults

## In-scope artefacts

**6 LWC bundles** (`force-app/main/default/lwc/`):

| Component | Object | Apex Controller | Purpose |
|---|---|---|---|
| `bookingLifecycleTracker` | Booking__c | BookingLifecycleController | Visual path indicator showing booking lifecycle stages with milestone dates below |
| `paymentTimeline` | Booking__c | PaymentTimelineController | Vertical timeline of payment plan milestones with status badges and amounts |
| `demandCollectionSummary` | Booking__c | DemandCollectionController | 3 metric tiles + collection progress bar |
| `unitStatusCard` | Unit__c | UnitStatusCardController | Status badge + blocking countdown + area + pricing card |
| `projectInventoryChart` | Project__c | ProjectInventoryController | SVG donut chart of unit-status distribution |
| `buyerProfileCard` | Account | BuyerProfileController | Identity card with KYC badge, masked PAN, booking count |

**6 Apex controllers** — single `@AuraEnabled(cacheable=true)` method per controller, returning a wrapper class with `@AuraEnabled` properties. All SOQL uses `WITH SECURITY_ENFORCED`.

**3 flexipage updates** — embed LWCs into existing record pages:
- `Booking_Record_Page` → adds 3 LWCs to `detailTabContent` facet
- `Unit_Record_Page` → adds `unitStatusCard` to `detailTabContent` facet
- `Project_Record_Page` → adds `projectInventoryChart` to the `sidebar` region

**NOT embedded via flexipage:** `buyerProfileCard` is exposed for the Account record page but not auto-embedded — Account uses SDO default flexipages which we don't own. Sahil drags it onto an Account flexipage manually via App Builder.

## Locked design decisions

**D1. Single-SOQL controllers with wrapper classes.** Each controller does one query (SOQL or AggregateResult), populates a single nested `@AuraEnabled` wrapper class, returns it. Both the inner class AND every property need `@AuraEnabled` or LWC deserialization fails silently.

**D2. `@AuraEnabled(cacheable=true)` on all 6 read methods.** All methods are pure reads. LWC caches the result in browser memory and refreshes only when `recordId` changes — fewer SOQL calls per page load, faster perceived load.

**D3. `WITH SECURITY_ENFORCED` on every SOQL.** Per CLAUDE.md non-negotiable #10. CP Portal LWCs (future) will need the additional `CP_Scope` utility per non-negotiable #7; internal LWCs only need security-enforced for now.

**D4. SLDS utility classes, minimal custom CSS.** All layouts use SLDS grid (`slds-grid`, `slds-col slds-size_1-of-N`) and spacing (`slds-p-around_medium`, etc.). Custom CSS is limited to what SLDS doesn't cover: progress-bar fill (`demandCollectionSummary`), donut chart positioning (`projectInventoryChart`), monospace PAN (`buyerProfileCard`), separator border (`bookingLifecycleTracker`).

**D5. SVG donut without external library.** `projectInventoryChart` uses the `r=15.91549430918954` trick — circumference = 2π × r = 100, so `stroke-dasharray="X 100-X"` directly maps a percentage to a segment. ~30 lines of JS + ~25 lines of SVG. No Chart.js, no D3.

**D6. Live countdown via `setInterval` + `disconnectedCallback`.** `unitStatusCard` updates the "X hours Y minutes remaining" countdown every 30 seconds when the unit is Blocked. Standard pattern: `connectedCallback` registers, `disconnectedCallback` clears. Resilient to LWC component lifecycle.

**D7. PAN masking convention.** `buyerProfileCard` masks PAN as `XXXXXX` + last 4 chars (matches Indian financial-data masking norm). PAN is 10 chars total → 6-char prefix masked, 4-char suffix visible.

**D8. Flexipage retrieval before edit.** Per the "repo as source of truth" principle but acknowledging Setup UI drift: STEP 4 retrieved current org versions of all 3 flexipages BEFORE editing. Booking and Project had drifted (Sahil added a sidebar region + extra highlights-panel properties via Setup UI). Synced local repo with retrieved versions, then added LWC `<itemInstances>` blocks. Repo now reflects org reality.

**D9. LWC embed pattern in flexipages.** Each LWC gets its own `<itemInstances>` block (one block = one row in the region):
```xml
<itemInstances>
    <componentInstance>
        <componentName>c:bookingLifecycleTracker</componentName>
        <identifier>c_bookingLifecycleTracker_1</identifier>
    </componentInstance>
</itemInstances>
```
No explicit `recordId` binding — the framework auto-injects it on record pages via `@api recordId`. (Confirmed via deploy + Tooling API.)

## Iteration story

- **STEP 1 discovery** — confirmed no existing LWCs in repo (first ones), no controller-name collisions, all 23 flexipages already in repo, all field types verified.
- **STEP 2 pilot** (`bookingLifecycleTracker`) — dry-run green first attempt. Pattern established for the rest.
- **STEP 3 batch** (5 remaining LWCs + 5 controllers, deployed together) — dry-run green first attempt. The pilot pattern transferred cleanly.
- **STEP 4 flexipage embed** — retrieved fresh versions; Booking + Project had drifted from Setup UI edits; synced and embedded. Dry-run + real deploy green first attempt.
- **Zero failed dry-runs** across 12 components + 3 flexipage updates. Strict adherence to the retrieved-template pattern (LWC bundle structure) and the existing flexipage convention paid off.

## Files produced

```
force-app/main/default/lwc/
├── bookingLifecycleTracker/{js,html,css,js-meta.xml}
├── paymentTimeline/{js,html,js-meta.xml}              (no .css needed)
├── unitStatusCard/{js,html,js-meta.xml}               (no .css needed)
├── projectInventoryChart/{js,html,css,js-meta.xml}
├── demandCollectionSummary/{js,html,css,js-meta.xml}
└── buyerProfileCard/{js,html,css,js-meta.xml}

force-app/main/default/classes/
├── BookingLifecycleController.{cls,cls-meta.xml}
├── PaymentTimelineController.{cls,cls-meta.xml}
├── UnitStatusCardController.{cls,cls-meta.xml}
├── ProjectInventoryController.{cls,cls-meta.xml}
├── DemandCollectionController.{cls,cls-meta.xml}
└── BuyerProfileController.{cls,cls-meta.xml}

force-app/main/default/flexipages/
├── Booking_Record_Page.flexipage-meta.xml             (MODIFIED)
├── Unit_Record_Page.flexipage-meta.xml                (MODIFIED)
└── Project_Record_Page.flexipage-meta.xml             (MODIFIED)
```

## Verification

```
Tooling API (post-deploy):
  6/6 LightningComponentBundle records present
  6/6 ApexClass controllers present
  3/3 FlexiPage records updated (LastModifiedDate fresh)
```

UI spot-check (STEP 6) skipped per instruction; demo readiness will be verified when Sahil opens a record page.

## Gotchas surfaced

No new CLAUDE.md entries. Honoured:
- **#36-#38** (flexipage XML quirks) — the existing flexipages we modified already had correct schema (no `<mode>Replace</mode>` issues since these are standalone, not template-inheriting).
- **D8 above** — retrieve-before-edit prevents overwriting Setup UI drift. Worth adding as a working principle for any future flexipage work; not yet a numbered gotcha but a strong pattern.

## Known follow-ups

- **buyerProfileCard embedding** — Sahil drags onto Account flexipage in App Builder (or a future epic creates a custom Account flexipage we own).
- **Apex test classes for the 6 controllers** — coverage is 0% currently. Future epic should add `*ControllerTest` classes for all 6, targeting 85% coverage. Pattern: TestDataFactory chain to seed records, then `Test.startTest()` + call the @AuraEnabled method + assert wrapper fields.
- **`paymentTimeline` polish** — the timeline currently uses `lwc:if`/`lwc:else` (modern syntax) while `bookingLifecycleTracker` uses `if:true` (legacy). Could normalize to `lwc:if` everywhere.
- **Real-time refresh** — `cacheable=true` + `@wire` means the component caches the result. If a Demand is raised via Quick Action, the `demandCollectionSummary` won't update until page refresh. Could add `refreshApex` import + manual refresh after Quick Action completion (later polish).
- **`projectInventoryChart` rotation** — donut starts at 12 o'clock via `transform: rotate(-90deg)` on the SVG; works in modern browsers. If accessibility or older-browser support becomes a concern, refactor to use SVG transform attribute on each circle.
- **Flexipage activation** — these flexipages must be **set as org defaults** in App Builder for the LWCs to appear on standard record pages. If Sahil hasn't done this from prior E06-layout work, the LWCs are deployed but not visible.
