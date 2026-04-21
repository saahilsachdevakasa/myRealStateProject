# HOWTO — Day-to-day SDO workflow

Quick reference for working against your Salesforce SDO.

## One-time setup

### 1. Authenticate your SDO

```bash
sf org login web --alias re-crm-sdo
```

Use your SDO credentials in the browser. The alias `re-crm-sdo` is referenced by every script.

### 2. Set it as default (optional)

```bash
sf config set target-org=re-crm-sdo
```

After this, you can omit `--target-org` from every command.

### 3. Verify

```bash
sf org display --target-org re-crm-sdo
sf org open --target-org re-crm-sdo
```

## Daily workflow

### Check what you have

```bash
sf project list metadata --target-org re-crm-sdo          # what's in the org
sf project retrieve preview --target-org re-crm-sdo       # what would sync down
sf project deploy preview --target-org re-crm-sdo         # what would deploy up
```

### Deploy changes

```bash
./scripts/deploy.sh re-crm-sdo
```

Or directly:

```bash
sf project deploy start --source-dir force-app --target-org re-crm-sdo
```

### Run tests

```bash
# All local tests
sf apex run test --target-org re-crm-sdo --test-level RunLocalTests --result-format human --code-coverage

# Specific test class
sf apex run test --target-org re-crm-sdo --class-names BookingServiceTest --result-format human --code-coverage
```

### Retrieve changes made in the org UI

**Caveat:** if Claude Code or you change metadata in Setup UI, you must retrieve it back to source or it will be lost on SDO refresh.

```bash
sf project retrieve start --source-dir force-app --target-org re-crm-sdo
# or for a specific object:
sf project retrieve start --metadata CustomObject:Booking__c --target-org re-crm-sdo
```

## Working with data

### Seed demo data

After E02 deploys the data model:

```bash
./scripts/seed-demo-data.sh re-crm-sdo
```

This loads 720 inventory records + CPs + rate cards via `sf data import tree` using `data/plan.json`.

### Regenerate CSVs from the master workbook

If you edit `data/_inventory-master.xlsx`:

```bash
python3 data/export_csvs.py
```

### Spot-check data

```bash
sf data query --query "SELECT COUNT() FROM Unit__c" --target-org re-crm-sdo
sf data query --query "SELECT Unit_Status__c, COUNT(Id) FROM Unit__c GROUP BY Unit_Status__c" --target-org re-crm-sdo
```

## When the SDO gets refreshed

Salesforce periodically refreshes SDOs. When this happens:

1. **Re-authenticate** — the old org token is invalid: `sf org login web --alias re-crm-sdo`.
2. **Review manual setup steps** — `docs/manual-setup-steps.md` tracks anything you did via Setup UI.
3. **Rebuild** — run the full refresh script: `./scripts/refresh-sdo.sh re-crm-sdo`.

Total time to rebuild from scratch: around 20–40 minutes depending on epic count.

## Working with Claude Code

From the repo root:

```bash
claude
```

Claude Code reads `CLAUDE.md` automatically on session start. `PROJECT_CONTEXT.md` is referenced by CLAUDE.md and read when needed.

### Starting an epic

```
start E01
```

Claude Code will:

1. Read `docs/epics/E01-project-setup.md`.
2. Produce the artefacts listed in the "Artefacts to produce" section.
3. Run tests locally.
4. Deploy to the SDO.
5. Update the epic file's "Implemented" section.

### Checking what's been done

Each epic file's "Implemented" section accumulates the record of what was produced when that epic ran. This is your audit trail.

## Troubleshooting

### Deploy fails with "invalid session"

Re-auth: `sf org login web --alias re-crm-sdo`

### Deploy fails with test failures

Run specific failing tests to diagnose:

```bash
sf apex run test --target-org re-crm-sdo --class-names <FailingTestClass> --result-format human
```

### SDO refreshed and metadata is missing

Run `./scripts/refresh-sdo.sh re-crm-sdo` to redeploy from source.

### Lost metadata changes made in Setup UI

Not recoverable. This is why `CLAUDE.md` mandates: don't make changes in Setup UI that aren't reflected in source. Next time, retrieve immediately after any Setup UI change.
