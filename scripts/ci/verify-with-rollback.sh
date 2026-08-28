#!/usr/bin/env bash
# Health verification with automatic rollback.
#
# The pipeline spec supports no `if: failure()` step, so rollback is owned HERE:
# this script runs the full deployment validation suite and, if it fails, invokes
# the rollback playbook to restore the previous release before exiting non-zero.
# That is more robust than a CI conditional — the rollback decision lives with
# the check that makes it, and cannot be skipped by a cancelled job step.
set -uo pipefail

: "${TARGET_HOST:?TARGET_HOST must be set}"
: "${SSH_USER:?SSH_USER must be set}"

BASE_URL="http://${TARGET_HOST}"
mkdir -p reports/deployment

echo "=========================================================="
echo "Deployment validation for ${BASE_URL}"
echo "=========================================================="

# Give the freshly (re)started service time to bind before judging it.
echo "Waiting for the application to accept connections..."
curl --fail --silent --output /dev/null \
  --retry 20 --retry-delay 15 --retry-all-errors --max-time 20 \
  "${BASE_URL}/actuator/health" || true

if bash scripts/smoke-test.sh "$BASE_URL"; then
  echo ""
  echo "VERIFICATION PASSED — the deployment is healthy."
  exit 0
fi

# ---------------------------------------------------------------------------
# Verification failed: roll back to the previous release.
# ---------------------------------------------------------------------------
echo ""
echo "::error::VERIFICATION FAILED — rolling back to the previous release."

{
  echo ""
  echo "## Rollback"
  echo ""
  echo "- Triggered at: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "- Reason: deployment validation failed (see the table above)."
} >> reports/deployment/deployment-summary.md

if [ ! -f ~/.ssh/deploy_key ]; then
  echo "::error::No SSH key available — cannot roll back automatically."
  echo "- Result: ROLLBACK NOT ATTEMPTED (no SSH key)." >> reports/deployment/deployment-summary.md
  exit 1
fi

if ~/.local/bin/ansible-playbook \
  -i "${TARGET_HOST}," \
  -u "$SSH_USER" \
  --private-key ~/.ssh/deploy_key \
  ansible/rollback.yml; then

  echo "Rollback completed. Re-checking health of the restored release..."

  if curl --fail --silent --output /dev/null \
      --retry 12 --retry-delay 10 --retry-all-errors --max-time 20 \
      "${BASE_URL}/actuator/health"; then
    echo "::warning::Rolled back successfully — the PREVIOUS release is live and healthy."
    echo "- Result: ROLLED BACK — previous release restored and healthy." \
      >> reports/deployment/deployment-summary.md
  else
    echo "::error::Rollback ran but the restored release is still unhealthy — MANUAL INTERVENTION REQUIRED."
    echo "- Result: ROLLBACK COMPLETED BUT HOST STILL UNHEALTHY — manual intervention required." \
      >> reports/deployment/deployment-summary.md
  fi
else
  echo "::error::Rollback playbook FAILED — the host is in an indeterminate state. MANUAL INTERVENTION REQUIRED."
  echo "- Result: ROLLBACK FAILED — manual intervention required." \
    >> reports/deployment/deployment-summary.md
fi

# The deploy failed regardless of how the rollback went; never report success.
exit 1
