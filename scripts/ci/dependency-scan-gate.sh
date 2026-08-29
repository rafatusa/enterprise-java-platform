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
#
# ORDERING MATTERS: log retrieval (`gh run view --log-failed`, `gh api .../logs`)
# TRUNCATES long output, and it truncates the TAIL. The Trivy block is printed
# BEFORE the OWASP block because it is far shorter and was invisible for four
# consecutive attempts behind a long OWASP list. Put the scarcest information
# first; never assume the whole step output survives retrieval.
#
# ---------------------------------------------------------------------------
# SECURITY_GATE_MODE — the ONE sanctioned, temporary escape hatch
# ---------------------------------------------------------------------------
# Unset / anything else  -> "enforcing": CRITICAL and HIGH both fail. DEFAULT.
# "critical-only"        -> HIGH findings are reported as warnings; CRITICAL
#                           still fails the build.
#
# This exists so a project whose infrastructure path has never executed can be
# unblocked ONCE, deliberately, by a human decision recorded in the pipeline
# spec — instead of the far worse alternatives people reach for under pressure:
# lowering failBuildOnCVSS in pom.xml, dropping HIGH from the Trivy --severity
# list, or deleting the stage. Those changes are invisible in a log, apply to
# every dependency forever, and are easy to forget. This one announces itself
# in red on every run and is reverted by deleting a single env var.
#
# INVARIANTS — do not weaken these to make a build pass:
#   * The scanners still run at FULL severity. Nothing is filtered at scan time.
#   * Every finding is still printed and still uploaded as an artifact.
#   * CRITICAL always fails, in every mode.
#   * A tool-error always fails, in every mode: unscanned is not approved.
#   * The waiver is visible on stdout AND in the job summary annotation.
set -uo pipefail

REPORT_DIR="reports/security"
FAILED=0

GATE_MODE="${SECURITY_GATE_MODE:-enforcing}"
if [ "$GATE_MODE" = "critical-only" ]; then
  echo "::warning::SECURITY GATE IS IN critical-only MODE — HIGH-severity findings are being reported as warnings instead of failing the build. This is a temporary, human-authorised waiver. Remove SECURITY_GATE_MODE from .udap/pipeline.yaml to restore full enforcement."
  echo ""
  echo "=============================================================="
  echo " SECURITY GATE MODE: critical-only  (TEMPORARY WAIVER ACTIVE)"
  echo "=============================================================="
  echo " HIGH findings below are REAL and are NOT fixed — they are"
  echo " being tolerated for this run only. CRITICAL findings still"
  echo " fail the build. Restore full enforcement by deleting the"
  echo " SECURITY_GATE_MODE env var from .udap/pipeline.yaml."
  echo "=============================================================="
  echo ""
else
  echo "Security gate mode: enforcing (CRITICAL and HIGH both fail)."
fi

# Fail the build for this finding, unless a HIGH is being waived.
# severity: "critical" (always fails) or "high" (waived in critical-only mode).
gate_fail() {
  local severity="$1"
  local message="$2"

  if [ "$severity" = "high" ] && [ "$GATE_MODE" = "critical-only" ]; then
    echo "::warning::[WAIVED — critical-only mode] ${message}"
    return
  fi

  echo "::error::${message}"
  FAILED=1
}

verdict() {
  local label="$1"
  local dir="$2"
  local file="$3"
  local hint="$4"
  local severity="$5"

  # A recorded tool-error takes precedence over the exit code, which is set to 1
  # only so that nothing downstream mistakes a failed scan for a clean one.
  # NOTE: a tool-error is NEVER waived, in any mode. "The scanner did not run"
  # is not a severity judgement — it means the code is unverified, and an
  # unverified build must not ship regardless of how tolerant the gate is.
  if [ -f "${dir}/status" ] && [ "$(cat "${dir}/status")" = "tool-error" ]; then
    echo "::error::${label} gate FAILED — the scanner could not run."
    if [ -f "${dir}/error" ]; then
      echo "  Reason: $(cat "${dir}/error")"
    fi
    echo "  This is NOT a vulnerability report — nothing was scanned, so the"
    echo "  code is UNVERIFIED. Fix the runner/network, not the dependencies."
    echo "  (Not waivable: SECURITY_GATE_MODE does not apply to tool errors.)"
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
    gate_fail "$severity" "${label} gate FAILED. ${hint}"
  else
    echo "${label} gate passed."
  fi
}

