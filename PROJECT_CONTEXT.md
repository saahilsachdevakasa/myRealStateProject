# Project Context — RE Developer CRM

Authoritative data model, naming, and patterns reference. Every artefact produced by Claude Code must be consistent with this document.

## Scope

An SDO-grade MVP Salesforce CRM for Indian residential developers (Lodha/Godrej/DLF-class). Covers Sales Cloud, CP Experience Cloud portal, and two Agentforce agents. No Marketing Cloud, no Service Cloud, no live external integrations.

## Target environment

Salesforce SDO (Simple Demo Org). The repo is the source of truth — everything must be redeployable from `force-app/` onto a fresh SDO in a single deploy.

## Portfolio in demo

- **10 residential projects** (PRK, SPL, BEL, GRN, HRZ, ELY, AUR, SRN, CSM, MRD); each has 3 towers × 4 floors × 4 units = 48 units
- **2 commercial projects** (GAL, NXS); each has 2 blocks × 3 floors × 20 shops = 120 units
- **Total inventory**: 720 records

## Naming convention (summary)

| Entity | Format | Example |
|---|---|---|
| Project code | `{3 uppercase letters}` | `PRK` |
| Tower | `{PROJ}-T{nn}` | `PRK-T01` |
| Block (commercial) | `{PROJ}-B{nn}` | `GAL-B01` |
| Unit (residential) | `{PROJ}-T{nn}-F{nn}-U{nnn}` | `PRK-T01-F03-U002` |
| Unit (commercial) | `{PROJ}-B{nn}-F{nn}-S{nnn}` | `GAL-B01-F02-S015` |
| Lead | `LD-{YY}-{00000}` | `LD-26-00147` |
| Opportunity | `OP-{YY}-{00000}` | `OP-26-00094` |
| Booking | `BKG-{PROJ}-{YY}-{0000}` | `BKG-PRK-26-0042` |
| Demand | `DM-{BKG}-{nn}` | `DM-BKG-PRK-26-0042-03` |
| Receipt | `RCT-{YY}-{00000}` | `RCT-26-01837` |
| Agreement | `AGR-{BKG}` | `AGR-BKG-PRK-26-0042` |
| Possession | `POS-{BKG}` | `POS-BKG-PRK-26-0042` |
| Channel Partner | `CP-{YY}-{0000}` | `CP-26-0087` |
| Commission Ledger | `CL-{BKG}-{nn}` | `CL-BKG-PRK-26-0042-01` |
| Commission Payout | `CPY-{YY}-{MM}-{000}` | `CPY-26-04-003` |

Full grammar: `docs/naming-convention.docx`.

## Core object model

See Phase 1 Architecture Document Section 3 for full field lists.

- **Inventory**: `Project__c` → `Tower__c` → `Unit__c` (+ `Pricing_Component__c` on Booking for snapshotted pricing)
- **Customer**: `Lead`, `Account` (RTs Buyer/Corporate/CP), `Contact`, `Site_Visit__c`
- **Transactional**: `Opportunity`, `Booking__c`, `Booking_Customer__c` (junction), `Payment_Plan__c` + `Payment_Plan_Milestone__c`, `Booking_Payment_Schedule__c`, `Demand__c`, `Receipt__c`, `Receipt_Allocation__c` (junction), `Agreement__c`, `Possession__c`, `Snag_Item__c`
- **Channel Partner**: `Commission_Rate_Card__c`, `Commission_Ledger__c`, `Commission_Payout__c`
- **Supporting**: `Notification_Preference__c`, `Concession_Request__c`, `Document_Checklist__c`

## Architectural decisions (locked)

- **Booking/Opportunity model**: Option B (separate `Booking__c`). Opportunity covers pre-sales; `Booking__c` covers post-sales.
- **Booking ownership**: Post-Sales queue at creation, then round-robin to Post-Sales Executive.
- **Inventory**: Project → Tower → Unit hierarchy reused for commercial with record types.
- **Commission**: rate-card based with three milestone accruals (Booking, Agreement, Registration). Algorithm in Phase 1 Section 8.
- **Sharing**: Private OWD on transactional objects; role hierarchy + ownership-based + criteria-based; sharing sets for CP portal.
- **Document generation**: VisualForce PDF for MVP. Interface-backed so Phase 2 can swap to Salesforce Docs or Conga.
- **E-sign**: `IESignService` interface with `Stub` implementation. Leegality adapter in Phase 2.
- **Agentforce**: two agents (Lead Qualification, Sales RM Copilot). No Data Cloud dependency.

