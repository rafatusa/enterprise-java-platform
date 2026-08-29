#!/usr/bin/env bash
# Gitleaks secret scan. Always produces a report; the verdict is gitleaks-gate.sh.
#
# Same contract as every other scanner in this pipeline (see README
# "report-then-gate"): ALWAYS exit 0, record the verdict under reports/, and
# distinguish "found a secret" from "the scanner could not run":
#   gitleaks.exit -> 0 clean, 1 findings
#   status        -> ok | tool-error
#   error         -> reason, when tool-error
# Both fail the build, but the remedies are unrelated (rotate a credential vs
# fix the runner), so the gate must be able to say which.
set -uo pipefail

VERSION="8.21.2"
REPORT_DIR="reports/security/gitleaks"
mkdir -p "$REPORT_DIR"

BIN=/tmp/gitleaks
TGZ=/tmp/gitleaks.tar.gz
URL="https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/gitleaks_${VERSION}_linux_x64.tar.gz"

record_tool_error() {
  echo "1" > "${REPORT_DIR}/gitleaks.exit"
  echo "tool-error" > "${REPORT_DIR}/status"
  echo "$1" > "${REPORT_DIR}/error"
  echo "::warning::Gitleaks scan skipped — $1"
  exit 0
}

echo "::group::Install gitleaks ${VERSION}"
if ! curl -sSfL --retry 3 --retry-delay 5 -o "$TGZ" "$URL"; then
  echo "::endgroup::"
  record_tool_error "could not download gitleaks ${VERSION} from ${URL}"
fi
if ! tar -xzf "$TGZ" -C /tmp gitleaks; then
  echo "::endgroup::"
  record_tool_error "could not extract gitleaks from the release tarball"
fi
chmod +x "$BIN"
if ! "$BIN" version; then
  echo "::endgroup::"
  record_tool_error "${BIN} is present but not executable on this runner"
fi
echo "::endgroup::"

echo "::group::Gitleaks scan"
# --redact keeps secret VALUES out of the log and the report artifact.
"$BIN" detect \
  --source . \
  --config .gitleaks.toml \
  --report-format json \
  --report-path "${REPORT_DIR}/gitleaks-report.json" \
  --redact \
  --exit-code 1
STATUS=$?
echo "::endgroup::"

# gitleaks: 0 = clean, 1 = leaks found (--exit-code 1), anything else = failure.
if [ "$STATUS" -gt 1 ]; then
  record_tool_error "gitleaks exited ${STATUS} (scanner failure, e.g. an invalid .gitleaks.toml — not a detected secret)"
fi

echo "$STATUS" > "${REPORT_DIR}/gitleaks.exit"
echo "ok" > "${REPORT_DIR}/status"

exit 0
