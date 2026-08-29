#!/usr/bin/env bash
# Enforces the mutation-score gate (>= 70%).
#
# PIT itself fails the build when mutationThreshold is not met (configured in
# pom.xml), so the recorded exit code is the AUTHORITATIVE verdict. The score is
# reported here purely so the log states the number the verdict is based on.
#
# The score is read from PIT's own printed statistics, captured by mutation.sh.
# A previous version counted 'status="KILLED"' occurrences in mutations.xml and
# printed "Mutation score: 0.0% ... Mutation gate passed." when PIT had actually
# killed 31/34 — a number that contradicts its own verdict destroys trust in the
# gate even when the verdict is right.
#
# THREE states, as everywhere else in this pipeline:
#   passed      -> score met the threshold
#   findings    -> genuine surviving mutants; write tests
#   tool-error  -> PIT never completed a run; fix the toolchain, NOT the tests
set -uo pipefail

REPORT_DIR="reports/pit"
EXIT_FILE="${REPORT_DIR}/pit.exit"
STATUS_FILE="${REPORT_DIR}/status"
SUMMARY_FILE="${REPORT_DIR}/pit-summary.txt"

if [ ! -f "$EXIT_FILE" ]; then
  echo "::error::PIT produced no result file — the mutation stage did not run correctly."
  exit 1
fi

# A run that never produced statistics is a toolchain failure, not a low score.
if [ -f "$STATUS_FILE" ] && [ "$(cat "$STATUS_FILE")" = "tool-error" ]; then
  echo "::error::Mutation gate FAILED — PIT did not complete a mutation run."
  [ -f "${REPORT_DIR}/error" ] && cat "${REPORT_DIR}/error"
  echo "This is NOT a low mutation score — no score was produced, so the code is"
  echo "UNVERIFIED by mutation testing. Check the 'PIT failure output' group above:"
  echo "a PIT/pitest-junit5-plugin version that predates the project's JUnit"
  echo "Platform is the usual cause. Do NOT lower pit.mutation.threshold."
  exit 1
fi

if [ -f "$SUMMARY_FILE" ] && [ -s "$SUMMARY_FILE" ]; then
  line="$(cat "$SUMMARY_FILE")"
  total="$(sed -E 's/.*Generated ([0-9]+) mutations.*/\1/' <<<"$line")"
  killed="$(sed -E 's/.*Killed ([0-9]+).*/\1/' <<<"$line")"
  pct="$(sed -E 's/.*\(([0-9]+)%\).*/\1/' <<<"$line")"
  if [ -n "$pct" ]; then
    echo "Mutation score: ${pct}% (${killed}/${total} mutants killed, threshold 70%)"
  fi
fi

CODE="$(cat "$EXIT_FILE")"
if [ "$CODE" != "0" ]; then
  echo "::error::Mutation gate FAILED — score is below the 70% threshold set in pom.xml."
  echo "Write tests that kill the surviving mutants; do not lower pit.mutation.threshold."
  echo "Open reports/pit/index.html (pit-mutation-report artifact) and look for SURVIVED."
  exit 1
fi

echo "Mutation gate passed."
