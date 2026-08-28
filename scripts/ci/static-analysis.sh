#!/usr/bin/env bash
# Runs Checkstyle, PMD, CPD and SpotBugs and ALWAYS collects their reports.
#
# Why this never fails: the pipeline spec has no `if:` on steps, so a failure
# here would skip the artifact upload and hide the very report that explains the
# failure. The verdict is enforced by static-analysis-gate.sh, which runs AFTER
# the upload. Exit codes are recorded to disk for the gate to read.
#
# Tool output is NOT swallowed: each tool runs with consoleOutput/printFailingErrors
# so the violations appear in the CI log itself. An artifact you have to download
# to learn what broke is a slower feedback loop than a log you are already reading.
set -uo pipefail

REPORT_DIR="reports/static-analysis"
mkdir -p "$REPORT_DIR"

run_and_record() {
  local name="$1"
  shift
  echo "::group::${name}"
  "$@"
  local code=$?
  echo "$code" > "${REPORT_DIR}/${name}.exit"
  echo "${name} exit=${code}"
  echo "::endgroup::"
}

run_and_record checkstyle mvn -B -ntp checkstyle:check
run_and_record pmd        mvn -B -ntp pmd:check
run_and_record cpd        mvn -B -ntp pmd:cpd-check
run_and_record spotbugs   mvn -B -ntp compile spotbugs:check

# Collect whatever each tool produced; missing files are not fatal here.
for f in target/checkstyle-result.xml target/pmd.xml target/cpd.xml target/spotbugsXml.xml; do
  [ -f "$f" ] && cp "$f" "$REPORT_DIR/" || true
done

if [ -d target/site ]; then
  mkdir -p "$REPORT_DIR/site"
  cp -r target/site/. "$REPORT_DIR/site/" 2>/dev/null || true
fi

# Echo the findings into the log so the failure is diagnosable without
# downloading the artifact.
if [ -f target/checkstyle-result.xml ]; then
  echo "::group::Checkstyle violations"
  grep -o 'severity="[a-z]*" message="[^"]*"' target/checkstyle-result.xml | head -50 || true
  echo "::endgroup::"
fi

if [ -f target/pmd.xml ]; then
  echo "::group::PMD violations"
  grep -o 'priority="[0-9]"[^>]*>[^<]*' target/pmd.xml | head -50 || true
  echo "::endgroup::"
fi

echo "Static analysis reports collected in ${REPORT_DIR}"
exit 0
