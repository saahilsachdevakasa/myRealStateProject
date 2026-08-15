# E18 — Agentforce: Lead Qualification Agent + Sales RM Copilot

## Goal

Per Phase 1 Architecture Section 11: two Agentforce agents grounded on CRM
data only (no Data Cloud) — a Lead Qualification Agent that scores and
routes inbound leads, and a Sales RM Copilot that assists RMs with
inventory queries and next-best-action guidance on Lead/Opportunity
records.

## How this epic differs from every other epic in this repo

Every other epic in `docs/epics/` was built epic-first: spec drafted,
reviewed, then Claude Code produced metadata straight into `force-app/`.

**This one is backwards.** The agents already existed, fully built and
working, directly in `RealEstateSDO` — created via Agent Builder in
Setup UI on **2026-05-25 through 2026-06-03**, with zero corresponding
commits, epic doc, or `force-app/` footprint. This was discovered by
querying the org directly (`GenAiPlannerBundle` / `GenAiPluginDefinition`
/ `GenAiFunctionDefinition` via Tooling API) after a routine "what's
built vs. the architecture doc" review found Section 11 apparently
0% implemented in source — which was true of the repo, but not of the
org. Per CLAUDE.md's core rule ("the repo is the source of truth...
every piece of metadata must be in `force-app/`"), roughly three months
of working Agentforce build had been one SDO refresh away from
disappearing without a trace.

This epic is the retroactive fix: retrieve what exists, get it into
source, document what it actually does (which differs from the Section
11 spec in a few places — see below), and record the tooling problems
hit along the way as gotchas for future retrieval work.

## Dependencies

- E04 (permission sets, queues, users) — agents act on Lead/Opportunity/Unit
  data under the existing persona model
- E07 (unit status lifecycle) — inventory matching queries `Unit_Status__c`
- E08 (Opportunity → Booking) — Sales RM Copilot's Get Next Best Action
  reads Opportunity stage/activity data

## In scope (what was retrieved and backfilled)

Three agents, retrieved from the org and reconstructed in source format
under `force-app/main/default/genAiPlannerBundles/`,
`force-app/main/default/genAiFunctions/`, and
`force-app/main/default/classes/`:

| Agent (`GenAiPlannerBundle`) | Topics (`localTopics`) | Custom actions |
|---|---|---|
| **Lead_Qualification_Agent** | Lead Qualification, General FAQ | Match Inventory for Lead, Score and Route Lead |
| **Sales_RM_Copilot** | Inventory Search, Next Best Action, Lead Matching | Query Available Units, Match Inventory for Lead, Get Next Best Action |
| **Booking_Analysis_Agent** | Report Data Analysis | (standard `AnalyzeMetric` / `SummarizeDashboard` CRM Analytics actions only — no custom Apex) |

Every topic also carries the standard `AnswerQuestionsWithKnowledge`
action (knowledge-article search) — attached by the Agent Builder
template, not custom-built.

### Apex actions (4 classes + 4 test classes, all retrieved)

| Class | `@InvocableMethod` | Called by |
|---|---|---|
| `MatchInventoryAction` | `matchInventory(List<MatchRequest>)` — takes a Lead Id, returns up to 3 `Unit__c` matches ranked by budget fit, with rationale | Lead_Qualification_Agent's *Lead Qualification* topic, Sales_RM_Copilot's *Lead Matching* topic |
| `ScoreAndRouteLeadAction` | Scores a Lead Hot/Warm/Cold and routes to an RM queue | Lead_Qualification_Agent's *Lead Qualification* topic |
| `QueryAvailableUnitsAction` | Natural-language-filtered inventory search | Sales_RM_Copilot's *Inventory Search* topic |
| `GetNextBestActionAction` | Recommends next action on an Opportunity from stage + activity recency | Sales_RM_Copilot's *Next Best Action* topic |

All four are `public with sharing`, bulkified (`List<Request>` →
`List<Response>` per platform convention for invocable actions), and
have matching test classes already in the org (now in source too).

## Out of scope / known gaps against the Section 11 spec

The org's actual build diverges from the architecture doc in several
places. Documenting the divergence rather than silently treating the
org as "done":

- **No automatic Lead-insert invocation.** Section 11.1 specifies the
  Lead Qualification Agent fires automatically via a record-triggered
  Flow on Lead insert. **No such Flow or trigger exists** — confirmed
  by grepping `force-app/main/default/flows/` and `triggers/` for any
  reference to the four action classes; there are none outside the
  agent bundles themselves and their test classes. The agent is
  chat/conversation-invoked only (Agentforce Messaging/Sales Coach
  surface), not record-triggered. Whether this is an intentional
  simplification or an unfinished piece of E18 is unknown — flag to
  Sahil.
- **`DraftMessage` (Sales RM Copilot's "no-auto-send follow-up draft"
  action, Section 11.2) was never built.** Only 3 of the 4 topics/actions
  described for the Copilot exist (Inventory Query, Project Q&A via
  standard knowledge search, Next-Best-Action). Draft Follow-Up
  Message is missing entirely.
- **No `Agent_Invocation_Log__c` observability object** (Section 11.3).
  Agent invocations are not logged to a custom object for audit/tuning
  as the spec requires.
- **`Booking_Analysis_Agent` is not in the Phase 1 Architecture Document
  at all.** A third agent, built the same week as the other two, doing
  report/dashboard analysis via standard CRM Analytics actions
  (`AnalyzeMetric`, `SummarizeDashboard`) — no custom Apex. Undocumented
  anywhere prior to this epic file. Recommend Sahil confirm whether this
  was deliberate scope addition or an experiment that should be
  deactivated.
