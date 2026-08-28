#!/usr/bin/env bash
# Runs PIT mutation testing and collects the report. The 70% threshold verdict
# is enforced by mutation-gate.sh after the report upload.
set -uo pipefail

REPORT_DIR="reports/pit"
mkdir -p "$REPORT_DIR"

echo "::group::PIT mutation testing"
mvn -B -ntp test-compile org.pitest:pitest-maven:mutationCoverage
echo "$?" > "$REPORT_DIR/pit.exit"
echo "::endgroup::"

if [ -d target/pit-reports ]; then
  cp -r target/pit-reports/. "$REPORT_DIR/" 2>/dev/null || true
fi

exit 0
