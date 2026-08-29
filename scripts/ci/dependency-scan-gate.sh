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
#
# EVERY FINDING IS PRINTED BY *THIS* STEP, not by the scan step.
# The scan step always exits 0 (report-then-gate), so `gh run view --log-failed`
# only ever shows THIS step. A finding printed in the scan step's collapsed
# ::group:: is invisible in exactly the situation where it is needed. Anything a
# human must read to diagnose the failure belongs here.
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

# Name the vulnerable dependencies in the log so the failure is actionable
# without downloading the artifact.
#
# The MATCHED CPE and its version range are printed alongside each finding.
# That evidence is what distinguishes a genuine vulnerability from a CPE
# range-matching artifact — e.g. an advisory whose range is "Apache Tomcat
# 11.0.20 through 11.x" matched against a tomcat-embed-core 10.1.x jar, or a
# log4j-core advisory matched against the log4j-api bridge. Without it, the
# only way to tell them apart is to read each CVE by hand.
#
# It also shows WHICH JAR each CVE was reported against. That matters for
# suppression scoping: Tomcat's embed distribution ships as BOTH
# tomcat-embed-core AND tomcat-embed-websocket, and the same CVE is reported
# against both, so a packageUrl scoped to one artifact silently leaves the
# other unsuppressed.
if [ -f "$REPORT_DIR/owasp/dependency-check-report.json" ]; then
  echo ""
  echo "::group::OWASP: dependencies with CVSS >= 7"
  python3 - "$REPORT_DIR/owasp/dependency-check-report.json" <<'PY' || true
import json
import sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)


def version_range(vuln):
    """Summarise the affected-version range the matcher used."""
    parts = []
    for sw in vuln.get("vulnerableSoftware", []) or []:
        item = sw.get("software", sw) if isinstance(sw, dict) else {}
        cpe = item.get("id") or item.get("name") or ""
        bounds = []
        for key, label in (
            ("versionStartIncluding", ">="),
            ("versionStartExcluding", ">"),
            ("versionEndIncluding", "<="),
            ("versionEndExcluding", "<"),
        ):
            if item.get(key):
                bounds.append(f"{label}{item[key]}")
        if cpe or bounds:
            parts.append(f"{cpe} {' '.join(bounds)}".strip())
    # Keep it short: the first couple of ranges carry the signal.
    return parts[:2]


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
            hits.append(
                (
                    score,
                    dep.get("fileName", "?"),
                    vuln.get("name", "?"),
                    (vuln.get("description") or "").split(". ")[0][:160],
                    version_range(vuln),
                )
            )

for score, name, cve, desc, ranges in sorted(hits, reverse=True):
    print(f"  CVSS {score:>4}  {cve}  in {name}")
    if desc:
        print(f"           {desc}")
    for r in ranges:
        print(f"           matched: {r}")

print(f"\n  {len(hits)} finding(s) at or above CVSS 7.0")

# Distinct artifacts, so a suppression can be scoped to cover all of them.
artifacts = sorted({name for _, name, _, _, _ in hits})
if artifacts:
    print("\n  Reported against these artifacts (scope suppressions to ALL of them):")
    for artifact in artifacts:
        print(f"    - {artifact}")
PY
  echo "::endgroup::"
fi

# Trivy findings, printed HERE for the same reason as the OWASP list above: the
# scan step exits 0, so its own ::group:: output never appears in --log-failed.
# Trivy's JSON groups vulnerabilities by target (a lockfile, a jar, an OS
# package DB), so print target + package + installed/fixed version — the fixed
# version is the whole remediation in one field.
if [ -f "$REPORT_DIR/trivy-fs/trivy-fs-report.json" ]; then
  echo ""
  echo "::group::Trivy filesystem: CRITICAL and HIGH findings"
  python3 - "$REPORT_DIR/trivy-fs/trivy-fs-report.json" <<'PY' || true
import json
import sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)

counts = {"CRITICAL": 0, "HIGH": 0}
rows = []
secrets = []
misconfigs = []

for result in report.get("Results", []) or []:
    target = result.get("Target", "?")
    for vuln in result.get("Vulnerabilities", []) or []:
        sev = (vuln.get("Severity") or "").upper()
        if sev not in counts:
            continue
        counts[sev] += 1
        rows.append(
            (
                sev,
                vuln.get("VulnerabilityID", "?"),
                vuln.get("PkgName", "?"),
                vuln.get("InstalledVersion", "?"),
                vuln.get("FixedVersion") or "(no fix published)",
                target,
                (vuln.get("Title") or "")[:120],
            )
        )
    for finding in result.get("Secrets", []) or []:
        if (finding.get("Severity") or "").upper() in counts:
            secrets.append(
                (target, finding.get("RuleID", "?"), finding.get("StartLine", "?"))
            )
    for finding in result.get("Misconfigurations", []) or []:
        if (finding.get("Severity") or "").upper() in counts:
            misconfigs.append(
                (target, finding.get("ID", "?"), (finding.get("Title") or "")[:120])
            )

# CRITICAL first, then HIGH, then by package.
order = {"CRITICAL": 0, "HIGH": 1}
for sev, vid, pkg, installed, fixed, target, title in sorted(
    rows, key=lambda r: (order.get(r[0], 9), r[2], r[1])
):
    print(f"  {sev:<8} {vid}  {pkg} {installed}")
    print(f"           fixed in: {fixed}")
    print(f"           target:   {target}")
    if title:
        print(f"           {title}")

for target, rule, line in secrets:
    print(f"  SECRET   {rule}  {target}:{line}")

for target, mid, title in misconfigs:
    print(f"  CONFIG   {mid}  {target}")
    if title:
        print(f"           {title}")

print(
    f"\n  vulnerabilities: {counts['CRITICAL']} CRITICAL, {counts['HIGH']} HIGH"
    f"  |  secrets: {len(secrets)}  |  misconfigurations: {len(misconfigs)}"
)
print(
    "\n  A finding with a fixed version is remediated by upgrading that package."
    "\n  '(no fix published)' means no upgrade exists yet — the same situation as"
    "\n  a documented, time-boxed OWASP suppression."
)
PY
  echo "::endgroup::"
fi

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "Security gate failed. Remediate the findings — do not lower failBuildOnCVSS"
  echo "or drop severities from the Trivy invocation to get a green run."
  echo "If a finding's matched version range does not cover the jar's actual"
  echo "version, it is a CPE mismatch: add a documented, time-boxed entry to"
  echo "config/owasp/suppressions.xml naming the CVE and the evidence."
  exit 1
fi

echo "All dependency/security gates passed."
