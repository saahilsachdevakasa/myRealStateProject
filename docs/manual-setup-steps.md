# Manual Setup Steps

This file tracks one-time Setup-UI steps that cannot (or should not) be captured in `force-app/` metadata. Whenever the SDO is refreshed or a new org is created, these steps must be reproduced manually **before** running `./scripts/deploy.sh`.

## Why this exists

Some Salesforce features can only be enabled through the Setup UI (or via `sf org create scratch` with specific definition files, which we don't use on SDO). Capturing these steps here makes SDO refreshes reproducible.

## Protocol

Every time Claude Code (or Sahil) configures something via Setup UI that is not in source metadata:

1. Add an entry below under the appropriate section.
2. Include: the Setup path, exact values chosen, and the epic ID where the step first became necessary.
3. If the step can be eliminated by adding metadata to source, do that instead and remove the entry.

## Current manual steps

### One-time org configuration

*(None yet. Will be populated during E01.)*

### Feature activation

*(None yet.)*

### Third-party integrations

*(None yet.)*

### Users and licences

*(None yet. CP portal licences will be noted here when E14 lands.)*

## Template for new entries

```
### <Short title>

**When needed:** <E01 / pre-deploy / post-deploy>
**Setup path:** Setup → <full breadcrumb>
**Action:** <exact clicks and values>
**Why not in source:** <explain why this cannot be captured as metadata>
**Added by epic:** E<nn>
```
