#!/usr/bin/env bash
# Installs Trivy and prints its absolute path on stdout. Exits non-zero if the
# binary is not usable.
#
# SINGLE SOURCE OF TRUTH: both the filesystem scan (dependency-scan.sh) and the
# container scan (docker-build-scan.sh) source this. They previously each
# inlined `curl … install.sh | sh -s -- -b /tmp`, which logs "found version"
# and can still leave no binary behind; the callers then reported
# "/tmp/trivy: No such file or directory" as CRITICAL/HIGH findings. Fixing one
# call site and not the other is how the same failure comes back two stages
# later, so the installer lives here and nowhere else.
#
# Usage:
#   TRIVY_BIN="$(bash scripts/ci/install-trivy.sh)" || handle_tool_error
set -uo pipefail

TRIVY_VERSION="${TRIVY_VERSION:-0.58.2}"
DEST="${TRIVY_DEST:-/tmp}"
BIN="${DEST}/trivy"

# Already installed and working (both scans run in the same job in some layouts).
if [ -x "$BIN" ] && "$BIN" --version >/dev/null 2>&1; then
  echo "$BIN"
  exit 0
fi

TGZ="${DEST}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
URL="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"

# All progress output goes to stderr: stdout carries ONLY the resolved path.
{
  echo "Installing Trivy ${TRIVY_VERSION} from ${URL}"

  if ! curl -sSfL --retry 3 --retry-delay 5 -o "$TGZ" "$URL"; then
    echo "ERROR: download failed"
    exit 1
  fi

  if ! tar -xzf "$TGZ" -C "$DEST" trivy; then
    echo "ERROR: could not extract trivy from the release tarball"
    exit 1
  fi

  chmod +x "$BIN"

  if ! "$BIN" --version; then
    echo "ERROR: ${BIN} is present but not executable on this runner"
    exit 1
  fi
} >&2

echo "$BIN"
