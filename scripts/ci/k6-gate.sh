#!/usr/bin/env bash
# Gate: p95 latency < 400 ms and error rate < 1%.
#
# k6 exits non-zero when a configured threshold is breached, so its exit code is
# the authoritative verdict. The summary is parsed to print the actual numbers,
# because "the benchmark failed" without the measurement is not actionable.
set -uo pipefail

SUMMARY="reports/performance/k6-summary.json"
EXIT_FILE="reports/performance/k6.exit"

if [ -f "$SUMMARY" ]; then
  echo "=== Benchmark results ==="
  cat "$SUMMARY"
  echo ""
fi

if [ ! -f "$EXIT_FILE" ]; then
  echo "::error::k6 produced no result file — the performance stage did not run correctly."
  exit 1
fi

CODE="$(cat "$EXIT_FILE")"
if [ "$CODE" != "0" ]; then
  echo "::error::Performance gate FAILED — p95 latency exceeded 400 ms and/or the error rate exceeded 1%."
  echo "Open k6-summary.html in the k6-performance-report artifact for the per-endpoint breakdown."
  echo "Common causes at 200 VUs: undersized instance (CPU credit exhaustion),"
  echo "an undersized Hikari pool, or a missing database index."
  exit 1
fi

echo "Performance gate passed: p95 < 400 ms and error rate < 1%."
