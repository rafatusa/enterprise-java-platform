#!/usr/bin/env bash
# Runs unit tests (JUnit 5 + Mockito), Spring Boot integration tests and
# REST Assured API tests, then produces the JaCoCo report.
#
# Always exits 0 and always collects reports; the coverage VERDICT is enforced by
# the `mvn jacoco:check` step that runs after the artifact upload.
set -uo pipefail

REPORT_DIR="reports/tests"
mkdir -p "$REPORT_DIR"

echo "::group::Unit + integration tests"
# `verify` runs surefire (unit), failsafe (IT) and the JaCoCo merge+report.
mvn -B -ntp verify
TEST_EXIT=$?
echo "$TEST_EXIT" > "$REPORT_DIR/tests.exit"
echo "::endgroup::"

for d in surefire-reports failsafe-reports; do
  if [ -d "target/$d" ]; then
    mkdir -p "$REPORT_DIR/$d"
    cp -r "target/$d/." "$REPORT_DIR/$d/" 2>/dev/null || true
  fi
done

if [ -d target/site/jacoco ]; then
  mkdir -p "$REPORT_DIR/jacoco"
  cp -r target/site/jacoco/. "$REPORT_DIR/jacoco/" 2>/dev/null || true
fi

if [ "$TEST_EXIT" -ne 0 ]; then
  echo "::error::Tests failed (exit ${TEST_EXIT}). Reports are in the jacoco-and-test-reports artifact."
  # Tests failing IS a hard failure — but report collection above already ran.
  exit "$TEST_EXIT"
fi

echo "Tests passed. Coverage thresholds are enforced by the jacoco:check step."
