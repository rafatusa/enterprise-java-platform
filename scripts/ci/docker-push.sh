#!/usr/bin/env bash
# Gate then publish: a container image with CRITICAL/HIGH vulnerabilities is
# never pushed to the registry. Publishing a known-vulnerable image is worse
# than a failed build, because it outlives the pipeline run.
#
# A scan that could not RUN is also not a pass — but it is reported as a tool
# error, because the remedy (fix the runner) is unrelated to the remedy for a
# real finding (rebase the base image / upgrade the package).
#
# SECURITY_GATE_MODE — the same temporary, human-authorised escape hatch the
# dependency gate honours. See the long note in scripts/ci/dependency-scan-gate.sh.
#   unset / anything else -> enforcing: CRITICAL and HIGH both block the push
#   "critical-only"       -> HIGH is reported as a warning; CRITICAL still blocks
# Invariants: the scan still runs at full severity, every finding is still
# printed and uploaded, CRITICAL always blocks, and a tool-error always blocks
# (an unscanned image is not an approved image, in any mode).
set -uo pipefail

REPORT_DIR="reports/security/trivy-image"
GATE_MODE="${SECURITY_GATE_MODE:-enforcing}"

BUILD_EXIT_FILE="${REPORT_DIR}/build.exit"
if [ -f "$BUILD_EXIT_FILE" ] && [ "$(cat "$BUILD_EXIT_FILE")" != "0" ]; then
  echo "::error::Docker build failed. See the build log above."
  exit 1
fi

STATUS_FILE="${REPORT_DIR}/status"
EXIT_FILE="${REPORT_DIR}/trivy.exit"

if [ ! -f "$STATUS_FILE" ] || [ ! -f "$EXIT_FILE" ]; then
  echo "::error::Trivy produced no result files — the container scan did not run at all."
  echo "This is a RUNNER problem, not an image finding. Check the 'Trivy container scan' step above."
  exit 1
fi

# NEVER waived, in any mode: an unscanned image is unverified, not approved.
if [ "$(cat "$STATUS_FILE")" = "tool-error" ]; then
  echo "::error::The container scanner could not run — the image was NOT scanned and will NOT be published."
  [ -f "${REPORT_DIR}/error" ] && cat "${REPORT_DIR}/error"
  echo "This is NOT a vulnerability report. Fix the scanner installation (scripts/ci/install-trivy.sh), then re-run."
  echo "(Not waivable: SECURITY_GATE_MODE does not apply to tool errors.)"
  exit 1
fi

# Print the findings into the log so the failure is self-explanatory without
# downloading the artifact.
if [ -s "${REPORT_DIR}/trivy-image-report.txt" ]; then
  echo "::group::Container image findings"
  cat "${REPORT_DIR}/trivy-image-report.txt"
  echo "::endgroup::"
fi

CRIT=0
if [ -f "${REPORT_DIR}/trivy-image-report.json" ]; then
  CRIT=$(grep -o '"Severity": *"CRITICAL"' "${REPORT_DIR}/trivy-image-report.json" | wc -l | tr -d ' ')
  HIGH=$(grep -o '"Severity": *"HIGH"' "${REPORT_DIR}/trivy-image-report.json" | wc -l | tr -d ' ')
  echo "Container image findings — CRITICAL: ${CRIT}, HIGH: ${HIGH} (fixable only)"
fi

CODE="$(cat "$EXIT_FILE")"
if [ "$CODE" != "0" ]; then
  # A CRITICAL is never waivable. Only a HIGH-only result can pass under the
  # temporary waiver.
  if [ "$GATE_MODE" = "critical-only" ] && [ "${CRIT:-0}" -eq 0 ]; then
    echo "::warning::[WAIVED — critical-only mode] The image has fixable HIGH vulnerabilities. Publishing anyway under the temporary, human-authorised waiver. Remove SECURITY_GATE_MODE from .udap/pipeline.yaml to restore full enforcement."
    echo ""
    echo "=============================================================="
    echo " PUBLISHING AN IMAGE WITH KNOWN HIGH FINDINGS (waiver active)"
    echo "=============================================================="
    echo " The findings above are REAL and are NOT fixed. This image"
    echo " will exist in GHCR after this run. Remedy them and re-push"
    echo " as soon as the deploy path is proven."
    echo "=============================================================="
  else
    echo "::error::Container scan gate FAILED — the image has fixable CRITICAL or HIGH vulnerabilities and will NOT be published."
    echo "Remedy: the Dockerfile runtime stage runs 'apt-get upgrade' to pull base-image package patches; if a finding persists, rebase onto a newer eclipse-temurin tag."
    exit 1
  fi
else
  echo "Container scan passed. Publishing to GHCR."
fi

docker push "${IMAGE}:${IMAGE_TAG}"
docker push "${IMAGE}:latest"
echo "Published ${IMAGE}:${IMAGE_TAG}"
