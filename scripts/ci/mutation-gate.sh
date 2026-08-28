#!/usr/bin/env bash
# Enforces the mutation-score gate (>= 70%).
#
# PIT itself fails the build when mutationThreshold is not met (configured in
# pom.xml), so the recorded exit code is the authoritative verdict. The score is
# additionally parsed from mutations.xml purely to print a useful number.
set -uo pipefail

REPORT_DIR="reports/pit"
EXIT_FILE="${REPORT_DIR}/pit.exit"
XML="${REPORT_DIR}/mutations.xml"

if [ -f "$XML" ]; then
  KILLED=$(grep -c 'status="KILLED"' "$XML" || true)
  TOTAL=$(grep -c '<mutation ' "$XML" || true)
  if [ "${TOTAL:-0}" -gt 0 ]; then
    SCORE=$(awk "BEGIN { printf \"%.1f\", ($KILLED / $TOTAL) * 100 }")
    echo "Mutation score: ${SCORE}% (${KILLED}/${TOTAL} mutants killed, threshold 70%)"
  fi
else
  echo "::warning::mutations.xml not found — relying on the PIT plugin exit code."
fi

if [ ! -f "$EXIT_FILE" ]; then
  echo "::error::PIT produced no result file — the mutation stage did not run correctly."
  exit 1
fi

CODE="$(cat "$EXIT_FILE")"
if [ "$CODE" != "0" ]; then
  echo "::error::Mutation gate FAILED — score is below the 70% threshold set in pom.xml."
  echo "Write tests that kill the surviving mutants; do not lower pit.mutation.threshold."
  exit 1
fi

echo "Mutation gate passed."
