# E05 — Assignment Rules, Approval Processes, Booking Ownership Flow

## Objective

Operationalise the routing and approval layer on top of E03 (sharing) +
E04 (permissions, queues, users). After E05, inbound Leads get
auto-routed to the right RM or queue by source/project criteria,
Concession Requests flow through a 2-tier approval process (PSM ≤5%,
Sales Head >5%), and Booking inserts auto-transfer ownership to the
Post-Sales Queue. The org is now functional for the demo's Lead → Opp
→ Booking lifecycle without manual ownership reassignment.

## Dependencies

- **E04** complete — 7 demo users live, 2 queues exist, 6 permission
  sets assigned. Approval-process step approvers (psm.prk, saleshead)
  and assignment-rule routees (rm.prk, rm.spl, saleshead, cpmgr) all
  reference users that exist on the org.
- **E03** complete — `RECRM_*` roles exist; assignment rule queue
  membership flows through them.
- **E02b** complete — `Concession_Request__c`, `Lead`,
  `Project_Interest__c`, `Source_Channel__c`, `Booking__c` all in the
  data model.

## In scope

### 1 Flow
- `Transfer_Booking_To_Post_Sales_Queue` — Record-Triggered After-Save on
  `Booking__c` create. Always fires (no entry criteria). Gets the
  `Post_Sales_Queue` Group record by DeveloperName, then updates the
  triggering Booking's `OwnerId` to the queue's Id.

### 1 Approval Process
- `Concession_Request__c.Concession_Approval` — 2-tier:
  - **Step 1 (PSM Tier):** entry criteria `Requested_Pct__c <= 5`,
    approver `psm.prk@recrm-demo.invalid`, `ifCriteriaNotMet=GoToNextStep`,
    `rejectBehavior=RejectRequest`.
  - **Step 2 (Sales Head Tier):** entry criteria `Requested_Pct__c > 5`,
    approver `saleshead@recrm-demo.invalid`, `rejectBehavior=RejectRequest`.
  - Entry: `Status__c IN ('Draft','PSM Review')` (allows recall+resubmit).
  - Initial submission: Status → PSM Review.
  - Final approval: Status → Approved, Approved_Pct ← Requested_Pct,
    Approval_Date ← TODAY(), Expiry_Date ← TODAY()+7.
  - Final rejection: Status → Rejected.
  - Allow recall: yes.

### 1 Workflow (companion to approval process)
- `workflows/Concession_Request__c.workflow-meta.xml` — 6
  WorkflowFieldUpdates referenced by the approval process actions:
  - `Set_Status_PSM_Review` (Initial Submission)
  - `Set_Status_Approved`, `Set_Approved_Pct`, `Set_Approval_Date`,
    `Set_Expiry_Date` (Final Approval)
  - `Set_Status_Rejected` (Final Rejection)

### 1 AssignmentRule
- `Lead.RECRM_Lead_Assignment` — single rule, 7 entries (first-match-wins):
  1. `Source_Channel__c = CP` → CP_Manager_Queue
  2. `Source_Channel__c = Walk-in AND Project_Code_Text__c = PRK` → rm.prk
  3. `Source_Channel__c = Walk-in AND Project_Code_Text__c = SPL` → rm.spl
  4. `Source_Channel__c = Walk-in` (catch-all walk-in, no project) → saleshead
  5. `Source_Channel__c IN (6 digital values) AND Project_Code_Text__c = PRK` → rm.prk
  6. Same digital set AND `Project_Code_Text__c = SPL` → rm.spl
  7. Catch-all → saleshead

### 1 supporting CustomField (mini-deploy enabler)
- `Lead.Project_Code_Text__c` — `Formula(Text)` returning
  `Project_Interest__r.Project_Code__c`. Created because assignment-rule
  criteria cannot traverse Lookup `__r` references directly.

## Out of scope (deferred)

- **Opportunity → Booking trigger** (creates Booking on Opp Closed Won) —
  Apex, ships in **E08**.
- **Round-robin assignment within Post-Sales Queue** to a specific exec —
  scope of E05 is queue ownership; per-exec assignment is a later
  enhancement.
- **Lead Qualification Agent** intelligent routing — replaces or augments
  this declarative assignment rule in **E18**.
