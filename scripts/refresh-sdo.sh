#!/usr/bin/env bash
# Rebuilds a freshly refreshed SDO from source.
# Use this after Salesforce refreshes your SDO, or on a brand-new SDO.
# Usage: ./scripts/refresh-sdo.sh [org-alias]

set -euo pipefail

ORG_ALIAS="${1:-re-crm-sdo}"

echo "================================================="
echo "  Rebuilding SDO: $ORG_ALIAS"
echo "================================================="

# 1. Authenticate if needed
if ! sf org display --target-org "$ORG_ALIAS" > /dev/null 2>&1; then
  echo ""
  echo "Org not authenticated. Opening login..."
  sf org login web --alias "$ORG_ALIAS"
fi

# 2. Reproduce any manual Setup steps (one-time features that can't be in source)
echo ""
echo "REMINDER: Check docs/manual-setup-steps.md for any click-trail"
echo "steps that must be performed in Setup before deploying."
read -p "Have you completed all manual Setup steps? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
  echo "Aborted. Complete the manual steps first."
  exit 0
fi

# 3. Deploy all metadata
echo ""
echo "Deploying metadata..."
./scripts/deploy.sh "$ORG_ALIAS"

# 4. Seed demo data
echo ""
echo "Seeding demo data..."
./scripts/seed-demo-data.sh "$ORG_ALIAS" || echo "  (seed may fail if data model isn't deployed yet — continue)"

echo ""
echo "================================================="
echo "  SDO rebuild complete."
echo "================================================="
