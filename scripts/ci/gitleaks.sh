#!/usr/bin/env bash
# Gitleaks secret scan. Always produces a report; the verdict is gitleaks-gate.sh.
set -uo pipefail

VERSION="8.21.2"
REPORT_DIR="reports/security/gitleaks"
mkdir -p "$REPORT_DIR"

curl -sSfL -o /tmp/gitleaks.tar.gz \
  "https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/gitleaks_${VERSION}_linux_x64.tar.gz"
tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks
chmod +x /tmp/gitleaks

echo "::group::Gitleaks scan"
# --redact keeps secret VALUES out of the log and the report artifact.
/tmp/gitleaks detect \
  --source . \
  --config .gitleaks.toml \
  --report-format json \
  --report-path "${REPORT_DIR}/gitleaks-report.json" \
  --redact \
  --exit-code 1
echo "$?" > "${REPORT_DIR}/gitleaks.exit"
echo "::endgroup::"

exit 0
