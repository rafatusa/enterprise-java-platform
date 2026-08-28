#!/usr/bin/env bash
# Builds the container image and scans it with Trivy.
# Always collects the report; the verdict + push happen in docker-push.sh.
set -uo pipefail

TRIVY_VERSION="0.58.2"
REPORT_DIR="reports/security/trivy-image"
mkdir -p "$REPORT_DIR"

IMAGE="ghcr.io/$(echo "${REPO_OWNER}" | tr '[:upper:]' '[:lower:]')/enterprise-java-platform"
echo "IMAGE=${IMAGE}" >> "$GITHUB_ENV"
echo "Building ${IMAGE}:${IMAGE_TAG}"

echo "::group::Docker build"
docker build -t "${IMAGE}:${IMAGE_TAG}" -t "${IMAGE}:latest" .
BUILD_EXIT=$?
echo "$BUILD_EXIT" > "${REPORT_DIR}/build.exit"
echo "::endgroup::"

if [ "$BUILD_EXIT" -ne 0 ]; then
  echo "::error::Docker build failed — skipping the container scan."
  exit 0
fi

echo "::group::Trivy container scan"
curl -sSfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b /tmp "v${TRIVY_VERSION}"

/tmp/trivy image \
  --severity CRITICAL,HIGH \
  --exit-code 1 \
  --no-progress \
  --ignore-unfixed \
  --format json \
  --output "${REPORT_DIR}/trivy-image-report.json" \
  "${IMAGE}:${IMAGE_TAG}"
echo "$?" > "${REPORT_DIR}/trivy.exit"

/tmp/trivy image --severity CRITICAL,HIGH --no-progress --ignore-unfixed \
  --format table --output "${REPORT_DIR}/trivy-image-report.txt" \
  "${IMAGE}:${IMAGE_TAG}" || true
echo "::endgroup::"

exit 0
