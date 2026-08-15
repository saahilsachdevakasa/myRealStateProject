# RE Developer CRM — Technical Design Document

**System:** Salesforce CRM for Indian Residential & Commercial Developers
**Target environment:** Salesforce SDO (`re-crm-sdo`) — single demo org, repo-as-source-of-truth
**Document date:** 2026-08-16
**Prepared by:** Documentation Agent (synthesized from `PROJECT_CONTEXT.md`, all `docs/epics/E*.md` files, deployed `force-app/` metadata, `agent-output/2026-08-15-full-codebase-review.md`, and `CLAUDE.md`)

> **Source-access note:** `docs/phase0-brief.docx`, `docs/phase1-architecture.docx`, and `docs/naming-convention.docx` are binary `.docx` files and could not be opened by this agent. Every reference to "Phase 1 Architecture Section N" below is a citation carried forward verbatim from the epic docs (which *were* able to read the source at build time), not a citation this document independently verified against the docx. Where the built system and the epic's stated intent disagree, both are noted. `PROJECT_CONTEXT.md` and the 24 epic docs under `docs/epics/` are treated as the authoritative synthesized record for this document.

---

## 1. Executive Summary

### 1.1 What this system is

RE Developer CRM is an MVP-grade Salesforce implementation for an Indian residential/commercial real-estate developer (Lodha/Godrej/DLF-class demo narrative). It covers the full buyer lifecycle — **Lead → Opportunity → Booking → Payment Plan → Demand → Receipt → Agreement → Possession** — plus a **Channel Partner (CP) commission engine** and a **CP self-service Experience Cloud portal**. Three **Agentforce** agents (built directly in the org via Agent Builder, backfilled into source in E18) provide lead scoring/routing, inventory-matching, and next-best-action guidance on top of the CRM data.

The demo portfolio comprises 10 residential projects (3 towers × 4 floors × 4 units = 48 units each) and 2 commercial projects (2 blocks × 3 floors × 20 shops = 120 units each) — 720 inventory records total.

### 1.2 Who it is for (personas)

| Persona | Role in the system |
|---|---|
| **RM (Relationship Manager)** | Owns Leads and Opportunities for a project team (PRK/SPL/Commercial); drives site visits through to booking. |
| **PSM (Pre-Sales Manager)** | Escalation tier for RMs; first-tier concession approver (≤5%). |
| **Sales Head** | Org-wide oversight (read access to all Bookings); second-tier concession approver (>5%). |
| **Post-Sales Executive** | Owns the Booking lifecycle after Closed Won — Demand, Receipt, Agreement, Possession, Snags. |
| **CP Manager** | Manages Channel Partner accounts, commission rate cards, ledgers, and payouts. |
| **Inventory Admin** | Owns Project/Tower/Unit master data, Payment Plans, Rate Cards. |
| **Channel Partner (external/portal user)** | Submits leads, tracks site visits, and views their own commission ledger/payouts via the CP Experience Cloud portal — strictly scoped to their own Account. |

### 1.3 What problem it solves

Indian residential sales cycles are long, multi-party (RM, buyer, Channel Partner, post-sales team, legal/registration), and financially intricate (GST/TDS-bearing demands, milestone-based payment plans, tiered CP commissions with clawback-on-cancellation). This system replaces spreadsheet- and email-driven coordination with a single object model, an enforced status lifecycle per Booking/Unit, automated demand/commission calculation, and a self-service portal that removes CP Manager as a manual bottleneck for partner visibility.

### 1.4 Summary of what was built

A 24-object custom + extended-standard data model (~354 custom fields), a 14-role sharing hierarchy with 6 persona permission sets, 7 trigger-handler-service chains covering the entire post-sales lifecycle, a 3-milestone commission engine with monthly payout batching, a 6-screen-flow UX layer wrapping the invocable Apex services, 12 internal Lightning Web Components, a 6-controller/6-LWC Channel Partner portal (code-complete; Experience Cloud site itself is a documented manual Setup step), and 3 Agentforce agents grounded on CRM data. As of 2026-08-15/16, a full codebase review found 14 critical defects (governor-limit bulkification gaps in 5 Agentforce action classes, missing Flow fault paths on 9 of 10 screen flows) — **all 14 have since been fixed and deployed**; 25 warnings and 5 suggestions from that same review remain open (see §12).

### 1.5 Build status — epics implemented

| Epic | Scope | Status |
|---|---|---|
| E02a | Inventory cluster (Project/Tower/Unit) | ✅ Deployed |
| E02b | Remaining data model (24 objects) | ✅ Deployed |
| E03 | Sharing model (OWD, roles, sharing rules) | ✅ Deployed |
| E04 | Permission sets, queues, demo users | ✅ Deployed |
| E05 / E05b | Assignment rules, approvals, Admin FLS closeout | ✅ Deployed |
| E06-apps / E06-layout / E06a / E06b / E06c | Apps, layouts, flexipages, Opportunity stages, validation rules, Path, first Apex (UnitBlockingService) | ✅ Deployed |
| E07 | Unit status lifecycle state machine (first trigger) | ✅ Deployed |
| E08 | Opportunity → Booking trigger | ✅ Deployed |
| E09 | Payment Plan instantiation trigger | ✅ Deployed |
| E10 | Demand generation service + naming trigger | ✅ Deployed |
| E11 | Receipt allocation and reconciliation | ✅ Deployed |
| E12 | Agreement workflow + Demand Letter PDF | ✅ Deployed |
| E13 | Possession handover + Snag items | ✅ Deployed |
| E14 (cp-base) | Channel Partner base infrastructure (RateCardService, VRs, CP status Flow) | ✅ Deployed |
| E14 (screen-flows) | 6 Screen Flows + Quick Actions wrapping E08–E13 services | ✅ Deployed |
| E15 (internal-lwc) | 6 internal record-page LWCs | ✅ Deployed |
| E15 (cp-portal-code) | CP_Scope + 6 portal controllers + 6 portal LWCs | ✅ Deployed (code only — Experience Cloud site is manual E16, not confirmed performed) |
| E17 | Commission engine (accrual, clawback, payout batch) | ✅ Deployed |
| E18 | Agentforce backfill (3 agents, 4 Apex actions) — retroactive source capture of org-built agents | ✅ Deployed (source now tracks org state) |
| E21 | Booking cancellation & refund | ✅ Deployed |
| **Critical-fix pass** (2026-08-15/16) | Bulkification of 5 Agentforce actions + fault paths on 9/10 flows, per code review | ✅ Deployed |

