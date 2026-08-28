#!/usr/bin/env bash
# Gate: any ERROR-severity (critical) SAST finding fails the pipeline.
#
# This step is the one that goes red, so it must be self-explanatory: it prints
# every finding (rule, file:line, message) rather than pointing at an artifact.
# A reviewer should never have to download a SARIF file to learn WHAT broke.
#
# It distinguishes the two ways a SAST stage can fail:
#   findings    -> real vulnerabilities in this repository; fix the code.
#   tool-error  -> the scanner never ran; fix the runner, not the code.
# Both fail the build (an unrun security scan is not a pass), but conflating
# them sends people hunting for a vulnerability that does not exist.
set -uo pipefail

REPORT_DIR="reports/security/semgrep"
EXIT_FILE="${REPORT_DIR}/semgrep.exit"
STATUS_FILE="${REPORT_DIR}/semgrep.status"
ERROR_FILE="${REPORT_DIR}/semgrep.error"
JSON_REPORT="${REPORT_DIR}/semgrep-report.json"

if [ ! -f "$EXIT_FILE" ]; then
  echo "::error::Semgrep produced no result file — the scan did not run correctly."
  exit 1
fi

STATUS="tool-error"
[ -f "$STATUS_FILE" ] && STATUS="$(cat "$STATUS_FILE")"

if [ "$STATUS" = "tool-error" ]; then
  echo "::error::SAST gate FAILED — the Semgrep scanner could not run."
  echo ""
  if [ -f "$ERROR_FILE" ]; then
    echo "Reason: $(cat "$ERROR_FILE")"
  fi
  echo ""
  echo "This is NOT a code finding — no vulnerability was reported. The scan"
  echo "itself failed to execute, so the code is UNVERIFIED."
  echo ""
  echo "Usual causes: no network access to semgrep.dev for the rule packs (p/java,"
  echo "p/security-audit, p/owasp-top-ten, p/secrets), a pip/PyPI outage, or a"
  echo "Python version semgrep does not support on this runner."
  exit 1
fi

CODE="$(cat "$EXIT_FILE")"
if [ "$CODE" = "0" ]; then
  echo "SAST gate passed: no ERROR-severity findings."
  exit 0
fi

echo "::error::SAST gate FAILED — Semgrep reported ERROR-severity findings."
echo ""

if [ -f "$JSON_REPORT" ]; then
  echo "Findings:"
  python3 - "$JSON_REPORT" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)

results = report.get("results", [])
for item in results:
    start = item.get("start", {})
    extra = item.get("extra", {})
    print(f"  [{extra.get('severity', 'ERROR')}] {item.get('check_id', '<unknown rule>')}")
    print(f"    {item.get('path', '?')}:{start.get('line', '?')}")
    message = " ".join((extra.get("message") or "").split())
    if message:
        print(f"    {message}")
    line = (extra.get("lines") or "").strip()
    if line:
        print(f"    > {line}")
    print("")

print(f"Total ERROR-severity findings: {len(results)}")
PY
else
  echo "No JSON report found at ${JSON_REPORT} — see the scan step's log output."
fi

echo ""
echo "Full report: reports/security/semgrep/semgrep-report.sarif (semgrep-report artifact)."
echo "Fix the finding, or add a narrowly-scoped '# nosemgrep: <rule-id>' with a justification comment."
exit 1
