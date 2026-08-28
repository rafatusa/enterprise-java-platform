#!/usr/bin/env bash
# OWASP Dependency Check + CycloneDX SBOM + Trivy filesystem scan.
# Always collects reports; the verdict is dependency-scan-gate.sh.
set -uo pipefail

TRIVY_VERSION="0.58.2"
REPORT_DIR="reports/security"
mkdir -p "$REPORT_DIR/owasp" "$REPORT_DIR/sbom" "$REPORT_DIR/trivy-fs"

# --- OWASP Dependency Check (fails at CVSS >= 7 per pom.xml) ---
# The NVD credential is read from the environment by the plugin
# (dependency-check reads nvd.api.key from NVD_API_KEY), so it is never passed
# on the command line.
echo "::group::OWASP Dependency Check"
if [ -n "${NVD_API_KEY:-}" ]; then
  export NVD_API_KEY
  mvn -B -ntp org.owasp:dependency-check-maven:check
else
  echo "::warning::NVD_API_KEY is not configured — the NVD feed is heavily rate-limited without one and this step will be slow. Request a free key at https://nvd.nist.gov/developers/request-an-api-key"
  mvn -B -ntp org.owasp:dependency-check-maven:check
fi
echo "$?" > "$REPORT_DIR/owasp/owasp.exit"
echo "::endgroup::"

for f in target/dependency-check-report.html target/dependency-check-report.json; do
  [ -f "$f" ] && cp "$f" "$REPORT_DIR/owasp/" || true
done

# --- CycloneDX SBOM ---
echo "::group::CycloneDX SBOM"
mvn -B -ntp cyclonedx:makeAggregateBom
echo "$?" > "$REPORT_DIR/sbom/sbom.exit"
echo "::endgroup::"

for f in target/bom.xml target/bom.json; do
  [ -f "$f" ] && cp "$f" "$REPORT_DIR/sbom/" || true
done

# --- Trivy filesystem scan ---
echo "::group::Trivy filesystem scan"
curl -sSfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b /tmp "v${TRIVY_VERSION}"

/tmp/trivy fs \
  --scanners vuln,secret,misconfig \
  --severity CRITICAL,HIGH \
  --exit-code 1 \
  --no-progress \
  --format json \
  --output "$REPORT_DIR/trivy-fs/trivy-fs-report.json" \
  .
echo "$?" > "$REPORT_DIR/trivy-fs/trivy.exit"

# Human-readable table alongside the JSON.
/tmp/trivy fs --scanners vuln,secret,misconfig --severity CRITICAL,HIGH \
  --no-progress --format table --output "$REPORT_DIR/trivy-fs/trivy-fs-report.txt" . || true
echo "::endgroup::"

exit 0
