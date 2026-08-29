#!/usr/bin/env bash
# Builds the container image and scans it with Trivy.
# Always collects the report; the verdict + push happen in docker-push.sh.
#
# Contract (identical to dependency-scan.sh — see README "report-then-gate"):
# this script ALWAYS exits 0 and records each step's verdict under
# reports/security/trivy-image/, so the artifact upload runs even when the gate
# is about to fail.
#
# CRITICAL DISTINCTION: "the image is vulnerable" and "the scanner could not
# run" must NOT look the same. The scan records BOTH:
#   trivy.exit  -> 0 clean, 1 findings
#   status      -> ok | tool-error
#   error       -> reason, when tool-error
# Both fail the build (an unrun scan is not a pass), but the gate says which,
# because the remedies are unrelated: rebase the image vs. fix the runner.
set -uo pipefail

REPORT_DIR="reports/security/trivy-image"
mkdir -p "$REPORT_DIR"

IMAGE="ghcr.io/$(echo "${REPO_OWNER}" | tr '[:upper:]' '[:lower:]')/enterprise-java-platform"
echo "IMAGE=${IMAGE}" >> "$GITHUB_ENV"
echo "Building ${IMAGE}:${IMAGE_TAG}"

echo "::group::Docker build"
docker build -t "${IMAGE}:${IMAGE_TAG}" -t "${IMAGE}:latest" .
BUILD_EXIT=$?
echo "::endgroup::"
echo "$BUILD_EXIT" > "${REPORT_DIR}/build.exit"

if [ "$BUILD_EXIT" -ne 0 ]; then
  echo "::error::Docker build failed — skipping the container scan."
  exit 0
fi

# The installer is shared with the filesystem scan (scripts/ci/install-trivy.sh)
# so a fix to it reaches every call site. This file previously inlined its own
# `curl … install.sh | sh -s -- -b /tmp`, which logged "found version" while
# leaving no binary behind — and the missing binary was then reported as
# CRITICAL/HIGH findings.
TRIVY_BIN="$(bash scripts/ci/install-trivy.sh)"
if [ -z "$TRIVY_BIN" ]; then
  echo "1" > "${REPORT_DIR}/trivy.exit"
  echo "tool-error" > "${REPORT_DIR}/status"
  echo "Trivy could not be installed on this runner (see the install log above)." \
    > "${REPORT_DIR}/error"
  echo "::warning::Trivy container scan skipped — the scanner could not be installed."
  exit 0
fi

echo "::group::Trivy container scan"
# --exit-code 1 => findings. Anything else is a scanner/DB failure, which is
# NOT a finding (Trivy exits 2 on a fatal error, e.g. an unreachable DB).
# --ignore-unfixed: only vulnerabilities with an available patch can be acted
# on; an unfixable distro CVE would block every build with no remedy.
"$TRIVY_BIN" image \
  --severity CRITICAL,HIGH \
  --exit-code 1 \
  --no-progress \
  --ignore-unfixed \
  --format json \
  --output "${REPORT_DIR}/trivy-image-report.json" \
  "${IMAGE}:${IMAGE_TAG}"
TRIVY_STATUS=$?
echo "::endgroup::"

if [ "$TRIVY_STATUS" -gt 1 ]; then
  echo "1" > "${REPORT_DIR}/trivy.exit"
  echo "tool-error" > "${REPORT_DIR}/status"
  echo "trivy exited ${TRIVY_STATUS} (scanner or vulnerability-DB failure, not an image finding)" \
    > "${REPORT_DIR}/error"
  echo "::warning::Trivy exited ${TRIVY_STATUS} — treating as a tool error, not findings."
  exit 0
fi

echo "$TRIVY_STATUS" > "${REPORT_DIR}/trivy.exit"
echo "ok" > "${REPORT_DIR}/status"

# Human-readable table alongside the JSON, printed into the log so the gate is
# explainable without downloading the artifact.
"$TRIVY_BIN" image --severity CRITICAL,HIGH --no-progress --ignore-unfixed \
  --format table --output "${REPORT_DIR}/trivy-image-report.txt" \
  "${IMAGE}:${IMAGE_TAG}" || true
if [ -s "${REPORT_DIR}/trivy-image-report.txt" ]; then
  echo "::group::Trivy container findings"
  cat "${REPORT_DIR}/trivy-image-report.txt"
  echo "::endgroup::"
fi

exit 0
