#!/usr/bin/env bash
# Loads pre-built demo data into the target SDO using sf data import tree.
# Tree-based import supports external-ID lookups natively.
# Usage: ./scripts/seed-demo-data.sh [org-alias]

set -euo pipefail

ORG_ALIAS="${1:-re-crm-sdo}"
PLAN_FILE="data/plan.json"

echo "================================================="
echo "  Seeding demo data to: $ORG_ALIAS"
echo "================================================="

if ! sf org display --target-org "$ORG_ALIAS" > /dev/null 2>&1; then
  echo "ERROR: org '$ORG_ALIAS' not authenticated."
  exit 1
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "ERROR: plan file not found at $PLAN_FILE"
  echo "Plan file is generated after E02 deploys the data model."
  echo "Create it by running: python3 data/generate_plan.py"
  exit 1
fi

# Tree-based import: one command, resolves external-ID lookups in order
echo ""
echo "Importing via tree plan..."
sf data import tree \
  --plan "$PLAN_FILE" \
  --target-org "$ORG_ALIAS"

echo ""
echo "================================================="
echo "  Seed complete."
echo "  Verify: sf data query --query 'SELECT COUNT() FROM Unit__c' -o $ORG_ALIAS"
echo "================================================="
