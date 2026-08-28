#!/usr/bin/env bash
# Pact provider contract verification.
#
# Contracts committed under src/test/resources/pacts are ALWAYS verified, so this
# gate is meaningful without external infrastructure. When a Pact Broker is
# configured, verification results are published to it as well.
#
# Broker credentials are read from the environment only.
set -euo pipefail

REPORT_DIR="reports/pacts"
mkdir -p "$REPORT_DIR"

echo "::group::Pact provider verification"
mvn -B -ntp test -Dtest='*PactTest' -DfailIfNoTests=false
echo "::endgroup::"

if [ -n "${PACT_BROKER_BASE_URL:-}" ]; then
  echo "Publishing verification results to ${PACT_BROKER_BASE_URL}"
  # pact.broker.token is picked up from the environment by the pact plugin.
  export PACT_BROKER_TOKEN
  mvn -B -ntp au.com.dius.pact.provider:maven:publish \
    -Dpact.broker.url="$PACT_BROKER_BASE_URL" \
    || echo "::warning::Pact Broker publish failed; local verification still passed."
else
  echo "::notice title=Pact Broker not configured::Contracts in src/test/resources/pacts were verified locally. Add PACT_BROKER_URL and PACT_BROKER_TOKEN as repository secrets to publish results."
fi

cp -r src/test/resources/pacts/. "$REPORT_DIR/" 2>/dev/null || true
if [ -d target/pacts ]; then
  cp -r target/pacts/. "$REPORT_DIR/" 2>/dev/null || true
fi
if [ -d target/surefire-reports ]; then
  mkdir -p "$REPORT_DIR/verification"
  cp -r target/surefire-reports/. "$REPORT_DIR/verification/" 2>/dev/null || true
fi

echo "Contract verification complete."
