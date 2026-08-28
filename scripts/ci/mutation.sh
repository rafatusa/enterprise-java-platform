#!/usr/bin/env bash
# Runs PIT mutation testing and collects the report. The 70% threshold verdict
# is enforced by mutation-gate.sh after the report upload.
#
# PIT's own <mutationThreshold> in pom.xml is what actually fails the build, so
# the recorded exit code is the authoritative verdict. The score is captured here
# from PIT's printed statistics — the line PIT itself computes — rather than
# re-derived by counting XML elements, which silently reported 0% when the
# element/attribute layout did not match the pattern.
set -uo pipefail

REPORT_DIR="reports/pit"
mkdir -p "$REPORT_DIR"
LOG="${REPORT_DIR}/pit-output.log"

echo "::group::PIT mutation testing"
mvn -B -ntp test-compile org.pitest:pitest-maven:mutationCoverage 2>&1 | tee "$LOG"
# With pipefail the pipeline status is mvn's, not tee's.
PIT_STATUS=${PIPESTATUS[0]}
echo "$PIT_STATUS" > "$REPORT_DIR/pit.exit"
echo "::endgroup::"

# PIT prints: ">> Generated 34 mutations Killed 31 (91%)"
SUMMARY="$(grep -E '^>> Generated [0-9]+ mutations Killed [0-9]+' "$LOG" | tail -1 || true)"
if [ -n "$SUMMARY" ]; then
  echo "$SUMMARY" > "$REPORT_DIR/pit-summary.txt"
fi

if [ -d target/pit-reports ]; then
  cp -r target/pit-reports/. "$REPORT_DIR/" 2>/dev/null || true
fi

exit 0
