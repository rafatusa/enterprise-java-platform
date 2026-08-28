#!/usr/bin/env bash
# Gate then publish: a container image with CRITICAL/HIGH vulnerabilities is
# never pushed to the registry. Publishing a known-vulnerable image is worse
# than a failed build, because it outlives the pipeline run.
set -uo pipefail

REPORT_DIR="reports/security/trivy-image"

BUILD_EXIT_FILE="${REPORT_DIR}/build.exit"
if [ -f "$BUILD_EXIT_FILE" ] && [ "$(cat "$BUILD_EXIT_FILE")" != "0" ]; then
  echo "::error::Docker build failed. See the build log above."
  exit 1
fi

EXIT_FILE="${REPORT_DIR}/trivy.exit"
if [ ! -f "$EXIT_FILE" ]; then
  echo "::error::Trivy produced no result file — the container scan did not run correctly."
  exit 1
fi

if [ -f "${REPORT_DIR}/trivy-image-report.json" ]; then
  CRIT=$(grep -o '"Severity": *"CRITICAL"' "${REPORT_DIR}/trivy-image-report.json" | wc -l | tr -d ' ')
  HIGH=$(grep -o '"Severity": *"HIGH"' "${REPORT_DIR}/trivy-image-report.json" | wc -l | tr -d ' ')
  echo "Container image findings — CRITICAL: ${CRIT}, HIGH: ${HIGH}"
fi

CODE="$(cat "$EXIT_FILE")"
if [ "$CODE" != "0" ]; then
  echo "::error::Container scan gate FAILED — the image has CRITICAL or HIGH vulnerabilities and will NOT be published."
  echo "Rebase onto a patched base image (eclipse-temurin:17-jre-jammy) or upgrade the affected package."
  exit 1
fi

echo "Container scan passed. Publishing to GHCR."
docker push "${IMAGE}:${IMAGE_TAG}"
docker push "${IMAGE}:latest"
echo "Published ${IMAGE}:${IMAGE_TAG}"