- **Approval emails customised** beyond Salesforce defaults — fine for
  demo (`.invalid` emails bounce silently); production tightening later.
- **Per-approver-step Status update** to 'Sales Head Review' when the
  escalation tier engages — not natively supported by approval process
  metadata. See "Known cosmetic issues" below.

## Acceptance criteria

1. `ProcessDefinition` record for `Concession_Approval` exists on
   `Concession_Request__c` (Type=Approval). Active state is implicit from the
   `<active>true</active>` in deployed metadata; empirical activation verification
   requires submitting a Concession_Request for approval — deferred to E23 demo
   rehearsal. (Verified: existence via `ProcessDefinition` SOQL returning 1 row.)
2. `Flow` `Transfer_Booking_To_Post_Sales_Queue` is `IsActive=true`,
   ProcessType=AutoLaunchedFlow. (Verified via `FlowDefinitionView`.)
3. All 6 `WorkflowFieldUpdate` records on `Concession_Request__c` exist
   with the names referenced by the approval process. (Verified via
   tooling-API `WorkflowFieldUpdate` query.)
4. `AssignmentRule` `Lead.RECRM_Lead_Assignment` deployed clean and
   active.
5. `Lead.Project_Code_Text__c` formula field deployed and queryable in
   Setup UI.

## Non-functional

