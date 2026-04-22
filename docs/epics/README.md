# Epic specifications

Per-epic context files. Each file is the ground truth for Claude Code when executing an epic.

## Naming

`E{nn}-{kebab-case-topic}.md`

Examples: `E01-project-setup.md`, `E07-inventory-lifecycle.md`, `E17-commission-engine.md`

## When files are written

**Just-in-time, not in bulk.** Drafting all 23 epic files up-front locks in assumptions that may evolve as earlier epics execute. Each epic file is drafted within a day or two of that epic starting.

## Workflow (SDO-targeted)

When a new epic approaches:

1. **Draft the file** using the template in Phase 1 Architecture Document Section 14.4 (`docs/phase1-architecture.docx`).
2. **Review with the Product Owner** (Sahil). Tighten acceptance criteria and out-of-scope markers before handing off.
3. **Hand off to Claude Code** from the repo root: `start E07` (or the matching epic ID).
4. Claude Code produces metadata, Apex, and tests under `force-app/`.
5. Deploy and test against the SDO: `./scripts/deploy.sh <sdo-alias>`.
6. Commit to git with a conventional commit message (e.g., `feat(E07): unit status lifecycle`).
7. Update the epic file's "Implemented" section.

## Template structure

Every epic file contains:

- **Objective** — one-paragraph statement of intent
- **Dependencies** — prior epics that must be complete (already deployed to SDO)
- **In scope** — concrete list of artefacts to produce
- **Out of scope** — explicitly deferred to named future epics
- **Acceptance criteria** — testable statements
- **Non-functional** — performance, security, governor-limit notes
- **Artefacts to produce** — list of file paths under `force-app/`
- **Manual Setup steps (if any)** — click-trail additions to `docs/manual-setup-steps.md`
- **Implementation notes** — patterns or edge cases to watch
- **Implemented** (filled post-build) — summary of what was produced

Do not embed commit SHAs in the Implemented section. Use `git log --grep='E0X'` to find the commits. Embedding SHAs creates a self-reference paradox when docs are amended.

## Status

Currently: **no epic files drafted**. E01 will be drafted next.
