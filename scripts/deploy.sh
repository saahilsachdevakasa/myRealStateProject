#!/usr/bin/env bash
# Deploys all metadata from force-app/ to the target SDO.
# Runs a validation deploy first; on success, runs the real deploy.
# Usage: ./scripts/deploy.sh [org-alias] [--skip-validate]

set -euo pipefail

ORG_ALIAS="${1:-re-crm-sdo}"
SKIP_VALIDATE=false
for arg in "$@"; do
  if [ "$arg" = "--skip-validate" ]; then
    SKIP_VALIDATE=true
  fi
done

echo "================================================="
echo "  Deploying to: $ORG_ALIAS"
echo "================================================="

# Sanity: confirm the org is authenticated
if ! sf org display --target-org "$ORG_ALIAS" > /dev/null 2>&1; then
  echo "ERROR: org '$ORG_ALIAS' not authenticated."
  echo "Run:  sf org login web --alias $ORG_ALIAS"
  exit 1
fi

# Validation deploy (dry run)
if [ "$SKIP_VALIDATE" = false ]; then
  echo ""
  echo "Running validation deploy (dry run)..."
  sf project deploy validate \
    --source-dir force-app \
    --target-org "$ORG_ALIAS" \
    --wait 20 \
    --test-level RunLocalTests
  echo ""
  echo "Validation passed. Proceeding to real deploy."
fi

# Real deploy
echo ""
echo "Deploying..."
sf project deploy start \
  --source-dir force-app \
  --target-org "$ORG_ALIAS" \
  --wait 20 \
  --test-level RunLocalTests

echo ""
echo "================================================="
echo "  Deploy complete."
echo "  Open:   sf org open -o $ORG_ALIAS"
echo "  Seed:   ./scripts/seed-demo-data.sh $ORG_ALIAS"
echo "================================================="