- All metadata redeployable from source on a fresh SDO in a single batch
  deploy (after the prerequisite `Project_Code_Text__c` field deploys
  alone first — it's a chicken-and-egg with the assignment rule).
- No manual Setup-UI steps required.

## Implementation notes

### Design decisions (locked before execution)

- **Walk-in routing** (revised from initial spec). Original spec routed
  every Walk-in lead to `saleshead` as a manual fallback. Revised to
  project-aware routing: Walk-in + PRK → rm.prk, Walk-in + SPL → rm.spl,
  Walk-in + no project → saleshead fallback. Better matches the demo
  narrative where walk-ins happen at physical project sites.

- **Approval-process step status update — Option A** (drop the per-step
  field update). Salesforce approval-process metadata has no native
  "fires when this step is entered" hook — `<approvalActions>` fires on
  step approval, not on step entry. Rather than synthesise it via a
  separate Flow watching `ProcessInstanceStep`, accepted that
  `Status__c='PSM Review'` persists through the entire approval lifecycle
  until Final Approval/Rejection. The Approval History related list
  shows the actual current approver, which is the canonical source of
  truth.

- **Entry criteria `Status__c IN ('Draft','PSM Review')`.** Supports
  recall + resubmit since recall doesn't reset Status. Without the OR
  clause, second submission after recall would fail entry criteria.

- **Single-user step approvers with `whenMultipleApprovers=FirstResponse`.**
  Demo simplification — no Manager-hierarchy lookup since demo users
  have no Manager relationships set. Production would use
  `relatedUser:Manager` for dynamic resolution.

- **`rejectBehavior=RejectRequest` on every step.** No kickback to prior
  approver — rejection ends the request immediately. PSM rejecting a
  ≤5% request and Sales Head rejecting a >5% request both go to
  `finalRejectionActions` (Status='Rejected').

- **Cross-object Lookup criteria → Formula(Text) field workaround.**
  `Project_Code_Text__c` on Lead returns
  `Project_Interest__r.Project_Code__c`. Assignment rules then route on
  this single-field reference. Slight schema bloat, but unavoidable
  given Salesforce's assignment-rule criteria limitations.

### Known cosmetic issues

- **Status='PSM Review' shows during Sales Head review.** The picklist
  value is tier-inaccurate when the escalation approver is the current
  reviewer. Workaround: trust the Approval History related list as the
  true tier indicator. Polish candidates (deferred): rename picklist
  value to a tier-agnostic 'In Approval', or build a Flow that watches
  `ProcessInstanceStep` and updates `Status__c` on tier transitions.

### Gotchas captured (now in CLAUDE.md)

- **#20** — ApprovalStep `<assignedApprover>` requires
  `<whenMultipleApprovers>` even with one approver.
- **#21** — Newly-deployed fields have no FLS by default; SOQL via API
  returns "no such column" while Setup UI shows the field.
- **#22** — ApprovalStep requires `<rejectBehavior>` with no default;
  position is alphabetical between `<name>` and `</approvalStep>`.
- **#23** — Assignment rule criteria cannot traverse Lookup `__r`;
  workaround is a Formula(Text) field on the source object.

## Implemented

**Commits**
See `git log --grep='E05'` for the commits that implemented this epic.

### Files produced

- `force-app/main/default/flows/Transfer_Booking_To_Post_Sales_Queue.flow-meta.xml`
- `force-app/main/default/approvalProcesses/Concession_Request__c.Concession_Approval.approvalProcess-meta.xml`
- `force-app/main/default/workflows/Concession_Request__c.workflow-meta.xml` (6 fieldUpdates)
- `force-app/main/default/assignmentRules/Lead.assignmentRules-meta.xml`
- `force-app/main/default/objects/Lead/fields/Project_Code_Text__c.field-meta.xml`

### Deploy iteration story

Two deploys total: a mini-deploy of the supporting field, then a batch
of the four E05 files.

| Attempt | Failure | Class |
|---|---|---|
| Mini-deploy of `Project_Code_Text__c` | — | Green (1 try) |
| Batch attempt 1 (4 files) | `whenMultipleApprovers` missing on PSM_Tier; `Project_Interest__r.Project_Code__c` cross-object reference rejected | NEW (#20) + NEW (#23, pre-approved fallback available) |
| Batch attempt 2 (after 2 fixes) | `rejectBehavior` missing on Sales_Head_Tier | NEW (#22) |
| Batch attempt 3 (after rejectBehavior added to both steps) | — | Green (11/11 components) |

### Demo-time tests (for E23 rehearsal)

| Scenario | Expected behaviour |
|---|---|
| Submit Concession_Request with Requested_Pct=3% | Routes to psm.prk (Step 1 criteria ≤5% met). Approval → Status=Approved, Approved_Pct=3, Approval_Date=today, Expiry_Date=today+7. |
| Submit Concession_Request with Requested_Pct=8% | Step 1 entry criteria fails (>5%); `ifCriteriaNotMet=GoToNextStep` skips PSM, routes directly to saleshead. Approval → same final actions. |
| Reject at PSM (3% case) | `rejectBehavior=RejectRequest` → finalRejectionActions fire → Status=Rejected. |
| Reject at Sales Head (8% case) | Same — Status=Rejected. |
| Recall, edit, resubmit | Allowed via `<allowRecall>true</allowRecall>`. Entry criteria includes 'PSM Review' so resubmission passes. |
| Lead with Source_Channel='Walk-in', Project_Interest → (a PRK project record) | Routes to rm.prk (entry 2); `Project_Code_Text__c` formula resolves to 'PRK'. |
| Lead with Source_Channel='Walk-in', no Project_Interest | Routes to saleshead (entry 4 catch-all); `Project_Code_Text__c` is blank, so entries 2–3 skipped. |
| Lead with Source_Channel='Digital', Project_Interest → (an SPL project record) | Routes to rm.spl (entry 6); `Project_Code_Text__c` formula resolves to 'SPL'. |
| Lead with Source_Channel='CP' | Routes to CP_Manager_Queue (entry 1). |
| Lead with Source_Channel='Other' (no other criteria match) | Routes to saleshead (entry 7 catch-all). |
| Booking insert | Flow fires → OwnerId reassigned to Post_Sales_Queue. Verify via SOQL: `SELECT OwnerId FROM Booking__c WHERE Id = :newBookingId` returns the queue Group Id. |

### Manual Setup steps

None.

### Known follow-ups for later epics

- **E08**: Apex trigger that creates a `Booking__c` from a Closed-Won
  Opportunity. Will fire this Flow as a side effect.
- **E18**: Lead Qualification Agent — intelligent inbound Lead routing
  to replace or augment the declarative assignment rule.
- **Polish epic (TBD)**: rename `Concession_Request__c.Status__c`
  picklist value `PSM Review` to a tier-agnostic 'In Approval' (or build
  a Flow that updates Status on Sales Head tier engagement).
- **FLS grant for `Lead.Project_Code_Text__c`** in persona permission
  sets — currently admin-only (deploy default). Expose to RM/PSM/
  Sales_Head/CP_Manager when Lead record-page rendering needs it.