- **Grounding via `Project.Brochure__c` (uploaded PDFs as a knowledge
  source, Section 11.2)** was not verified — out of scope for this
  retrieval pass, which focused on getting the planner/function/Apex
  layer into source, not auditing every grounding source.
- **Publish/activation status not verified.** This epic did not confirm
  whether these agents are attached to an active Messaging channel,
  the Agentforce Sales Coach panel, or are still in Setup-only draft
  state. Recommend a manual UI check.

## Non-functional: how the retrieval actually happened

Two tooling problems blocked a normal source-format retrieve; both are
recorded as CLAUDE.md gotchas #45–46 and summarized here for context.

1. **`sf project retrieve start` (source format) throws a false-positive
   `TypeInferenceError: Unexpected child metadata ... found for parent
   type [CustomObject]`** on the alphabetically-first `QuickAction` file
   in any object's `quickActions/` folder — confirmed unrelated to
   Agentforce metadata (it blocks retrieval of *anything*, project-wide)
   and confirmed **not fixed by upgrading the CLI** (reproduced
   identically on 2.120.3 and the latest 2.147.7). Root-caused by
   temporarily removing the flagged file and re-running: the error just
   moved to the new alphabetically-first sibling, proving the bug is in
   the CLI's local resolver, not in any one metadata file.
2. **Worked around** by retrieving in metadata format instead
   (`--target-metadata-dir`, bypasses the buggy local-source scan),
   then hand-reconstructing the source-format layout: Apex classes
   copied as-is; `GenAiFunction`/`GenAiPlannerBundle` bundles had their
   bare `<Name>.<type>` file renamed to `<Name>.<type>-meta.xml` with
   subfolders (`input/`, `output/`, `localActions/`, `plannerActions/`)
   copied unchanged.
3. **`GenAiPlannerBundle` required manifest API version 65.0** —
   62.0 (which matches the org's Apex classes) and 64.0 both failed with
   entity-not-available / unsupported-version errors specific to that
   type. `GenAiFunction` retrieved fine at 62.0.
4. **Validated the hand-reconstruction** with
   `sf project deploy start --source-dir <paths> --dry-run
   --test-level NoTestRun` — all 55 components reported `Unchanged`
   (byte-identical to the org), 0 errors.

## Artefacts produced by this epic

```
force-app/main/default/classes/
  MatchInventoryAction.cls(-meta.xml)          + MatchInventoryActionTest.cls(-meta.xml)
  ScoreAndRouteLeadAction.cls(-meta.xml)       + ScoreAndRouteLeadActionTest.cls(-meta.xml)
  QueryAvailableUnitsAction.cls(-meta.xml)     + QueryAvailableUnitsActionTest.cls(-meta.xml)
  GetNextBestActionAction.cls(-meta.xml)       + GetNextBestActionActionTest.cls(-meta.xml)

force-app/main/default/genAiFunctions/
  Match_Inventory_for_Lead/{Match_Inventory_for_Lead.genAiFunction-meta.xml, input/schema.json, output/schema.json}
  Score_and_Route_Lead/{...}
  Query_Available_Units/{...}
  Get_Next_Best_Action/{...}

force-app/main/default/genAiPlannerBundles/
  Lead_Qualification_Agent/{Lead_Qualification_Agent.genAiPlannerBundle-meta.xml, localActions/, plannerActions/}
  Sales_RM_Copilot/{...}
  Booking_Analysis_Agent/{...}

manifest/
  agentforce-retrieve.xml           # GenAiPlannerBundle (v62 attempt) + GenAiPlugin + GenAiFunction + the 8 Apex files, v62.0
  agentforce-planner-retrieve.xml   # GenAiPlannerBundle + GenAiPlugin, v65.0 (the version that actually works)

CLAUDE.md
  gotcha #45 — TypeInferenceError retrieve bug + metadata-format workaround
  gotcha #46 — per-type API version requirements for Agentforce metadata
```

## Implementation notes

- Re-retrieving in future: use `manifest/agentforce-planner-retrieve.xml`
  for planner bundles (v65.0) and `manifest/agentforce-retrieve.xml` for
  the Apex/GenAiFunction layer (v62.0 is fine there) — don't merge them
  into one manifest/version, the planner bundle type will fail at 62.0.
- Any future edit to agent topic instructions, scope, or actions made
  via Agent Builder in Setup UI must be re-retrieved through this same
  metadata-format workaround and re-committed — there is no
  source-format path that currently works for this org on this
  metadata type combination (gotcha #45).
- Do not attempt `sf project retrieve start` in source format on this
  org for *any* metadata that touches an object with a `quickActions/`
  folder until gotcha #45 is independently confirmed fixed upstream —
  it will fail regardless of which components you're actually trying to
  retrieve.

## Implemented

- [x] Root-caused the source-format retrieve blocker (CLI bug, not a
      metadata defect) — proved via file-removal test
- [x] Retrieved 3 `GenAiPlannerBundle` agents, 4 `GenAiFunction`
      definitions, 4 Apex action classes + 4 test classes via
      metadata-format retrieve
- [x] Hand-reconstructed source format for all retrieved components
- [x] Validated reconstruction with a dry-run deploy — 0 errors, all
      components `Unchanged`
- [x] Documented 2 new CLAUDE.md gotchas (#45, #46)
- [x] Upgraded `@salesforce/cli` 2.120.3 → 2.147.7 (confirmed the
      retrieve bug persists regardless — see gotcha #45)
- [ ] Not done: reconciling the 4 gap items above with Sahil (auto-invocation
      on Lead insert, DraftMessage action, Agent_Invocation_Log__c,
      the undocumented Booking_Analysis_Agent's status)
