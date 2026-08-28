#!/usr/bin/env bash
# Gate: Critical security issues > 0 or High vulnerabilities > 0 fail the build.
#
# Covers OWASP Dependency Check (CVSS >= 7 per pom.xml) and Trivy filesystem
# (CRITICAL,HIGH). SBOM generation must also have succeeded — a missing SBOM is a
# supply-chain reporting failure, not a cosmetic one.
set -uo pipefail

REPORT_DIR="reports/security"
FAILED=0

verdict() {
  local label="$1"
  local file="$2"
  local hint="$3"

  if [ ! -f "$file" ]; then
    echo "::error::${label} produced no result file — the scan did not run correctly."
    FAILED=1
    return
  fi

  local code
  code="$(cat "$file")"
  if [ "$code" != "0" ]; then
    echo "::error::${label} gate FAILED. ${hint}"
    FAILED=1
  else
    echo "${label} gate passed."
  fi
}

verdict "OWASP Dependency Check" "$REPORT_DIR/owasp/owasp.exit" \
  "A dependency has a CVSS >= 7 vulnerability. Upgrade it; suppress only with a documented, time-boxed entry."

verdict "CycloneDX SBOM" "$REPORT_DIR/sbom/sbom.exit" \
  "SBOM generation failed — the build cannot ship without a bill of materials."

verdict "Trivy filesystem" "$REPORT_DIR/trivy-fs/trivy.exit" \
  "CRITICAL or HIGH findings in the filesystem scan. See reports/security/trivy-fs/."

if [ -f "$REPORT_DIR/trivy-fs/trivy-fs-report.json" ]; then
  CRIT=$(grep -o '"Severity": *"CRITICAL"' "$REPORT_DIR/trivy-fs/trivy-fs-report.json" | wc -l | tr -d ' ')
  HIGH=$(grep -o '"Severity": *"HIGH"' "$REPORT_DIR/trivy-fs/trivy-fs-report.json" | wc -l | tr -d ' ')
  echo "Trivy filesystem findings — CRITICAL: ${CRIT}, HIGH: ${HIGH}"
fi

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "Security gate failed. Remediate the findings — do not lower failBuildOnCVSS"
  echo "or drop severities from the Trivy invocation to get a green run."
  exit 1
fi

echo "All dependency/security gates passed."
