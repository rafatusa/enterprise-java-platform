#!/usr/bin/env bash
# OWASP Dependency Check + CycloneDX SBOM + Trivy filesystem scan.
#
# Contract (see README "report-then-gate"): this script ALWAYS exits 0 and
# records each tool's verdict under reports/security/, so the artifact upload
# runs even when a gate is about to fail. dependency-scan-gate.sh turns the
# recorded verdicts into the build result.
#
# CRITICAL DISTINCTION: "the scanner found a vulnerability" and "the scanner
# could not run" must NOT look the same. Each tool records BOTH:
#   <tool>.exit    -> 0 clean, 1 findings
#   status         -> ok | tool-error
#   error          -> reason, when tool-error
# Both fail the build (an unrun scan is not a pass), but the gate says which,
# because the remedies are unrelated: upgrade a dependency vs. fix the runner.
set -uo pipefail

REPORT_DIR="reports/security"
mkdir -p "$REPORT_DIR/owasp" "$REPORT_DIR/sbom" "$REPORT_DIR/trivy-fs"

# --- OWASP Dependency Check (fails at CVSS >= 7 per pom.xml) ---
# The NVD credential is read from the environment by the plugin
# (dependency-check reads nvd.api.key from NVD_API_KEY), so it is never passed
# on the command line.
echo "::group::OWASP Dependency Check"
if [ -z "${NVD_API_KEY:-}" ]; then
  echo "::warning::NVD_API_KEY is not configured — the NVD feed is heavily rate-limited without one and this step will be slow. Request a free key at https://nvd.nist.gov/developers/request-an-api-key"
fi
mvn -B -ntp org.owasp:dependency-check-maven:check
OWASP_STATUS=$?
echo "$OWASP_STATUS" > "$REPORT_DIR/owasp/owasp.exit"
echo "ok" > "$REPORT_DIR/owasp/status"
echo "::endgroup::"

for f in target/dependency-check-report.html target/dependency-check-report.json; do
  [ -f "$f" ] && cp "$f" "$REPORT_DIR/owasp/" || true
done

# --- CycloneDX SBOM ---
echo "::group::CycloneDX SBOM"
mvn -B -ntp cyclonedx:makeAggregateBom
echo "$?" > "$REPORT_DIR/sbom/sbom.exit"
echo "ok" > "$REPORT_DIR/sbom/status"
echo "::endgroup::"

for f in target/bom.xml target/bom.json; do
  [ -f "$f" ] && cp "$f" "$REPORT_DIR/sbom/" || true
done

# --- Trivy filesystem scan ---
# The installer is shared with the container scan (scripts/ci/install-trivy.sh)
# so a fix to it reaches every call site.
TRIVY_BIN="$(bash scripts/ci/install-trivy.sh)"
if [ -z "$TRIVY_BIN" ]; then
  echo "1" > "$REPORT_DIR/trivy-fs/trivy.exit"
  echo "tool-error" > "$REPORT_DIR/trivy-fs/status"
  echo "Trivy could not be installed on this runner (see the install log above)." \
    > "$REPORT_DIR/trivy-fs/error"
  echo "::warning::Trivy filesystem scan skipped — the scanner could not be installed."
else
  echo "::group::Trivy filesystem scan"
  # --exit-code 1 => findings. Anything else is a scanner/DB failure, which is
  # NOT a finding (Trivy exits 2 on a fatal error, e.g. an unreachable DB).
  "$TRIVY_BIN" fs \
    --scanners vuln,secret,misconfig \
    --severity CRITICAL,HIGH \
    --exit-code 1 \
    --no-progress \
    --format json \
    --output "$REPORT_DIR/trivy-fs/trivy-fs-report.json" \
    .
  TRIVY_STATUS=$?
  echo "::endgroup::"

  if [ "$TRIVY_STATUS" -gt 1 ]; then
    echo "1" > "$REPORT_DIR/trivy-fs/trivy.exit"
    echo "tool-error" > "$REPORT_DIR/trivy-fs/status"
    echo "trivy exited ${TRIVY_STATUS} (scanner or vulnerability-DB failure, not a code finding)" \
      > "$REPORT_DIR/trivy-fs/error"
    echo "::warning::Trivy exited ${TRIVY_STATUS} — treating as a tool error, not findings."
  else
    echo "$TRIVY_STATUS" > "$REPORT_DIR/trivy-fs/trivy.exit"
    echo "ok" > "$REPORT_DIR/trivy-fs/status"

    # Human-readable table alongside the JSON, printed into the log so the gate
    # is explainable without downloading the artifact.
    "$TRIVY_BIN" fs --scanners vuln,secret,misconfig --severity CRITICAL,HIGH \
      --no-progress --format table --output "$REPORT_DIR/trivy-fs/trivy-fs-report.txt" . || true
    if [ -s "$REPORT_DIR/trivy-fs/trivy-fs-report.txt" ]; then
      echo "::group::Trivy filesystem findings"
      cat "$REPORT_DIR/trivy-fs/trivy-fs-report.txt"
      echo "::endgroup::"
    fi
  fi
fi

exit 0
