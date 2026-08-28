#!/usr/bin/env bash
# Gate: ANY detected secret fails the pipeline.
set -uo pipefail

REPORT_DIR="reports/security/gitleaks"
EXIT_FILE="${REPORT_DIR}/gitleaks.exit"
REPORT="${REPORT_DIR}/gitleaks-report.json"

if [ ! -f "$EXIT_FILE" ]; then
  echo "::error::Gitleaks produced no result file — the scan did not run correctly."
  exit 1
fi

if [ -f "$REPORT" ]; then
  # The report is a JSON array; "[]" means no findings.
  COUNT=$(grep -o '"RuleID"' "$REPORT" | wc -l | tr -d ' ')
  echo "Gitleaks findings: ${COUNT}"
fi

CODE="$(cat "$EXIT_FILE")"
if [ "$CODE" != "0" ]; then
  echo "::error::Secret scan FAILED — gitleaks detected credentials in the repository."
  echo "Rotate every exposed credential FIRST (it is compromised the moment it is committed),"
  echo "then remove it from the working tree and history. Do not add it to .gitleaks.toml"
  echo "unless it is a genuine false positive."
  exit 1
fi

echo "Secret scan passed: no secrets detected."