# --- Severity classification ------------------------------------------------
#
# Both classifiers below answer ONE question: "is there a CRITICAL here?" — a
# CRITICAL is never waivable, a HIGH is (under critical-only mode).
#
# These must be STRUCTURAL, not textual. An earlier version grepped the Trivy
# JSON for '"Severity": "CRITICAL"' anywhere in the file, which also matched
# MISCONFIGURATION and SECRET entries — so a CRITICAL-severity IaC rule made
# the whole Trivy verdict unwaivable even when zero CRITICAL vulnerabilities
# existed. Parse the structure and look only where the answer actually lives.

# Trivy: only Results[].Vulnerabilities[] counts toward the vulnerability
# severity. Misconfigurations and secrets are reported separately below and are
# managed through .trivyignore, not through this classification.
TRIVY_SEVERITY="high"
if [ -f "$REPORT_DIR/trivy-fs/trivy-fs-report.json" ] &&
  python3 -c "
import json, sys
report = json.load(open('$REPORT_DIR/trivy-fs/trivy-fs-report.json'))
for result in report.get('Results', []) or []:
    for vuln in result.get('Vulnerabilities', []) or []:
        if (vuln.get('Severity') or '').upper() == 'CRITICAL':
            sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
  TRIVY_SEVERITY="critical"
fi

# OWASP: failBuildOnCVSS is 7, so any finding it reports is >= 7.0. Treat >= 9.0
# as critical (never waivable) and 7.0-8.9 as high.
OWASP_SEVERITY="high"
if [ -f "$REPORT_DIR/owasp/dependency-check-report.json" ] &&
  python3 -c "
import json, sys
report = json.load(open('$REPORT_DIR/owasp/dependency-check-report.json'))
for dep in report.get('dependencies', []):
    for vuln in dep.get('vulnerabilities', []) or []:
        c3, c2 = vuln.get('cvssv3') or {}, vuln.get('cvssv2') or {}
        try:
            score = float(c3.get('baseScore') or c2.get('score') or 0)
        except (TypeError, ValueError):
            continue
        if score >= 9.0:
            sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
  OWASP_SEVERITY="critical"
fi

verdict "OWASP Dependency Check" "$REPORT_DIR/owasp" "$REPORT_DIR/owasp/owasp.exit" \
  "A dependency has a CVSS >= 7 vulnerability. Upgrade it; suppress only with a documented, time-boxed entry." \
  "$OWASP_SEVERITY"

# The SBOM is a supply-chain deliverable, not a severity judgement — never waived.
verdict "CycloneDX SBOM" "$REPORT_DIR/sbom" "$REPORT_DIR/sbom/sbom.exit" \
  "SBOM generation failed — the build cannot ship without a bill of materials." \
  "critical"

verdict "Trivy filesystem" "$REPORT_DIR/trivy-fs" "$REPORT_DIR/trivy-fs/trivy.exit" \
  "CRITICAL or HIGH findings in the filesystem scan. See reports/security/trivy-fs/." \
  "$TRIVY_SEVERITY"

# --- Trivy findings FIRST (see the ordering note in the header) -------------
#
# Trivy's JSON groups vulnerabilities by target (a lockfile, a jar, an OS
# package DB), so print target + package + installed/fixed version — the fixed
# version is the whole remediation in one field. Trivy uses its own
# version-accurate database, so nothing in config/owasp/suppressions.xml
# affects these findings: they are an independent gate, managed through
# .trivyignore.
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
    "\n  Misconfigurations are IaC rules; accepted ones live in .trivyignore"
    "\n  with their reasoning and a review date."
)
PY
  echo "::endgroup::"
fi

# --- OWASP findings second --------------------------------------------------
#
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

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "Security gate failed. Remediate the findings — do not lower failBuildOnCVSS"
  echo "or drop severities from the Trivy invocation to get a green run."
  echo "If a finding's matched version range does not cover the jar's actual"
  echo "version, it is a CPE mismatch: add a documented, time-boxed entry to"
  echo "config/owasp/suppressions.xml naming the CVE and the evidence."
  exit 1
fi

if [ "$GATE_MODE" = "critical-only" ]; then
  echo ""
  echo "::warning::Dependency/security gates passed under the critical-only waiver. HIGH findings above are unresolved. Restore full enforcement by removing SECURITY_GATE_MODE from .udap/pipeline.yaml."
else
  echo "All dependency/security gates passed."
fi
