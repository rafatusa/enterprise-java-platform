#!/usr/bin/env bash
# Runs the k6 benchmark. Always collects the HTML/JSON reports; the threshold
# verdict is enforced by k6-gate.sh after the artifact upload.
set -uo pipefail

mkdir -p reports/performance

echo "Running k6 against ${BASE_URL}"
echo "Profile: ramp 2m -> 200 VUs, hold 15m, ramp-down 1m"

k6 run \
  --summary-export=reports/performance/k6-metrics.json \
  perf/load-test.js
echo "$?" > reports/performance/k6.exit

exit 0
