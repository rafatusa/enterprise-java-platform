#!/usr/bin/env bash
# Semgrep SAST scan.
#
# Contract (see README "report-then-gate"): this script ALWAYS exits 0 and
# records the real verdict in reports/security/semgrep/semgrep.exit. The
# artifact upload therefore always runs, and semgrep-gate.sh turns the recorded
# status into the build verdict.
#
# CRITICAL DISTINCTION: "semgrep found a vulnerability" and "semgrep failed to
# run" must NOT look the same. Semgrep's own exit codes conflate them (any
# non-zero), so this script separates them explicitly:
#   semgrep.exit    -> 0 clean, 1 findings
#   semgrep.status  -> ok | tool-error
# A tool error still fails the gate (a security scan that did not run is not a
# pass), but it says so in those words instead of reporting phantom findings.
set -uo pipefail

REPORT_DIR="reports/security/semgrep"
mkdir -p "$REPORT_DIR"

fail_tool() {
  echo "::warning::Semgrep could not run: $1"
  echo "1" > "${REPORT_DIR}/semgrep.exit"
  echo "tool-error" > "${REPORT_DIR}/semgrep.status"
  echo "$1" > "${REPORT_DIR}/semgrep.error"
  exit 0
}

echo "::group::Install semgrep"
if ! python3 -m pip install --quiet --disable-pip-version-check semgrep; then
  echo "::endgroup::"
  fail_tool "pip install semgrep failed (see the install log above)."
fi

if ! command -v semgrep >/dev/null 2>&1; then
  echo "::endgroup::"
  fail_tool "semgrep is not on PATH after installation."
fi

semgrep --version
echo "::endgroup::"

SEMGREP_ARGS=(
  --config=p/java
  --config=p/security-audit
  --config=p/owasp-top-ten
  --config=p/secrets
  --severity=ERROR
  --metrics=off
)

# JSON first: it is both the artifact and the input the gate prints findings
# from, so if only one pass can succeed it must be this one.
echo "::group::Semgrep SAST (ERROR severity)"
semgrep scan "${SEMGREP_ARGS[@]}" \
  --json --output "${REPORT_DIR}/semgrep-report.json" .
STATUS=$?

# Exit 0 = clean, 1 = findings. Anything else is a tool/config/network failure
# (2 = fatal error, 7 = rule fetch failure), which is NOT a finding.
if [ "$STATUS" -gt 1 ]; then
  echo "::endgroup::"
  fail_tool "semgrep scan exited ${STATUS} (rule download or fatal error, not a code finding)."
fi

if [ ! -s "${REPORT_DIR}/semgrep-report.json" ]; then
  echo "::endgroup::"
  fail_tool "semgrep produced no JSON report; the scan did not complete."
fi

# Human-readable pass for the log, and SARIF for the artifact.
semgrep scan "${SEMGREP_ARGS[@]}" --text . || true
semgrep scan "${SEMGREP_ARGS[@]}" \
  --sarif --output "${REPORT_DIR}/semgrep-report.sarif" . >/dev/null 2>&1 || true
echo "::endgroup::"

echo "$STATUS" > "${REPORT_DIR}/semgrep.exit"
echo "ok" > "${REPORT_DIR}/semgrep.status"

if [ "$STATUS" -ne 0 ]; then
  echo "Semgrep found ERROR-severity issues; the gate step will fail the build."
else
  echo "Semgrep: no ERROR-severity findings."
fi

exit 0
