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
# VERSION PINNING — read before changing TRIVY_VERSION:
# The pin must be a tag that actually EXISTS at
# https://github.com/aquasecurity/trivy/releases. A fictitious tag makes the
# asset URL 404, and a 404 here previously surfaced as "CRITICAL or HIGH
# findings" in the gate. Verify with:
#   gh release view "v${TRIVY_VERSION}" --repo aquasecurity/trivy
# The asset name is trivy_<version>_Linux-64bit.tar.gz (capital L, "64bit").
#
# Usage:
#   TRIVY_BIN="$(bash scripts/ci/install-trivy.sh)" || handle_tool_error
set -uo pipefail

TRIVY_VERSION="${TRIVY_VERSION:-0.74.0}"
DEST="${TRIVY_DEST:-/tmp}"
BIN="${DEST}/trivy"

# Already installed and working (both scans run in the same job in some layouts).
if [ -x "$BIN" ] && "$BIN" --version >/dev/null 2>&1; then
  echo "$BIN"
  exit 0
fi

# All progress output goes to stderr: stdout carries ONLY the resolved path.
{
  fetch() {
    local version="$1"
    local tgz="${DEST}/trivy_${version}_Linux-64bit.tar.gz"
    local url="https://github.com/aquasecurity/trivy/releases/download/v${version}/trivy_${version}_Linux-64bit.tar.gz"

    echo "Installing Trivy ${version} from ${url}"
    if ! curl -sSfL --retry 3 --retry-delay 5 -o "$tgz" "$url"; then
      echo "ERROR: download failed for v${version} (does that release tag exist?)"
      return 1
    fi
    if ! tar -xzf "$tgz" -C "$DEST" trivy; then
      echo "ERROR: could not extract trivy from the release tarball"
      return 1
    fi
    chmod +x "$BIN"
    if ! "$BIN" --version; then
      echo "ERROR: ${BIN} is present but not executable on this runner"
      return 1
    fi
    return 0
  }

  if ! fetch "$TRIVY_VERSION"; then
    # A pin that no longer resolves must not silently disable security scanning.
    # Fall back to whatever the project's latest release actually is, and say so
    # loudly so the stale pin gets corrected rather than lived with.
    echo "::warning::Trivy ${TRIVY_VERSION} could not be installed; falling back to the latest release. Correct TRIVY_VERSION in scripts/ci/install-trivy.sh."
    LATEST="$(curl -sSfL https://api.github.com/repos/aquasecurity/trivy/releases/latest \
      | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')"
    if [ -z "${LATEST:-}" ]; then
      echo "ERROR: could not resolve the latest Trivy release either"
      exit 1
    fi
    fetch "$LATEST" || exit 1
  fi
} >&2

echo "$BIN"
