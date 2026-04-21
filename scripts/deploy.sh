#!/usr/bin/env bash
# Deploys all metadata from force-app/ to the target SDO.
# Runs a validation deploy first; on success, runs the real deploy.
# Usage: ./scripts/deploy.sh [org-alias] [--skip-validate] [--test-level <LEVEL>]
#   --test-level values: NoTestRun | RunLocalTests | RunAllTestsInOrg | RunSpecifiedTests
#   Default: NoTestRun (metadata-only deploys; revisit when Apex lands in E06/E07).

set -euo pipefail

ORG_ALIAS="${1:-re-crm-sdo}"
SKIP_VALIDATE=false
TEST_LEVEL="NoTestRun"

# Skip the first positional arg (org alias) when parsing flags
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-validate)
      SKIP_VALIDATE=true
      shift
      ;;
    --test-level)
      if [ -z "${2:-}" ]; then
        echo "ERROR: --test-level requires a value (NoTestRun | RunLocalTests | RunAllTestsInOrg | RunSpecifiedTests)"
        exit 1
      fi
      TEST_LEVEL="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument '$1'"
      echo "Usage: ./scripts/deploy.sh [org-alias] [--skip-validate] [--test-level <LEVEL>]"
      exit 1
      ;;
  esac
done

echo "================================================="
echo "  Deploying to: $ORG_ALIAS"
echo "  Test level:   $TEST_LEVEL"
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
    --test-level "$TEST_LEVEL"
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
  --test-level "$TEST_LEVEL"

echo ""
echo "================================================="
echo "  Deploy complete."
echo "  Open:   sf org open -o $ORG_ALIAS"
echo "  Seed:   ./scripts/seed-demo-data.sh $ORG_ALIAS"
echo "================================================="
