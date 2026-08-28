#!/usr/bin/env bash
# Gate: Critical security issues > 0 or High vulnerabilities > 0 fail the build.
#
# Covers OWASP Dependency Check (CVSS >= 7 per pom.xml) and Trivy filesystem
# (CRITICAL,HIGH). SBOM generation must also have succeeded — a missing SBOM is a
# supply-chain reporting failure, not a cosmetic one.
#
# Each tool is reported in one of three states, because they need different
# actions and conflating them sends people to the wrong place:
#   passed      -> nothing to do
#   findings    -> real vulnerabilities; upgrade the dependency
#   tool-error  -> the scanner never ran; fix the runner, NOT the code
# tool-error still fails the build: unscanned code is unverified, not approved.
set -uo pipefail

REPORT_DIR="reports/security"
FAILED=0

verdict() {
  local label="$1"
  local dir="$2"
  local file="$3"
  local hint="$4"

  # A recorded tool-error takes precedence over the exit code, which is set to 1
  # only so that nothing downstream mistakes a failed scan for a clean one.
  if [ -f "${dir}/status" ] && [ "$(cat "${dir}/status")" = "tool-error" ]; then
    echo "::error::${label} gate FAILED — the scanner could not run."
    if [ -f "${dir}/error" ]; then
      echo "  Reason: $(cat "${dir}/error")"
    fi
    echo "  This is NOT a vulnerability report — nothing was scanned, so the"
    echo "  code is UNVERIFIED. Fix the runner/network, not the dependencies."
    FAILED=1
    return
  fi

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

verdict "OWASP Dependency Check" "$REPORT_DIR/owasp" "$REPORT_DIR/owasp/owasp.exit" \
  "A dependency has a CVSS >= 7 vulnerability. Upgrade it; suppress only with a documented, time-boxed entry."

verdict "CycloneDX SBOM" "$REPORT_DIR/sbom" "$REPORT_DIR/sbom/sbom.exit" \
  "SBOM generation failed — the build cannot ship without a bill of materials."

verdict "Trivy filesystem" "$REPORT_DIR/trivy-fs" "$REPORT_DIR/trivy-fs/trivy.exit" \
  "CRITICAL or HIGH findings in the filesystem scan. See reports/security/trivy-fs/."

# Findings summary, only meaningful when Trivy actually produced a report.
if [ -f "$REPORT_DIR/trivy-fs/trivy-fs-report.json" ]; then
  CRIT=$(grep -o '"Severity": *"CRITICAL"' "$REPORT_DIR/trivy-fs/trivy-fs-report.json" | wc -l | tr -d ' ')
  HIGH=$(grep -o '"Severity": *"HIGH"' "$REPORT_DIR/trivy-fs/trivy-fs-report.json" | wc -l | tr -d ' ')
  echo "Trivy filesystem findings — CRITICAL: ${CRIT}, HIGH: ${HIGH}"
fi

# Name the vulnerable dependencies in the log so the failure is actionable
# without downloading the artifact.
if [ -f "$REPORT_DIR/owasp/dependency-check-report.json" ]; then
  echo ""
  echo "::group::OWASP: dependencies with CVSS >= 7"
  python3 - "$REPORT_DIR/owasp/dependency-check-report.json" <<'PY' || true
import json
import sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)

hits = []
for dep in report.get("dependencies", []):
    for vuln in dep.get("vulnerabilities", []) or []:
        score = 0.0
        cvss3 = vuln.get("cvssv3") or {}
        cvss2 = vuln.get("cvssv2") or {}
        try:
            score = float(cvss3.get("baseScore") or cvss2.get("score") or 0)
        except (TypeError, ValueError):
            score = 0.0
        if score >= 7.0:
            hits.append((score, dep.get("fileName", "?"), vuln.get("name", "?"),
                         (vuln.get("description") or "").split(". ")[0][:160]))

for score, name, cve, desc in sorted(hits, reverse=True):
    print(f"  CVSS {score:>4}  {cve}  in {name}")
    if desc:
        print(f"           {desc}")

print(f"\n  {len(hits)} finding(s) at or above CVSS 7.0")
PY
  echo "::endgroup::"
fi

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "Security gate failed. Remediate the findings — do not lower failBuildOnCVSS"
  echo "or drop severities from the Trivy invocation to get a green run."
  exit 1
fi

echo "All dependency/security gates passed."