No epic numbered E16, E19, E20, E22, or E23 exists as a standalone doc in `docs/epics/` at this time (E16 is referenced only as a manual-setup appendix inside E15; E20/E23 are referenced prospectively inside other epics' "Known follow-ups" as future work, not yet started).

---

## 2. System Architecture Overview

### 2.1 Target environment

The system is built and deployed against a single **Salesforce SDO (Simple Demo Org)**, not a scratch org, not a sandbox, no packaging. This has architectural consequences documented repeatedly across the epics:

- **The repo is the source of truth.** Every metadata component must live under `force-app/` so the org can be rebuilt from a single `sf project deploy start` on a freshly-refreshed SDO.
- **Any one-time Setup-UI click-trail** (feature activation, Experience Cloud site creation, layout assignment, currency locale) is recorded in `docs/manual-setup-steps.md` so it survives an SDO refresh even though it isn't deployable metadata.
- **No scratch orgs, no sandboxes.** All discovery (`sf data query`, Tooling API introspection) and validation (`--dry-run`) happens directly against the SDO.

### 2.2 High-level component map

```
                         ┌────────────────────────────────────────┐
                         │           Data Model (§3)              │
                         │  Lead/Opp → Booking → Payment/Demand/   │
                         │  Receipt → Agreement → Possession       │
                         │  + Inventory (Project/Tower/Unit)       │
                         │  + Channel Partner (Rate Card/Ledger/   │
                         │    Payout)                              │
                         └───────────────┬──────────────────────────┘
                                         │
                 ┌───────────────────────┼───────────────────────────┐
                 ▼                       ▼                           ▼
     ┌───────────────────┐   ┌────────────────────────┐   ┌──────────────────────┐
     │ Automation Layer   │   │  Apex Service Layer      │   │  Security Model (§9) │
     │ (§4)               │   │  (§5) — trigger→handler   │   │  OWD + role hierarchy │
     │ Flows, Approval     │   │  →service chains,        │   │  + 6 persona perm     │
     │ Processes,          │   │  invocable actions,      │   │  sets + sharing rules │
     │ Assignment Rules    │   │  batch (Commission)      │   │                       │
     └─────────┬───────────┘   └───────────┬──────────────┘   └───────────────────────┘
               │                            │
               ▼                            ▼
     ┌────────────────────────────────────────────────────┐
     │              LWC / UI Layer (§6)                    │
     │   12 internal record-page components +               │
     │   Screen Flows/Quick Actions wrapping invocables      │
     └───────────────────────┬──────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                                ▼
     ┌──────────────────────┐        ┌──────────────────────────┐
     │  CP Portal (§7)       │        │  Agentforce Layer (§8)    │
     │  CP_Scope isolation +  │        │  3 agents grounded on     │
     │  6 controllers + 6 LWC │        │  CRM data, 4 custom       │
     │  (Experience Cloud)    │        │  Invocable actions        │
     └──────────────────────┘        └──────────────────────────┘
```

Two layers referenced in `CLAUDE.md`/`PROJECT_CONTEXT.md` as architectural intent are **not yet present in `force-app/`**: the **interface-first integration layer** (`IESignService`, `IKYCService`, `ServiceFactory`, `Integration_Config__mdt`, Stub implementations) and the **Experience Cloud site itself** (E15 shipped only the Apex/LWC code; the Digital Experiences site, sharing sets, and portal user creation are E16's manual Setup-UI walkthrough, whose completion is not confirmed by anything in source). Both are called out again in §5.4, §7, and §12.

### 2.3 Flow-vs-Apex decision matrix, as actually applied

`CLAUDE.md` non-negotiable #3 defaults automation to declarative Flow, reserving Apex for cases the platform can't express declaratively. The built system follows this consistently:

| Concern | Mechanism chosen | Why |
|---|---|---|
| Field-level required/format rules (Project Code format, Floor/Unit range, Tower name matches code) | **Validation Rule** | Pure declarative constraint. |
| Stage-gated Opportunity fields (Project required after Qualified, Unit by Negotiation, financials at Closed Won) | **Validation Rule**, `ISCHANGED(StageName)` scoped | No cross-object DML needed. |
| Lead routing by source/project | **Assignment Rule** | Native fit; workaround needed only for cross-object criteria (gotcha #23). |
| Concession approval (2-tier PSM/Sales Head) | **Approval Process** + companion Workflow field updates | Native approval semantics (recall, delegation, history) beat a hand-rolled Apex state machine. |
| CP status → audit field population / portal-access revocation | **Record-Triggered Flow** (`CP_Status_Change_Handler`) | Simple before-save field derivation; no complex cross-object orchestration. |
| Booking → Post-Sales Queue ownership | **Record-Triggered Flow** (`Transfer_Booking_To_Post_Sales_Queue`), later made redundant (but not removed) by `BookingService` setting `OwnerId` at insert | Originally Flow-first per non-negotiable #3; BookingService duplicates it as a belt-and-suspenders fallback (flagged as redundant automation in code review W5). |
| Opportunity → Booking creation, Unit state machine, Payment Plan instantiation, Demand generation, Receipt allocation, Agreement/Possession sync, Commission accrual/clawback, Cancellation cascade | **Apex** (trigger → handler → service) | All require multi-object atomic DML, computed sequencing, or business logic beyond declarative expressiveness — explicitly the carve-out non-negotiable #3 allows. |
| One-click UX for the above Apex services | **Screen Flow + Flow-type Quick Action** wrapping the `@InvocableMethod` | Keeps business logic in Apex (testable, bulkified) while giving users a native Lightning UI entry point — Flow-as-UI-shell over Apex-as-logic is the established pattern from E14 (screen-flows). |

---

## 3. Data Model

The deployed field metadata is this project's data dictionary (there is no separate `docs/00-data-dictionary/`). As of the latest deploy, `force-app/main/default/objects/` contains **21 custom objects** and **3 extended standard objects with declared OWD** (Account, Contact, Lead) plus Opportunity extended with fields/validation rules/record types (no dedicated OWD override — standard Private default retained). Total custom field count is **354** field-meta.xml files across all objects.

### 3.1 Lead-to-Opportunity cluster

| Object | Type | Purpose | Key fields | Relationships |
|---|---|---|---|---|
| `Lead` | Standard, extended (+15 fields, 2 RTs) | Inbound prospect capture | `Project_Interest__c` (Lookup Project), `Project_Code_Text__c` (Formula(Text), workaround for assignment-rule Lookup traversal — gotcha #23), `Source_Channel__c`, `External_Lead_Id__c` (unique+externalId) | RT: `Residential_Lead`, `Commercial_Lead` |
| `Account` | Standard, extended (+18 fields, 3 RTs) | Buyer / Corporate Buyer / Channel Partner master | `Buyer_Type__c`, `KYC_Status__c`, `PAN__c`, `GSTIN__c`, `CP_Status__c`, `CP_Tier__c`, `Portal_Access__c`, `Blacklisted__c` | RT: `Buyer`, `Corporate_Buyer`, `Channel_Partner` |
| `Contact` | Standard, extended (+6 fields) | Individual buyer/co-buyer | `PAN__c`, `Aadhaar_Last4__c`, `DOB__c`, `NRI_Status__c`, `Passport_Number__c`, `Occupation__c` | OWD: ControlledByParent (Account) |
| `Opportunity` | Standard, extended (+12 fields, 2 RTs) | Pre-sales pipeline | `Project__c` (Lookup), `Primary_Unit__c` (Lookup Unit), `EOI_Amount__c`, `Token_Amount__c`, `Source_CP__c` (Lookup Account), `Booking__c` (Lookup, round-trip after Closed Won) | RT: `Pre_sales_Residential` (9-stage BP), `Pre_sales_Commercial` (7-stage BP) |
| `Site_Visit__c` | Custom, 15 fields | Scheduled/logged site visits | `Lead__c` / `Opportunity__c` (either parent), `Source_Channel__c` (Formula, derives from whichever parent is set) | Created via `Schedule_Site_Visit` Screen Flow |

**Opportunity StandardValueSet augmentation (E06a):** 6 active stages were added alongside the 7 stock SDO stages — `New`, `Qualified`, `Site Visit Scheduled`, `Site Visit Done`, `EOI`, `Token Paid`, `Closed Won (Booked)` — scoped per-RT via two new `BusinessProcess` records (`Pre_sales_Residential`, `Pre_sales_Commercial`). The legacy `Pre_Sales_Process` BP was marked inactive (not deleted) once the two new BPs took over.

### 3.2 Inventory cluster

| Object | Type | Purpose | Key fields | Relationships |
|---|---|---|---|---|
| `Project__c` | Custom, 21 fields, 2 RTs | Top-level property (10 residential + 2 commercial in demo data) | `Project_Code__c` (Text(3), unique), `Launch_Status__c`, `Total_Units__c`/`Available_Units__c`/`Booked_Units__c` (roll-ups), `Sellthrough_Pct__c` (Formula) | Parent of Tower__c (MD) |
| `Tower__c` | Custom, 13 fields, 2 RTs | Tower (residential) or Block (commercial) | `Project__c` (Master-Detail), `Tower_Code__c` (Formula(Text)), `Total_Units__c`/`Available_Units__c`/`Booked_Units__c` (roll-ups) | MD child of Project__c; MD parent of Unit__c |
| `Unit__c` | Custom, 26 fields, 2 RTs | Individual saleable unit/shop | `Tower__c` (Master-Detail), `Project__c` (Formula(Text), NOT Lookup — Salesforce formulas can't return references), `Unit_Code__c` (Formula(Text)), `Unit_Status__c` (state-machine picklist), `Base_Price__c` (Formula(Currency)), `Active_Booking__c` (Lookup Booking__c) | MD child of Tower__c |
| `Pricing_Component__c` | Custom, 11 fields | Per-booking snapshotted pricing line items | `Booking__c` (Master-Detail) | MD child of Booking__c |

`Unit__c.Unit_Status__c` state machine (enforced in Apex, §4.4/§5.2): `Available → Blocked → {Available, Booked} → Cancelled → Available`. Five declared transitions; everything else rejected.

### 3.3 Booking cluster

| Object | Type | Purpose | Key fields | Relationships |
|---|---|---|---|---|
| `Booking__c` | Custom, 34 fields, 2 RTs | Post-sales record of a confirmed sale | `Opportunity__c`, `Unit__c`, `Primary_Buyer__c`, `Project__c` (Formula, traverses `Unit__r.Tower__r.Project__r.Project_Code__c`), `Booking_Status__c` (lifecycle: Confirmed → Agreement Pending → Agreement Signed → Registered → Possession Ready → Possessed / Cancelled), `Total_Paid__c` (roll-up SUM of Receipt.Amount), `Total_Outstanding__c` (Formula), `Source_CP__c` (Lookup Account) | Created from Opportunity at Closed Won (E08); parent of Demand/Receipt/Agreement/Possession/Pricing_Component/Booking_Customer/Booking_Payment_Schedule |
| `Booking_Customer__c` | Custom, 7 fields | Junction — joint-buyer support | `Booking__c`, `Contact__c`, `Is_Primary__c`, `Ownership_Pct__c`, `Payment_Share_Pct__c` | Enables `Booking__c.Customer_Count__c` roll-up and `Joint_Booking__c` formula |

### 3.4 Payment Plan / Demand / Receipt cluster

| Object | Type | Purpose | Key fields |
|---|---|---|---|
| `Payment_Plan__c` | Custom, 6 fields | Named plan template (CLP/DLP/PLP demo seeds) | `Active__c` (guarded by VR — see gotcha #40), `Milestone_Count__c` / `Total_Pct_Check__c` (roll-ups) |
| `Payment_Plan_Milestone__c` | Custom, 8 fields | Milestone template row | `Payment_Plan__c` (Master-Detail), `Percentage__c`, `Sequence__c`, `Trigger_Type__c` |
| `Booking_Payment_Schedule__c` | Custom, 13 fields | Per-Booking instantiated schedule row | `Booking__c` (Master-Detail), `Scheduled_Amount__c`, `Expected_Date__c`, `Status__c` (Pending → Demand Raised → …) |
| `Demand__c` | Custom, 21 fields | Raised payment demand (GST/TDS-computed) | `Booking__c` (Master-Detail), `Net_Payable__c`/`Days_Overdue__c` (Formula), `PDF_Generated__c`, `Status__c` |
| `Receipt__c` | Custom, 15 fields | Buyer payment received | `Booking__c` (Master-Detail), `Amount__c`, `Amount_Allocated__c` (roll-up SUM of Receipt_Allocation), `Status__c` (Received → Under Reconciliation → Reconciled) |
| `Receipt_Allocation__c` | Custom, 5 fields | Junction — Receipt applied to Demand (or Advance) | `Receipt__c`, `Demand__c` (Lookup, `required=false` — enables advance payments) |

### 3.5 Agreement / Possession cluster

| Object | Type | Purpose | Key fields |
|---|---|---|---|
| `Agreement__c` | Custom, 17 fields | Sale agreement + registration | `Booking__c` (Master-Detail, 1:1 enforced in Apex), `Agreement_Value__c` (Formula = `Booking__r.Agreement_Value__c`), `Status__c` (Not Started → … → Signed → Executed), `ESign_Provider__c`/`ESign_Envelope_Id__c`/`ESign_Status__c` (display-only, no live e-sign integration) |
| `Possession__c` | Custom, 15 fields | Handover record | `Booking__c` (Master-Detail, 1:1 enforced in Apex), `Snag_Count__c`/`Open_Snag_Count__c` (native roll-ups, filtered), `All_Dues_Cleared__c` (Formula) |
| `Snag_Item__c` | Custom, 9 fields | Punch-list item during snag phase | `Possession__c` (Master-Detail), `Description__c` (required), `Reported_Date__c` (required), `Status__c` |

`Booking.Agreement__c` and `Booking.Possession__c` are both single-slot **Lookups** (label "Related Agreement"/"Related Possession") — the corresponding child objects are Master-Detail *to* Booking. The 1:1 cardinality itself is Apex-enforced (`AgreementService`/`PossessionService` reject a second create against the same Booking); it is not a platform-level constraint.

### 3.6 Channel Partner / Commission cluster

| Object | Type | Purpose | Key fields |
|---|---|---|---|
| `Commission_Rate_Card__c` | Custom, 10 fields | Per Project × CP Tier milestone rate schedule | `Booking_Pct__c`/`Agreement_Pct__c`/`Registration_Pct__c`, `Active__c` (Formula, date-window based), `Effective_From__c`/`Effective_To__c` |
| `Commission_Ledger__c` | Custom, 15 fields | One row per milestone accrual (or clawback) | `Booking__c` (Master-Detail), `Channel_Partner__c` (Lookup Account), `Milestone__c` (Booking / Agreement / Registration / Clawback), `Rate_Pct__c` (snapshotted, not live), `Gross_Commission__c`/`Net_Payable__c` (Formula), `Status__c`, `Payout__c` (Lookup) |
| `Commission_Payout__c` | Custom, 11 fields | Monthly per-CP payout batch record | `Channel_Partner__c`, `Entry_Count__c`/`Gross_Commission__c`/`GST_Total__c`/`TDS_Total__c` (plain fields, Apex-computed — not roll-ups, since Ledger's MD parent is Booking, not Payout), `Status__c`, `Statement_PDF_Id__c` (unpopulated — see §12) |

### 3.7 CP Portal / Account scoping

The CP portal has no dedicated custom object of its own — it scopes existing objects (`Lead`, `Booking__c`, `Site_Visit__c`, `Commission_Ledger__c`, `Commission_Payout__c`) to the logged-in CP's `Account` via the `CP_Scope` Apex utility (§7) plus (once E16's manual Setup is completed) Experience Cloud Sharing Sets. `Account.Portal_Access__c` gates whether a CP Account's contacts can be provisioned as portal users.

### 3.8 Supporting cluster

| Object | Type | Purpose |
|---|---|---|
| `Notification_Preference__c` | Custom, 8 fields | Per-user/contact notification channel preferences |
| `Concession_Request__c` | Custom, 12 fields | Discount request routed through the 2-tier Approval Process |
| `Document_Checklist__c` | Custom, 9 fields | KYC/legal document tracking per Booking |

### 3.9 Relationship diagram (prose form)

```
Project__c (MD parent)
 └─ Tower__c (MD parent)
     └─ Unit__c ── Active_Booking__c (Lookup) ──► Booking__c

Lead ──(Project_Interest__c Lookup)──► Project__c
Lead ──(assignment)──► RM / CP_Manager_Queue

Opportunity ──(Project__c Lookup)──► Project__c
Opportunity ──(Primary_Unit__c Lookup)──► Unit__c
Opportunity ──(Source_CP__c Lookup)──► Account [Channel_Partner RT]
Opportunity ══(Closed Won trigger, E08)══► Booking__c [created]
Opportunity ◄──(Booking__c Lookup, round-trip)── Booking__c

Booking__c (MD parent)
 ├─ Booking_Customer__c (junction → Contact)
 ├─ Booking_Payment_Schedule__c
 ├─ Demand__c
 │    └─ (referenced by) Receipt_Allocation__c ◄── Receipt__c (MD parent)
 ├─ Agreement__c  [Booking.Agreement__c Lookup points back]
 ├─ Possession__c [Booking.Possession__c Lookup points back]
 │    └─ Snag_Item__c
 ├─ Pricing_Component__c
 └─ Commission_Ledger__c ──(Channel_Partner__c Lookup)──► Account [CP RT]
                          ──(Payout__c Lookup)──► Commission_Payout__c

Payment_Plan__c (MD parent)
 └─ Payment_Plan_Milestone__c
      (instantiated per-Booking into Booking_Payment_Schedule__c by PaymentScheduleService)

Commission_Rate_Card__c ──(Project__c + CP_Tier__c key)──► resolved by RateCardService
```

### 3.10 Record types summary

9 objects carry record types: `Lead` (Residential_Lead, Commercial_Lead), `Account` (Buyer, Corporate_Buyer, Channel_Partner), `Opportunity` (Pre_sales_Residential, Pre_sales_Commercial), `Booking__c` (Residential_Booking, Commercial_Booking), `Project__c` (Residential, Commercial), `Tower__c` (Residential_Tower, Commercial_Block), `Unit__c` (Residential_Unit, Commercial_Shop) — 15 record types total across these 7 objects.

### 3.11 Validation rules deployed (14, live)

| Object | Rule | Purpose |
|---|---|---|
| `Project__c` | `Project_Code_Format` | Enforces 3-uppercase-letter code |
| `Tower__c` | `Tower_Name_Matches_Code` | `Name` must equal derived `Tower_Code__c` |
| `Unit__c` | `Floor_In_Range`, `Unit_Number_In_Range` | Bounds-check against Tower's declared floor/unit counts |
| `Opportunity` | `Require_Project_After_Qualified`, `Require_Unit_By_Negotiation`, `Closed_Won_Requires_Financials`, `Closed_Lost_Requires_Reason` | Stage-gated field requirements, all `ISCHANGED(StageName)`-scoped |
| `Booking__c` | `Unit_Must_Be_Blocked_At_Booking`, `Source_CP_Must_Be_Active` | Booking-time integrity guards |
| `Payment_Plan__c` | `Active_Plan_Total_Pct_Must_Be_100` | Milestone percentages must sum to 100 on active plans (interacts with gotcha #40 — see §11) |
| `Commission_Rate_Card__c` | `All_Milestones_Required`, `Effective_From_Required`, `Effective_To_After_From` | Rate card data-quality guards (`Effective_From_Required` is flagged as dead/unreachable code in §12 — the field-level Required already covers it) |

---

## 4. Automation Layer

### 4.1 Flows (10 deployed)

All Screen Flows launched from Booking/Receipt/Demand/Opportunity Quick Actions wrap an `@InvocableMethod` Apex service — the Apex holds the business logic and bulkification; the Flow is a thin UI shell (confirmation screen, input capture, error display).

| Flow | Type | Trigger | Calls | Fault handling |
|---|---|---|---|---|
| `Raise_Demand` | Screen | Quick Action on Booking | `DemandService.raiseDemands` | ✅ `faultConnector` → Error_Screen (fixed in critical-fix pass) |
| `Allocate_Receipt` | Screen | Quick Action on Receipt | `ReceiptAllocationService.allocateReceipts` | ✅ Fixed |
| `Create_Agreement` | Screen | Quick Action on Booking | `AgreementService.createAgreements` | ✅ Fixed |
| `Create_Possession` | Screen | Quick Action on Booking | `PossessionService.createPossessions` | ✅ Fixed |
| `Generate_Demand_Letter` | Screen | Quick Action on Demand | `DemandLetterService.generateDemandLetters` | ✅ Fixed |
| `Schedule_Site_Visit` | Screen | Quick Action on Opportunity | Direct `recordCreates` on `Site_Visit__c` | ✅ Fixed |
| `Request_Concession` | Screen | Quick Action on Opportunity | Direct `recordCreates` on `Concession_Request__c` | ✅ Fixed |
| `Cancel_Booking` | Screen | Quick Action on Booking | `CancellationService.cancelBookings` | ✅ Fixed |
| `Transfer_Booking_To_Post_Sales_Queue` | Record-Triggered (After-Save, Create) | Booking insert | `Update_Booking_Owner` (direct record update) | ✅ Fixed — also guarded against a null-queue lookup crashing every Booking insert on a rebuilt SDO |
| `CP_Status_Change_Handler` | Record-Triggered (Before-Save, Update) | `Account.CP_Status__c` change | Field derivation only (no Apex/DML risk) | ✅ Clean at original review — no fault path needed (no throwing call in this flow) |

All 10 flows carry `<processType>Flow</processType>` (or `AutoLaunchedFlow` for the record-triggered pair) at `apiVersion=62.0`, except `Transfer_Booking_To_Post_Sales_Queue` which is pinned to `66.0` (matching `sfdx-project.json`'s `sourceApiVersion`) — a known inconsistency, see §12 (Suggestion S4).

### 4.2 Approval Processes (2 deployed)

| Process | Object | Steps | Notes |
|---|---|---|---|
| `Concession_Approval` | `Concession_Request__c` | Step 1 (PSM, ≤5%, `FirstResponse`, `RejectRequest`) → Step 2 (Sales Head, >5%, `RejectRequest`) | Entry criteria `Status__c IN ('Draft','PSM Review')` supports recall+resubmit. Companion `Concession_Request__c.workflow-meta.xml` (6 field updates) drives the initial-submission / final-approval / final-rejection actions — this is a required implementation detail of the Approval Process feature, not parallel legacy Workflow automation (confirmed clean in code review S5). |
| `CP_Registration_Approval` | `Account` (Channel_Partner RT) | Single step, specific-user approver | Entry criteria `RecordType = Channel Partner AND CP_Status = Pending Approval`. Final approval sets `CP_Status=Active` + `Portal_Access=true`; final rejection sets `CP_Status=Suspended`. |

**Open warning (W1, unfixed):** neither process's first approval step declares `<rejectBehavior>` — only `Concession_Approval`'s second step (`Sales_Head_Tier`) does. Both files were retrieved from a live already-deployed org rather than authored from scratch, so this predates the review and relies on undocumented platform default-on-reject behavior. Not blocking; flagged for symmetry.

### 4.3 Assignment Rules (1 deployed)

`Lead.RECRM_Lead_Assignment` — single rule, 7 first-match-wins entries: CP-sourced leads → `CP_Manager_Queue`; Walk-in leads route project-aware (PRK→rm.prk, SPL→rm.spl, no-project→saleshead fallback); 6 digital-channel values route the same project-aware way; final catch-all → saleshead. Routes on `Lead.Project_Code_Text__c`, a `Formula(Text)` field created specifically because assignment-rule criteria cannot traverse `__r` Lookup relationships (gotcha #23).

### 4.4 Trigger framework

One trigger per object, thin trigger → handler → service, consistently applied across all 7 triggers (confirmed "exemplary" in code review, 3–8 lines each, zero business logic in trigger bodies):

| Trigger | Object | Context(s) | Handler | Routes to |
|---|---|---|---|---|
| `UnitTrigger` | `Unit__c` | Before Update | `UnitTriggerHandler` | `UnitLifecycleService.onBeforeUpdate` — the 5-transition state machine (Available↔Blocked↔Booked→Cancelled→Available), audit history append, field clearing on → Available |
| `OpportunityTrigger` | `Opportunity` | After Update | `OpportunityTriggerHandler` | `BookingService.onOpportunityClosedWon` (guarded by `RecursionGuard`) |
| `BookingTrigger` | `Booking__c` | After Insert, After Update | `BookingTriggerHandler` | After Insert → `CommissionService.accrueOnBooking`; After Update (guarded) → `PaymentScheduleService.onPaymentPlanSelected` + `CommissionService.clawbackOnCancellation` |
| `DemandTrigger` | `Demand__c` | Before Insert | `DemandTriggerHandler` | `DemandNamingService.onBeforeInsert` (no guard needed — before-insert, no self-DML) |
| `AgreementTrigger` | `Agreement__c` | Before Insert, After Update | `AgreementTriggerHandler` | Before Insert → `AgreementNamingService`; After Update (guarded) → `AgreementService.onAfterUpdate` + `CommissionService.accrueOnAgreementSigned`/`accrueOnRegistration` |
| `PossessionTrigger` | `Possession__c` | Before Insert, After Update | `PossessionTriggerHandler` | Before Insert → `PossessionNamingService`; After Update (guarded) → `PossessionService.onAfterUpdate` |
| `CommissionLedgerTrigger` | `Commission_Ledger__c` | Before Insert | `CommissionLedgerTriggerHandler` | `CommissionLedgerNamingService` (self-computing sequence, no stored `_Seq__c` field) |

`RecursionGuard.cls` (`isFirstRun(key)` / `reset(key)` / `@TestVisible resetAll()`) protects every after-update handler whose service performs DML capable of re-firing the same trigger. It was shipped as a utility in E07 with zero consumers (a deliberate "establish the pattern early" decision) and picked up its first real consumer in E08.

---

## 5. Apex Architecture

### 5.1 Service layer (by domain)

| Service | Domain | Key methods |
|---|---|---|
| `BookingService` | Booking creation | `onOpportunityClosedWon` — 6-step: filter Closed-Won opps, compute per-project-per-year sequence (`BKG-{PROJ}-{YY}-{nnnn}`), insert Booking, transition Unit Blocked→Booked, round-trip Opportunity.Booking__c |
| `UnitLifecycleService` | Inventory state machine | `onBeforeUpdate` — 5-transition guard, append-only text audit trail in `Status_History__c` |
| `UnitBlockingService` | Inventory | `blockUnit` — invocable, sets Blocked + expiry; pre-checks current status before allowing (added in E07 on top of E06c's original happy-path-only version) |
| `PaymentScheduleService` | Payment Plan instantiation | `onPaymentPlanSelected` — delete-then-recreate schedule rows on plan switch; computes `Scheduled_Amount` and `Expected_Date` per milestone trigger type |
| `DemandService` | Demand raising | `raiseDemands` — invocable; computes GST (0/1/5% bracket model) and TDS (§194IA simplified 1%/0% threshold) per Indian tax rules; transitions schedule row to Demand Raised |
| `ReceiptAllocationService` | Receipt reconciliation | `allocateReceipts` — invocable; aggregates via fresh `AggregateResult` (not stale roll-up reads) for both Demand and Receipt status transitions; supports advance payments (null Demand) |
| `AgreementService` | Agreement workflow | `createAgreements` (invocable) + `onAfterUpdate` (Signed→Agreement Signed, Executed→Registered Booking sync) |
| `PossessionService` | Possession handover | `createPossessions` (invocable) + `onAfterUpdate` (Handed Over→Possessed Booking sync); Snag roll-ups are native, no Apex |
| `CommissionService` | Commission accrual/clawback | `accrueOnBooking`, `accrueOnAgreementSigned`, `accrueOnRegistration`, `clawbackOnCancellation` — see §10 |
| `RateCardService` | Commission infrastructure | `getActiveRateCard`/`getActiveRateCards` — typed lookup of the active rate card for a Project × CP Tier combination |
| `CancellationService` | Booking cancellation | `cancelBookings` — invocable, 7-step cascade (Demands → Agreement → Possession → refund calc → Booking → Unit); commission clawback fires implicitly via the existing `BookingTrigger` wiring, zero coupling |
| `DemandLetterService` | PDF generation | `generateDemandLetters` — invocable, VF `renderAs="pdf"` → `ContentVersion`/`ContentDocumentLink` |
| `CP_Scope` | CP portal security | `getCpAccountId()`/`currentCpAccountId()` — the only sanctioned way for a portal controller to resolve "whose data" (§7) |

Every naming service (`AgreementNamingService`, `DemandNamingService`, `PossessionNamingService`, `CommissionLedgerNamingService`) follows the same bulk-query-parent-then-set-Name pattern, kept deliberately separate from business-logic services so direct DML / Data Loader imports also get correctly-named records.

### 5.2 Trigger handlers

See §4.4 — 7 handlers, one per triggered object, routing by `TriggerOperation` to the service layer. No business logic lives in a handler; each is a thin dispatcher.

### 5.3 Invocable / Agentforce actions

| Class | Consumer | Purpose | Bulkification status |
|---|---|---|---|
| `MatchInventoryAction` | `Lead_Qualification_Agent`, `Sales_RM_Copilot` | Ranks up to 3 Unit matches for a Lead by budget fit | ✅ Fixed (was per-request SOQL+DML loop; now bulk-hydrates Leads by `Set<Id>` first) |
| `ScoreAndRouteLeadAction` | `Lead_Qualification_Agent` | Scores Lead Hot/Warm/Cold, routes to RM queue | ✅ Fixed (bulk-fetch + cached queue lookups) |
| `QueryAvailableUnitsAction` | `Sales_RM_Copilot` | Natural-language-filtered inventory search | ✅ Fixed (project references resolved once for the whole batch) |
| `GetNextBestActionAction` | `Sales_RM_Copilot` | Recommends next action on an Opportunity from stage + activity recency | ✅ Fixed — single `Id IN :ids` query hydrates the whole batch, scoring itself is pure in-memory logic (0 DML) |

All four are `public with sharing`, `@InvocableMethod`-based, `List<Request> → List<Response>` per platform convention, and (as of the critical-fix pass) bulk-hydrate every SOQL dependency across the whole request list rather than per-record. See §12 for the residual test-coverage gap on `GetNextBestActionAction`.

### 5.4 Batch classes

`CommissionPayoutBatch` — `Database.Batchable<SObject>` + `Schedulable`. `start` queries Accrued/Approved ledger entries with `Payout__c = null`; `execute` groups by `Channel_Partner__c`, computes Apex aggregates (Entry_Count, Gross/GST/TDS totals — plain fields, not roll-ups, since Ledger's Master-Detail parent is Booking, not Payout), inserts one Payout per CP, links entries back. `Schedulable.execute` re-launches the batch for chunked monthly runs. Cron registration (`System.schedule(...)`) is a one-line manual step, not yet deployed as a `CronTrigger` metadata component.

### 5.5 Integration interface layer — architectural intent vs. built state

`CLAUDE.md` non-negotiable #6 and `PROJECT_CONTEXT.md`'s "Integration interfaces" pattern describe an `I<Service>` interface + `<Service>Stub` implementation + `ServiceFactory` (selected via `Integration_Config__mdt`) for e-sign (`IESignService`) and KYC (`IKYCService`) integrations, with Phase 2 adapters swapped in later.

**Reconciliation finding: none of `IESignService`, `IKYCService`, `ServiceFactory`, `ESignServiceStub`, or `Integration_Config__mdt` exist anywhere in `force-app/`** (confirmed via repo-wide grep). Agreement's e-sign fields (`ESign_Provider__c`, `ESign_Envelope_Id__c`, `ESign_Status__c`, added in E02b) are populated nowhere and are explicitly noted as "display-only" in E12's design decisions. This is a **documented, deliberate deferral** (E12 D10: "Future epic will wire `IESignService` interface with a Stub and a Leegality adapter"), not silent drift — but it means the interface-first pattern described as an existing convention in `CLAUDE.md`/`PROJECT_CONTEXT.md` is currently aspirational for e-sign/KYC specifically. Any future epic that needs to send an Agreement for e-signature will need to build this layer from scratch; it should not be assumed to already exist.

### 5.6 Test strategy and coverage

- `TestDataFactory.cls` is the single builder utility for all test data (Project, Tower, Unit, Account, Opportunity, Booking, Payment Plan + Milestones, Demand, Receipt + Allocation, Agreement, Possession + Snag, CP Account, Rate Card, Commission Ledger/Payout). Every builder honors the validation rules on its target object (documented as gotcha #30) and pre-computes any Name that a VR enforces.
- Coverage is consistently 90–100% on every trigger/handler/service class shipped through E21 (per-epic figures cited throughout §3 originate from synchronous test runs with `--code-coverage`, worked around CLI v2.84.6's async-reporting bugs — gotcha #31).
- **Gap:** 6 LWC-backing controller classes (`BookingLifecycleController`, `BuyerProfileController`, `DemandCollectionController`, `PaymentTimelineController`, `ProjectInventoryController`, `UnitStatusCardController`) have **zero test coverage** — flagged in code review as W2, violating non-negotiable #8 ("every class has a companion test class"). Not yet remediated.
- **Gap:** `RecursionGuard.reset(key)` remains uncovered (only `resetAll()` and `isFirstRun()` are exercised) — deferred until a real consumer needs mid-transaction reset.

---

## 6. LWC / UI Layer

### 6.1 Internal record-page components (6, E15)

| Component | Object | Controller | Purpose |
|---|---|---|---|
| `bookingLifecycleTracker` | Booking__c | `BookingLifecycleController` | Visual path indicator of Booking lifecycle stages |
| `paymentTimeline` | Booking__c | `PaymentTimelineController` | Vertical milestone timeline with status badges |
| `demandCollectionSummary` | Booking__c | `DemandCollectionController` | 3 metric tiles + collection progress bar |
| `unitStatusCard` | Unit__c | `UnitStatusCardController` | Status badge + live blocking countdown (`setInterval`, cleaned up in `disconnectedCallback`) |
| `projectInventoryChart` | Project__c | `ProjectInventoryController` | Hand-rolled SVG donut chart (no charting library) |
| `buyerProfileCard` | Account | `BuyerProfileController` | Identity card with PAN masking (`XXXXXX1234`) |

Design patterns: single-SOQL controllers returning a wrapper class (both the class and every property need `@AuraEnabled`), `cacheable=true` on all read methods, `WITH SECURITY_ENFORCED` on every query, SLDS-first CSS. Embedded into `Booking_Record_Page`, `Unit_Record_Page`, `Project_Record_Page` flexipages; `buyerProfileCard` is available but not auto-embedded (Account uses SDO-default flexipages the project doesn't own — manual App Builder placement is a documented follow-up).

### 6.2 Screen Flows as the invocable-service UI shell

See §4.1 — 8 of the 10 flows are Screen Flows launched from Quick Actions, giving one-click UI access to the E08–E13/E21 Apex services without duplicating business logic in the UI layer.

### 6.3 Error handling pattern

Every `AuraHandledException` message across the Apex service layer is specific and actionable, and (post critical-fix pass) every Flow calling one of those services now has a `faultConnector` routing to an Error screen displaying `{!$Flow.FaultMessage}`. LWC components follow a consistent isLoading/error/data pattern; `cpSubmitLead` wraps its imperative Apex call in try/catch/finally with `ShowToastEvent` feedback and a double-submit guard.

---

## 7. CP Portal (Experience Cloud)

### 7.1 Isolation model — defense in depth

Every CP portal request passes through three independent layers, per E15's design:

```
Portal user → LWC
      │  (cacheable @AuraEnabled)
      ▼
Cp{Page}Controller
  FIRST line: Id cpId = CP_Scope.getCpAccountId();
  SOQL: WHERE <link field> = :cpId  AND  WITH SECURITY_ENFORCED   ◀── Layer 1 (SOQL scope + FLS)
  Returns a wrapper class, never a raw SObject                    ◀── Layer 2 (field whitelisting)
      │
      ▼
CP_Scope: User → Contact → Account, no raw UserInfo in business queries   ◀── Layer 3 (identity resolution)
```

`CP_Scope.getCpAccountId()` (code in §5.1's class list; full body reproduced below) is the **only** sanctioned way a portal controller learns whose data to return:

```apex
public static Id currentCpAccountId() {
    Id userId = UserInfo.getUserId();
    List<User> users = [SELECT ContactId FROM User WHERE Id = :userId AND ContactId != null WITH SECURITY_ENFORCED LIMIT 1];
    if (users.isEmpty() || users[0].ContactId == null) {
        throw new AuraHandledException('Unable to determine your Channel Partner account. Please contact your administrator.');
    }
    List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :users[0].ContactId WITH SECURITY_ENFORCED LIMIT 1];
    if (contacts.isEmpty() || contacts[0].AccountId == null) {
        throw new AuraHandledException('Your user is not linked to a Channel Partner account.');
    }
    return contacts[0].AccountId;
}
```

A `@TestVisible testCpAccountId` static override lets tests inject a CP Id without provisioning a real portal user — every controller test includes a bidirectional `testCpIsolation_BothDirections` method that flips the override between two CP accounts and asserts each sees only its own data.

### 7.2 Portal controllers (6) and LWCs (6)

| Controller | Wrapper | LWC | Scope field |
|---|---|---|---|
| `CpDashboardController` | `DashboardData{leadCount, activeBookings, ytdCommission, pendingPayouts}` | `cpDashboard` | Multiple SOQL, all `Source_CP__c`/`Channel_Partner__c = cpId` |
| `CpLeadListController` | `LeadData[]` | `cpLeadList` | `Lead.Source_CP__c` |
| `CpSubmitLeadController` | `getActiveProjects()`, `submitLead(...)` | `cpSubmitLead` | Write path — `Source_Channel__c` hardcoded `'CP'`, `Source_CP__c` from `CP_Scope` |
| `CpSiteVisitsController` | `VisitData[]` | `cpSiteVisits` | `Lead__r.Source_CP__c OR Opportunity__r.Source_CP__c` |
| `CpCommissionsController` | `CommissionSummary{entries[], totalGross, totalNet, totalAccrued, totalPaid}` | `cpCommissions` | `Commission_Ledger__c.Channel_Partner__c` |
| `CpPayoutsController` | `PayoutData[]` | `cpPayouts` | `Commission_Payout__c.Channel_Partner__c` |

All 6 LWC bundles target both `lightningCommunity__Page` (portal) and `lightning__RecordPage` (internal review by PSM/Sales Head) — 100% adherence to gotcha #47's correct target-name form confirmed clean in code review.

### 7.3 What is NOT yet built: the Experience Cloud site itself

E15 shipped the Apex/LWC **code** layer only. The actual Digital Experiences site (Build Your Own LWR template, domain, page assembly, Sharing Sets, CP portal permission set, demo portal user) is documented as **E16's manual Setup-UI walkthrough** inside the E15 epic doc — a 7-step click-trail (enable Digital Experiences → create the LWR site → configure Sharing Sets → place the 6 LWCs on 6 pages → create `CP_Portal_User` permission set → create the demo portal user → run the isolation smoke test). **Nothing in source confirms this walkthrough has been executed on the current SDO.** Until it is, the portal code is deployed but has no live front door. Sahil should confirm E16's completion status; if not done, it is the single largest remaining gap between "code complete" and "demo-able."

### 7.4 Sharing model for external users (once E16 is complete)

Per the E16 spec: OWD Private/Private (internal/external) on Account, Contact, Lead, Booking__c, Commission_Ledger__c, Commission_Payout__c, Site_Visit__c; one Sharing Set per object granting Read where `Object.Source_CP__c = $User.Contact.AccountId`. This is the **infrastructure** layer; `CP_Scope`'s SOQL filter is the **application** layer; `WITH SECURITY_ENFORCED` is the **FLS** layer — all three must hold simultaneously for the portal to be secure (E15's explicit design note).

---

## 8. Agentforce Layer

### 8.1 How this layer came to exist in source

Unlike every other part of this system, the three Agentforce agents were **not** built epic-first from a spec. They were built directly in the org via Agent Builder in Setup UI (2026-05-25 through 2026-06-03) with zero corresponding commits — discovered only when a routine "spec vs. build" review found Phase 1 Architecture Section 11 apparently 0% implemented in source, which was true of the repo but not of the org. E18 is the retroactive fix: retrieved the agents from the org (working around two CLI/metadata retrieval bugs, gotchas #45–46), reconstructed source format, and documented the divergence from spec.

### 8.2 The three agents

| Agent (`GenAiPlannerBundle`) | Topics | Custom Invocable actions |
|---|---|---|
| `Lead_Qualification_Agent` | Lead Qualification, General FAQ | `MatchInventoryAction`, `ScoreAndRouteLeadAction` |
| `Sales_RM_Copilot` | Inventory Search, Next Best Action, Lead Matching | `QueryAvailableUnitsAction`, `MatchInventoryAction`, `GetNextBestActionAction` |
| `Booking_Analysis_Agent` | Report Data Analysis | None custom — standard CRM Analytics actions only (`AnalyzeMetric`, `SummarizeDashboard`) |

Every topic also carries the standard `AnswerQuestionsWithKnowledge` action, attached by the Agent Builder template rather than custom-built.

### 8.3 What each action does

- **`MatchInventoryAction.matchInventory`** — takes a Lead Id, returns up to 3 ranked `Unit__c` matches by budget fit with a rationale string.
- **`ScoreAndRouteLeadAction.scoreAndRoute`** — scores a Lead Hot/Warm/Cold and routes it to an RM queue.
- **`QueryAvailableUnitsAction.queryUnits`** — natural-language-filtered inventory search for the RM Copilot's Inventory Search topic.
- **`GetNextBestActionAction.getNBA`** — recommends the next action on an Opportunity from stage + activity recency + key financial fields (see §5.3 for the full stage-branching logic).

### 8.4 Known gaps vs. the Phase 1 Architecture Document, Section 11

Documented explicitly in E18 rather than silently treated as "done":

- **No automatic Lead-insert invocation.** Section 11.1 specifies the Lead Qualification Agent fires automatically on Lead insert via a record-triggered Flow. No such Flow/trigger exists — the agent is chat/conversation-invoked only.
- **`DraftMessage` action never built.** Only 3 of the 4 spec'd Sales RM Copilot topics/actions exist; the "no-auto-send follow-up draft" capability is missing.
- **No `Agent_Invocation_Log__c` observability object** (Section 11.3) — agent invocations are not logged for audit/tuning.
- **`Booking_Analysis_Agent` is not in the Phase 1 Architecture Document at all** — an undocumented third agent built the same week as the other two. Recommend Sahil confirm whether this was deliberate scope addition or an experiment to deactivate.
- **Grounding via `Project.Brochure_URL__c` as a knowledge source** was not verified during the E18 retrieval pass.
- **Publish/activation status not verified** — whether these agents are attached to an active Messaging channel or Sales Coach panel, or remain in Setup-only draft state, is an open manual-UI check.

---

## 9. Security Model

### 9.1 Organization-Wide Defaults

Tightened in E03 from the SDO's default `ReadWrite`/`Private`:

| Object | Internal / External OWD |
|---|---|
| `Project__c` | Read / Private |
| `Lead` | Private / Private |
| `Account` | Private / Private |
| `Contact` | ControlledByParent / ControlledByParent (requires **both** `<sharingModel>` and `<externalSharingModel>` declared explicitly — gotcha #11) |
| `Site_Visit__c` | Private / Private |
| `Booking__c` | Private / Private |
| `Payment_Plan__c` | Read / Private |
| `Commission_Rate_Card__c` | Read / Private |
| `Commission_Payout__c` | Private / Private |
| `Notification_Preference__c` | Private / Private |
| `Concession_Request__c` | Private / Private |

All Master-Detail children inherit `ControlledByParent`. `EntityDefinition.InternalSharingModel` misreports Contact specifically (surfaces effective, not declared, sharing — gotcha #12); Setup UI is authoritative for Contact OWD verification.

### 9.2 Role hierarchy (14 roles)

A standalone `RECRM_*` tree parallel to the 85 pre-existing stock SDO roles (none modified/deleted): `RECRM_CEO` → `RECRM_VP_Sales` → {`RECRM_Sales_Head` → `RECRM_PSM_PRK`/`RECRM_PSM_SPL`/`RECRM_PSM_Commercial` → their respective `RECRM_RM_Team_*`; `RECRM_Head_Of_Post_Sales` → `RECRM_Post_Sales_Team_Lead` → `RECRM_Post_Sales_Exec`; `RECRM_Head_Of_CPs` → `RECRM_CP_Manager`}.

### 9.3 Sharing rules (4, criteria-based)

| Rule | Object | Criterion | Shared to |
|---|---|---|---|
| `CP_Accounts_Visible_To_RECRM` | Account | `RecordTypeId = 'Channel Partner'` (Label, not DeveloperName) | `roleAndSubordinates = RECRM_CEO` |
| `Bookings_To_Sales_Head` | Booking__c | `Booking_Date__c notEqual null` (substitutes for the spec's cross-object-formula criterion, which sharing rules reject) | `roleAndSubordinates = RECRM_Sales_Head` |
| `CP_Sourced_Bookings_To_CP_Manager` | Booking__c | `Source_Channel__c equals 'CP'` (substitutes for a Lookup-to-Account criterion, also rejected) | `roleAndSubordinates = RECRM_CP_Manager` |
| `CP_Sourced_Opps_To_CP_Manager` | Opportunity | `Source_Channel__c equals 'CP'` | `roleAndSubordinates = RECRM_CP_Manager` |

### 9.4 Permission sets (6, per-persona)

| Permission set | Scope |
|---|---|
| `RECRM_Inventory_Admin` | CRUD: Project, Tower, Unit, Payment_Plan+Milestone, Commission_Rate_Card. Read: Booking. |
| `RECRM_CP_Manager` | CRUD: Account (CP RT), all commission objects. Read: Contact, Booking, Opportunity, Unit, Tower, Project, Payment_Plan. |
| `RECRM_RM` / `RECRM_PSM` / `RECRM_Sales_Head` | Identical object/field scope (CRUD Lead/Opportunity/Site_Visit/Concession_Request/Notification_Preference; Read Account/Contact/Unit/Project/Tower/Booking/Payment_Plan) — persona differences live in approval-tier assignment and role/queue membership, not FLS/CRUD. |
| `RECRM_Post_Sales_Exec` | CRUD: Booking + all downstream children (Demand, Receipt, BPS, Agreement, Possession, Snag, Doc_Checklist, junctions, Pricing_Component). Read: Opportunity, Account, Contact, Unit, Project, Tower, Payment_Plan. |

`Pricing_Component__c` was reassigned from Inventory_Admin to Post_Sales_Exec during E04 build because its Master-Detail-parent-Read dependency chain (gotcha #14) required Booking access, which is semantically Post-Sales' domain anyway.

The (not-yet-confirmed-deployed) `CP_Portal_User` permission set for external Experience Cloud users is documented in E15/E16 but its existence in `force-app/` was not independently re-verified for this document beyond the epic's own claim — see §7.3.

### 9.5 Field-Level Security approach

Custom fields carry **no FLS on any profile by default when deployed via Metadata API — including the System Administrator profile** (gotcha #27, the single most consequential platform quirk this project hit). `ModifyAllData`/`ViewAllData` bypass FLS for object-level CRUD but not for field visibility in SOQL or on Lightning record pages. The mitigation applied throughout: grant FLS on the Admin profile and the relevant persona permission set(s) in the **same commit** as the field metadata. Required, Formula (MasterDetail/RollupSummary/AutoNumber), fields carry implicit FLS and must be *excluded* from explicit `<fieldPermissions>` blocks (gotchas #15, #25, #26) — formula fields are the one counter-intuitive exception, needing an *explicit* `editable=false` grant despite being read-only, because SOQL selectability of a formula field is not inherited from its underlying referenced fields.

### 9.6 CP portal isolation guarantee

See §7.1–7.4. Confirmed "airtight" in the full codebase review — all 6 portal controllers scope every SOQL through `CP_Scope`, each with a dedicated bidirectional isolation test, full compliance with `CLAUDE.md` non-negotiable #7.

---

## 10. Commission Engine

### 10.1 Architecture

```
RateCardService (E14) — getActiveRateCards(Project × CP_Tier)
        │
Booking AFTER_INSERT / Agreement AFTER_UPDATE / Booking AFTER_UPDATE
        ▼
CommissionService — accrueOnBooking / accrueOnAgreementSigned /
                     accrueOnRegistration / clawbackOnCancellation
        │ insert/update
        ▼
Commission_Ledger__c (Master-Detail to Booking)
   Naming trigger: CL-{Booking Name}-{nn}
        │ batched & rolled up (monthly)
        ▼
CommissionPayoutBatch (Database.Batchable + Schedulable)
   groups Accrued/Approved entries with no Payout, by CP
        ▼
Commission_Payout__c — AutoNumber CPY-{YY}-{MM}-{000}
```

### 10.2 Three-milestone accrual

| Milestone | Trigger | Filter |
|---|---|---|
| Booking | `BookingTrigger` AFTER_INSERT | `Source_CP__c != null` |
| Agreement Signed | `AgreementTrigger` AFTER_UPDATE | `old.Status != 'Signed' && new.Status == 'Signed'` |
| Registration | `AgreementTrigger` AFTER_UPDATE | `Registration_Date` null→non-null AND `Status == 'Executed'` |

Each milestone creates one `Commission_Ledger__c` row via a shared internal `accrueMilestone` core that bulk-loads CP accounts (Tier + GSTIN) and rate cards once per batch. **No active rate card for a Project × Tier combination is a silent skip (logged at `WARN`), not a blocking error** — commission accrual is deliberately decoupled from the Booking/Agreement lifecycles it observes.

### 10.3 Rate storage and formula quirk

`Rate_Pct__c` stores the literal display value (2 for 2%, not 0.02) because Salesforce's `Currency × Percent` formula evaluation treats the Percent operand as a decimal automatically — `1,000,000 * 2` (as a `Currency * Percent` formula) yields 20,000, not 2,000,000. Apex GST/TDS computation explicitly divides by 100 to mirror this: `gross = (basis * ratePct / 100).setScale(2)`.

### 10.4 GSTIN-driven GST logic

If the CP has no GSTIN on file, an 18% reverse-charge GST is added to Net (rather than deducted, since the developer bears the tax burden in that scenario); with a GSTIN, GST is 0 at the ledger-entry level (CP self-invoices). TDS is a flat 5% in the commission context (distinct from the Demand-side §194IA 1% threshold model in §5.1's `DemandService` — two independent tax computations for two different transaction types).

### 10.5 Clawback-on-cancellation logic

Fires implicitly — `CancellationService` has zero direct coupling to `CommissionService`; the Booking status transition to `Cancelled` in `CancellationService`'s Step 6 fires `BookingTrigger AFTER_UPDATE`, which (per the E17 wiring inside `BookingTriggerHandler`) calls `CommissionService.clawbackOnCancellation`.

- **Accrued or Approved** entries: `Status` flipped to `Clawed Back` in place — no new record, audit trail is the modification timestamp.
- **Paid** entries: the original is **never modified** (audit preservation). A new offset entry is inserted with `Milestone = 'Clawback'`, negated basis/GST/TDS, `Status = 'Accrued'` (flows through the normal approval/payout cycle as a negative line on the next payout), and `Hold_Reason` cross-referencing the original entry's Name.

### 10.6 Payout batching

`Commission_Payout__c.Entry_Count__c`/`Gross_Commission__c`/`GST_Total__c`/`TDS_Total__c` are plain fields computed by `CommissionPayoutBatch` in Apex — not roll-up summaries, because `Commission_Ledger__c`'s Master-Detail parent is `Booking__c`, not `Commission_Payout__c` (the Ledger→Payout link is a Lookup). Cron registration for the monthly run (`System.schedule('Monthly CP Payout', '0 0 1 1 * ? *', new CommissionPayoutBatch())`) is a one-line manual step, not yet a deployed `CronTrigger`.

---

## 11. Deployment Model

### 11.1 SDO constraints

- **Single org, no scratch orgs, no sandboxes, no packaging.** Every deploy targets `re-crm-sdo` directly via `sf project deploy start --target-org re-crm-sdo`.
- **The repo is the source of truth.** The SDO may be refreshed or rebuilt without warning; every deployable artefact must live in `force-app/`.
- **`docs/manual-setup-steps.md` captures the non-deployable residue** — currently: demo-user temp passwords (regenerated each SDO refresh, `.invalid` TLD emails), plus (referenced but not yet appended in that file) the Approval Process for CP Registration/Concession per E14's D3 decision, and Field History Tracking enablement for Booking cancellation audit (E21).
- **`scripts/deploy.sh`** wraps `sf project deploy start` with a configurable `--test-level`; defaulted to `NoTestRun` while the org had zero Apex, and is expected to move toward `RunLocalTests` now that Apex coverage is substantial (not confirmed changed in source at time of writing).

### 11.2 Deploy tooling quirks worth a technical reader knowing

The full gotcha list lives in `CLAUDE.md` (47 numbered entries, continuing from #48 for future additions). The highest-impact ones for anyone extending this system:

- **#27 — Freshly-deployed custom fields have no FLS anywhere, including Admin.** Always bundle FLS grants with field metadata in the same commit.
- **#31 — Salesforce CLI v2.84.6 on this dev machine misreports Apex deploy/test results** (`MetadataTransferError: Missing message metadata.transfer:Finalizing`, `TypeError: Cannot read properties of null`) while the underlying deploy/test actually succeeds. Verify via `sf project deploy report --job-id <id> --json` and direct Tooling API queries (`ApexTestResult`, `ApexCodeCoverageAggregate`) rather than trusting the CLI's own summary output.
- **#40 — Master-Detail child DML re-evaluates the parent's Validation Rules mid-batch**, even within a single bulk insert. `Payment_Plan__c.Active_Plan_Total_Pct_Must_Be_100` cannot be satisfied by inserting milestones and the parent atomically in one transaction — the pattern is seed inactive, insert children, activate the parent as a **separate, later** step (manual Setup UI edit, since rollup commits are async).
- **#45/#46 — Agentforce metadata (`GenAiPlannerBundle`) cannot be retrieved in source format at all on this org** (a CLI resolver bug, not a metadata defect, confirmed unfixed across CLI versions 2.120.3→2.147.7) and **requires API version 65.0** specifically, independent of the rest of the org's Apex API version. Retrieve via `--target-metadata-dir` and hand-reconstruct source format; validate with a dry-run deploy expecting `Unchanged` on every file.
- **#41 — Flow-type Quick Actions belong in `<platformActionList>`, not `<quickActionList>`** on page layouts — the latter is reserved for Create/Update/VisualforcePage/feed-item/SendEmail action types.
- **#11/#12 — Contact OWD requires both `<sharingModel>` and `<externalSharingModel>` declared together**, and `EntityDefinition` misreports Contact's *declared* OWD as its *effective* (post-Account-propagation) OWD — Setup UI is authoritative for verification.

### 11.3 Manual-setup dependency

Beyond `docs/manual-setup-steps.md`'s tracked items, several epics document deferred manual Setup-UI work that is **not yet reflected as completed anywhere in source**:
- Page-layout-to-(Profile×RecordType) assignments (E06-layout) — required for the 29 layouts to actually appear.
- Flexipage-as-org-default activation for 22 custom-object record pages (E06-layout Phase 2) — 22 individual Setup UI clicks per SDO refresh, or a future `scripts/assign-flexipages.apex`.
- App visibility per persona (E06-apps) — currently all 4 Lightning Apps are visible to every profile.
- The full Experience Cloud CP portal site build (E16, see §7.3) — the largest single deferred item.
- Approval Process for CP Registration/Concession-adjacent flows the E14 base epic referenced as design D3 (though `CP_Registration_Approval` and `Concession_Approval` approval processes *are* present in `force-app/`, retrieved from the live org per commit `590fe1b`).
- Currency locale (India/INR) at the Company Information level.
- Field History Tracking on `Booking__c.Booking_Status__c`/`Cancellation_Date__c`.

---

## 12. Known Issues / Technical Debt

Source: `agent-output/2026-08-15-full-codebase-review.md` (117 files reviewed: 70 Apex classes, 7 triggers, 12 LWCs, 10 flows, 14 validation rules, 2 approval processes, 1 assignment rule, 1 legacy workflow file). The review found 14 critical, 25 warning, and 5 suggestion-level issues. **All 14 criticals were fixed and deployed as of 2026-08-15/16** (confirmed in this pass by re-reading `GetNextBestActionAction.cls`, which is now bulk-hydrated, and all 10 flow XMLs, which now all carry `<faultConnector>`). The 25 warnings and 5 suggestions below were **not** part of that remediation pass and remain open.

### 12.1 Fixed (for reference — no longer open)

- 5 Agentforce/Invocable Apex action classes (`CancellationService`, `GetNextBestActionAction`, `MatchInventoryAction`, `QueryAvailableUnitsAction`, `ScoreAndRouteLeadAction`) issued SOQL/DML inside per-request loops — all bulkified to hydrate the whole batch with `Set<Id>`-keyed queries up front.
- 9 of 10 Flows had no `<faultConnector>` on an Apex action call or `recordCreates` element capable of throwing — all 9 now route to an Error screen.

### 12.2 GetNextBestActionAction coverage gap (discovered during the critical-fix deploy)

`GetNextBestActionActionTest.cls` has 8 test methods, all exercising the invocable with a **single-item request list**. Unlike the other bulkified action test classes, there is no test asserting correct 1:1 request→response ordering or governor-limit safety across a large batch (e.g., 200 requests spanning many distinct Opportunities). The class itself is correctly bulkified (confirmed by code inspection in §5.3/8.3), but the test suite does not *prove* that bulkification at scale — a latent verification gap rather than a functional defect. Recommend adding a bulk test mirroring the pattern already used elsewhere (e.g., `CommissionServiceTest`'s 3-Booking-×-3-CP-tier bulk case) before this class sees any further changes.

### 12.3 Open warnings (25 found; not all individually listed — see full review for exhaustive detail)

The most consequential:

| # | Issue | Files affected |
|---|---|---|
| W1 | Approval Process `rejectBehavior` gaps on first-tier steps | `CP_Registration_Approval`, `Concession_Approval` (PSM_Tier) |
| W2 | 6 controller classes have zero test coverage | `BookingLifecycleController`, `BuyerProfileController`, `DemandCollectionController`, `PaymentTimelineController`, `ProjectInventoryController`, `UnitStatusCardController` |
| W3 | 12 trigger-handler/naming-service classes omit an explicit sharing declaration (no `with sharing`/`without sharing`) | `AgreementNamingService`, `AgreementTriggerHandler`, `BookingTriggerHandler`, `CommissionLedgerNamingService`, `CommissionLedgerTriggerHandler`, `DemandNamingService`, `DemandTriggerHandler`, `OpportunityTriggerHandler`, `PossessionNamingService`, `PossessionTriggerHandler`, `UnitTriggerHandler`, `UnitLifecycleService` |
| W4 | `DemandService.raiseDemands` has no null/empty-list guard (unlike every sibling invocable) | `DemandService.cls` |
| W5 | Redundant Booking-owner assignment — both `BookingService` (Apex, at insert) and `Transfer_Booking_To_Post_Sales_Queue` (Flow, after-save) set `OwnerId` to the same queue | `BookingService.cls`, `Transfer_Booking_To_Post_Sales_Queue.flow-meta.xml` |
| W6 | `cpLeadList`'s row-click navigation handler is dead code (no action column defined, so `onrowaction` can never fire) | `lwc/cpLeadList/` |
| W7 | `Effective_From_Required` validation rule is unreachable dead code — the field-level `Required` attribute already fires first | `Commission_Rate_Card__c/validationRules/Effective_From_Required` |

The remaining 18 warnings are lower-impact variants of the same three themes (missing sharing declarations, missing null guards, minor UX/dead-code items) — see the full review file for the complete list.

### 12.4 Open suggestions (5)

- **S1** — Booking sequence-number race window: two Closed-Won transactions on the same Project landing near-simultaneously could theoretically compute the same sequence number (in-memory count, not a locked counter). Low probability at demo scale.
- **S2** — `UnitBlockingService`'s "Unit not found" error message doesn't identify which unit in a bulk request.
- **S3** — `GetNextBestActionActionTest` uses a hardcoded fake Id literal rather than a runtime-constructed nonexistent Id.
- **S4** — Inconsistent metadata API versions: all LWCs and 9/10 Flows pinned to 62.0; `Transfer_Booking_To_Post_Sales_Queue` and `sfdx-project.json` are on 66.0.
- **S5** — The retained `Concession_Request__c.workflow-meta.xml` (field updates only, no rules) should carry a one-line note so a future cleanup pass doesn't mistake it for dead legacy automation — it is a required implementation detail of the Approval Process feature.

### 12.5 Other technical debt identified during this documentation pass

- **Interface-first integration layer does not exist** (`IESignService`/`IKYCService`/`ServiceFactory`/`Integration_Config__mdt`) despite being described as an established pattern in `CLAUDE.md` and `PROJECT_CONTEXT.md` — see §5.5. This is documented deferral, not drift, but should not be assumed present by a new contributor reading only the top-level convention docs.
- **CP Portal Experience Cloud site completion is unconfirmed** — see §7.3. The code layer (E15) is complete and tested; the site itself (E16) is a manual walkthrough whose execution status is not recorded anywhere in source.
- **Concurrent-insert sequence numbering** used by both `BookingService` (Booking naming) and `DemandService`/`CommissionLedgerNamingService` (per-parent sequence numbers) is SOQL-count-based, not lock-protected — acceptable at SDO single-user demo scale, flagged repeatedly across epics as a Phase-2 hardening item (replace with a locked Custom Setting or platform sequence).
- **GST/TDS tax logic is a simplified bracket model** (3-bracket GST, single-threshold §194IA TDS) rather than a full Indian tax rule engine — acceptable for demo narrative, explicitly flagged in E10 as a candidate for replacement with a Custom Metadata Type rate card in Phase 2.

---

## 13. Appendix

### 13.1 Glossary of domain terms

| Term | Meaning |
|---|---|
| **BSP** | Basic Sale Price — the per-square-foot rate before floor-rise/corner/park premiums. |
| **CP** | Channel Partner — a real-estate broker/agent Account (record type `Channel_Partner`) who sources leads/bookings in exchange for tiered commission. |
| **CLP / DLP / PLP** | Construction Linked Plan / Down Payment Plan / Possession Linked Plan — the three demo Payment Plan templates. |
| **Demand** | A raised payment request against a Booking, computed with GST/TDS, tied to a Payment Plan milestone. |
| **EOI** | Expression of Interest — an early-stage Opportunity milestone/stage indicating serious buyer intent, typically with a token amount. |
| **NOC** | No Objection Certificate — issued at possession once all dues are cleared (referenced in Possession's `All_Dues_Cleared__c` gate; PDF generation not yet built). |
| **NRI** | Non-Resident Indian — a buyer classification affecting KYC and tax handling. |
| **PLC** | Preferential Location Charge — a percentage premium added to Base Price for corner units or park-facing units. |
| **Possession** | The handover event/record marking a Booking as complete (keys handed over). |
| **RERA** | Real Estate (Regulation and Development) Act — Indian regulatory framework; `RERA_Number__c`/`RERA_State__c` fields track project registration. |
| **Sellthrough** | Percentage of a Project's total units that are Booked, computed as a roll-up-derived formula. |
| **Snag** | A defect/punch-list item logged during the possession snag-rectification phase. |
| **TDS** | Tax Deducted at Source — Indian withholding tax; §194IA governs real-estate transactions above ₹50L. |
| **UTR** | Unique Transaction Reference — bank payment reference number, captured on Commission Payout for reconciliation (field exists, capture workflow manual). |

### 13.2 Object API name reference

| API Name | Standard/Custom | Domain |
|---|---|---|
| `Lead` | Standard (extended) | Lead-to-Opportunity |
| `Account` | Standard (extended) | Lead-to-Opportunity / CP |
| `Contact` | Standard (extended) | Lead-to-Opportunity |
| `Opportunity` | Standard (extended) | Lead-to-Opportunity |
| `Site_Visit__c` | Custom | Lead-to-Opportunity |
| `Project__c` | Custom | Inventory |
| `Tower__c` | Custom | Inventory |
| `Unit__c` | Custom | Inventory |
| `Pricing_Component__c` | Custom | Inventory / Booking |
| `Booking__c` | Custom | Booking |
| `Booking_Customer__c` | Custom | Booking |
| `Payment_Plan__c` | Custom | Payment Plan / Demand / Receipt |
| `Payment_Plan_Milestone__c` | Custom | Payment Plan / Demand / Receipt |
| `Booking_Payment_Schedule__c` | Custom | Payment Plan / Demand / Receipt |
| `Demand__c` | Custom | Payment Plan / Demand / Receipt |
| `Receipt__c` | Custom | Payment Plan / Demand / Receipt |
| `Receipt_Allocation__c` | Custom | Payment Plan / Demand / Receipt |
| `Agreement__c` | Custom | Agreement / Possession |
| `Possession__c` | Custom | Agreement / Possession |
| `Snag_Item__c` | Custom | Agreement / Possession |
| `Commission_Rate_Card__c` | Custom | Channel Partner / Commission |
| `Commission_Ledger__c` | Custom | Channel Partner / Commission |
| `Commission_Payout__c` | Custom | Channel Partner / Commission |
| `Notification_Preference__c` | Custom | Supporting |
| `Concession_Request__c` | Custom | Supporting |
| `Document_Checklist__c` | Custom | Supporting |

### 13.3 API version note

`sfdx-project.json` declares `sourceApiVersion: 66.0`. Most existing components (LWCs, 9 of 10 flows) are pinned to `62.0`, the version current when those epics were built; only the most recently touched flow (`Transfer_Booking_To_Post_Sales_Queue`) matches the project-level 66.0. This is tracked as Suggestion S4 in §12.4 — a housekeeping item, not a functional defect.

---

*End of Technical Design Document. This document synthesizes `PROJECT_CONTEXT.md`, all 24 files under `docs/epics/`, the deployed `force-app/main/default/` metadata tree, `agent-output/2026-08-15-full-codebase-review.md`, and `CLAUDE.md`'s 47-entry gotcha list as of 2026-08-16. It does not modify any of those source files.*
