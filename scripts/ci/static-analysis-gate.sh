#!/usr/bin/env bash
# Enforces the static analysis gates using the exit codes recorded by
# static-analysis.sh. Runs AFTER the report upload so evidence always survives.
#
# Gates (as specified):
#   - Checkstyle violations exist            -> fail
#   - PMD violations exceed threshold        -> fail (threshold = priority <= 3)
#   - SpotBugs High priority issues exist    -> fail
set -uo pipefail

REPORT_DIR="reports/static-analysis"
FAILED=0

check() {
  local name="$1"
  local file="${REPORT_DIR}/${name}.exit"

  if [ ! -f "$file" ]; then
    echo "::error::${name} produced no result file — the analysis stage did not run correctly."
    FAILED=1
    return
  fi

  local code
  code="$(cat "$file")"
  if [ "$code" != "0" ]; then
    echo "::error::${name} gate FAILED (exit ${code}). See the ${name} report in the static-analysis-reports artifact."
    FAILED=1
  else
    echo "${name} gate passed."
  fi
}

check checkstyle
check pmd
check cpd
check spotbugs

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "Static analysis gate failed. Fix the reported violations."
  echo "Do NOT relax config/checkstyle/checkstyle.xml, config/pmd/ruleset.xml or"
  echo "the SpotBugs threshold to make this pass — those thresholds are the contract."
  exit 1
fi

echo "All static analysis gates passed."
