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
# gate even when the verdict is right. If the score cannot be determined, say so
# explicitly rather than printing a fabricated 0.
set -uo pipefail

REPORT_DIR="reports/pit"
EXIT_FILE="${REPORT_DIR}/pit.exit"
SUMMARY_FILE="${REPORT_DIR}/pit-summary.txt"
XML="${REPORT_DIR}/mutations.xml"

report_score() {
  # Preferred: PIT's own summary line, e.g.
  #   >> Generated 34 mutations Killed 31 (91%)
  if [ -f "$SUMMARY_FILE" ] && [ -s "$SUMMARY_FILE" ]; then
    local line total killed pct
    line="$(cat "$SUMMARY_FILE")"
    total="$(sed -E 's/.*Generated ([0-9]+) mutations.*/\1/' <<<"$line")"
    killed="$(sed -E 's/.*Killed ([0-9]+).*/\1/' <<<"$line")"
    pct="$(sed -E 's/.*\(([0-9]+)%\).*/\1/' <<<"$line")"
    if [ -n "$pct" ]; then
      echo "Mutation score: ${pct}% (${killed}/${total} mutants killed, threshold 70%)"
      return 0
    fi
  fi

  # Fallback: count from mutations.xml. PIT writes status as an attribute; match
  # either quoting style and any attribute order.
  if [ -f "$XML" ]; then
    local killed total
    killed="$(grep -o "status=['\"]KILLED['\"]" "$XML" | wc -l | tr -d ' ')"
    total="$(grep -c '<mutation' "$XML" | tr -d ' ')"
    if [ "${total:-0}" -gt 0 ]; then
      awk -v k="$killed" -v t="$total" \
        'BEGIN { printf "Mutation score: %.1f%% (%d/%d mutants killed, threshold 70%%)\n", (k/t)*100, k, t }'
      return 0
    fi
  fi

  echo "::warning::Could not determine the mutation score from PIT output; the verdict below comes from PIT's own threshold check."
  return 0
}

report_score

if [ ! -f "$EXIT_FILE" ]; then
  echo "::error::PIT produced no result file — the mutation stage did not run correctly."
  exit 1
fi

CODE="$(cat "$EXIT_FILE")"
if [ "$CODE" != "0" ]; then
  echo "::error::Mutation gate FAILED — score is below the 70% threshold set in pom.xml."
  echo "Write tests that kill the surviving mutants; do not lower pit.mutation.threshold."
  echo "Open reports/pit/index.html (pit-mutation-report artifact) and look for SURVIVED."
  exit 1
fi

echo "Mutation gate passed."
