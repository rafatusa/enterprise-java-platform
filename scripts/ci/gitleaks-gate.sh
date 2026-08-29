#!/usr/bin/env bash
# Gate: ANY detected secret fails the pipeline.
#
# Three distinct states, because they need different actions:
#   passed      -> nothing to do
#   findings    -> a credential is in the tree; ROTATE it, then remove it
#   tool-error  -> the scanner never ran; fix the runner, NOT the code
# tool-error still fails the build: unscanned code is unverified, not approved.
#
# The findings are PRINTED here (file, line, rule). gitleaks runs with --redact,
# so the values are already "REDACTED" in the report — naming the location leaks
# nothing and is the difference between a fixable failure and a mystery.
set -uo pipefail

REPORT_DIR="reports/security/gitleaks"
EXIT_FILE="${REPORT_DIR}/gitleaks.exit"
STATUS_FILE="${REPORT_DIR}/status"
REPORT="${REPORT_DIR}/gitleaks-report.json"

if [ ! -f "$EXIT_FILE" ] || [ ! -f "$STATUS_FILE" ]; then
  echo "::error::Gitleaks produced no result files — the scan did not run at all."
  echo "This is a RUNNER problem, not a detected secret. Check the install step above."
  exit 1
fi

if [ "$(cat "$STATUS_FILE")" = "tool-error" ]; then
  echo "::error::Secret scan gate FAILED — the scanner could not run."
  [ -f "${REPORT_DIR}/error" ] && cat "${REPORT_DIR}/error"
  echo "This is NOT a detected secret. Nothing was scanned, so the tree is UNVERIFIED."
  exit 1
fi

if [ -f "$REPORT" ]; then
  COUNT=$(grep -o '"RuleID"' "$REPORT" | wc -l | tr -d ' ')
  echo "Gitleaks findings: ${COUNT}"

  if [ "${COUNT:-0}" -gt 0 ]; then
    echo ""
    echo "::group::Detected secrets (values redacted)"
    python3 - "$REPORT" <<'PY' || true
import json
import sys

try:
    with open(sys.argv[1]) as handle:
        findings = json.load(handle)
except (OSError, ValueError) as exc:
    print(f"could not parse the gitleaks report: {exc}")
    sys.exit(0)

for item in findings or []:
    path = item.get("File", "?")
    line = item.get("StartLine", "?")
    rule = item.get("RuleID", "?")
    desc = (item.get("Description") or "").strip()
    print(f"{path}:{line}  [{rule}]  {desc}")
PY
    echo "::endgroup::"
  fi
fi

CODE="$(cat "$EXIT_FILE")"
if [ "$CODE" != "0" ]; then
  echo "::error::Secret scan FAILED — gitleaks detected credentials in the repository."
  echo "Rotate every exposed credential FIRST (it is compromised the moment it is committed),"
  echo "then remove it from the working tree and history. Do not add it to .gitleaks.toml"
  echo "unless it is a genuine false positive — and if it is, say WHY in a comment."
  exit 1
fi

echo "Secret scan passed: no secrets detected."