## Patterns

### Repository layout (flat classes)

All Apex classes live directly in `force-app/main/default/classes/`. No subfolders. Organization is by **naming convention**:

```
force-app/main/default/
├── classes/
│   ├── BookingTriggerHandler.cls
│   ├── BookingTriggerHandlerTest.cls
│   ├── BookingService.cls
│   ├── BookingServiceTest.cls
│   ├── CommissionService.cls
│   ├── CommissionServiceTest.cls
│   ├── CommissionPayoutBatch.cls
│   ├── CommissionPayoutBatchTest.cls
│   ├── IESignService.cls
│   ├── ESignServiceStub.cls
│   ├── ServiceFactory.cls
│   ├── MatchInventoryAction.cls
│   ├── MatchInventoryActionTest.cls
│   ├── CpPortalLeadsController.cls
│   ├── CpPortalLeadsControllerTest.cls
│   ├── CP_Scope.cls
│   ├── RecursionGuard.cls
│   └── TestDataFactory.cls
├── triggers/
│   ├── BookingTrigger.trigger
│   ├── UnitTrigger.trigger
│   └── ...
└── objects/
    ├── Project__c/
    ├── Tower__c/
    └── ...
```

### Trigger framework

- One trigger file per object: `triggers/<Obj>Trigger.trigger`
- Trigger calls a TriggerHandler: `classes/<Obj>TriggerHandler.cls`
- Handler routes by context (before/after × insert/update/delete) to service methods in `classes/<Domain>Service.cls`
- Recursion guard via a `RecursionGuard` static flag utility

### Service classes

- One service per domain concern (`BookingService`, `CommissionService`, `DemandService`, `AgreementService`, `PossessionService`)
- Public methods bulkified (take `List<SObject>`)
- No DML or SOQL in loops
- Testable via dependency injection of child services where useful

### Integration interfaces

- Declared as Apex interfaces with `I` prefix (`IESignService`, `IKYCService`, `INotificationService`)
- Selected via `Integration_Config__mdt` custom metadata through `ServiceFactory`
- MVP uses Stub implementations (`ESignServiceStub`, etc.) across the board
- Adapter classes (`ESignServiceLeegality`, `KYCServiceIDfy`, etc.) come in Phase 2

### Apex tests

- `TestDataFactory` provides builders for Project, Tower, Unit, Lead, Opp, Booking, Receipt etc.
- Factories bulk-insert 200 records by default to exercise bulkification
- Test classes named `<ClassUnderTest>Test`
- Assertions use `System.assertEquals` with messages
- `@IsTest(SeeAllData=false)` always

## CP Portal isolation rules

**Every Apex method called from the CP portal must scope SOQL to the current user's CP Account.** Use `CP_Scope.currentCpAccountId()` to get the `AccountId`. Use it in `WHERE` clauses. Do not rely on sharing alone.

Example:

```apex
public with sharing class CpPortalLeadsController {
    @AuraEnabled(cacheable=true)
    public static List<Lead> getMyLeads() {
        Id cpAccountId = CP_Scope.currentCpAccountId();
        return [
            SELECT Id, Name, Status, Project_Interest__c, CreatedDate
            FROM Lead
            WHERE Source_CP__c = :cpAccountId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }
}
```

## Demo data

Pre-built inventory lives in `data/*.csv`. Load order: Projects → Towers → Units (residential) → Units (commercial) → CPs → Payment Plans → Payment Plan Milestones → Rate Cards.

Seed script: `scripts/seed-demo-data.sh <SDO alias>`.

CSVs use external-ID lookup syntax (`Project__r:Project_Code__c`), intended for `sf data import tree` with a plan file. See `data/plan.json` once E02 lands the data model.
