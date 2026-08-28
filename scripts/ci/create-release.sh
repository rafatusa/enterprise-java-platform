#!/usr/bin/env bash
# Creates a GitHub Release and attaches every report produced by the pipeline.
set -euo pipefail

TAG="v$(date -u +%Y.%m.%d)-${GITHUB_SHA::7}"
echo "Creating release ${TAG}"

NOTES_FILE=$(mktemp)
{
  echo "Automated release of enterprise-java-platform."
  echo ""
  echo "**Commit:** \`${GITHUB_SHA}\`"
  echo "**Built:** $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
  echo ""
  echo "### Gates passed"
  echo ""
  echo "| Gate | Threshold |"
  echo "|------|-----------|"
  echo "| Line coverage | >= 90% |"
  echo "| Branch coverage | >= 85% |"
  echo "| Mutation score | >= 70% |"
  echo "| Critical security issues | 0 |"
  echo "| High vulnerabilities | 0 |"
  echo "| Secrets detected | 0 |"
  echo "| Checkstyle violations | 0 |"
  echo "| PMD violations (priority <= 3) | 0 |"
  echo "| SpotBugs High priority | 0 |"
  echo "| p95 latency @ 200 VUs | < 400 ms |"
  echo "| Error rate | < 1% |"
  echo ""

  if [ -f release-artifacts/k6-performance-report/k6-summary.json ]; then
    echo "### Measured performance"
    echo ""
    echo '```json'
    cat release-artifacts/k6-performance-report/k6-summary.json
    echo '```'
    echo ""
  fi

  if [ -f release-artifacts/deployment-summary/deployment-summary.md ]; then
    echo "### Deployment validation"
    echo ""
    cat release-artifacts/deployment-summary/deployment-summary.md
    echo ""
  fi

  echo "### Attached reports"
  echo ""
  echo "JaCoCo coverage, PIT mutation, REST Assured/Surefire, k6 performance,"
  echo "Trivy (filesystem + container), Gitleaks, Semgrep, OWASP Dependency Check,"
  echo "CycloneDX SBOM, Terraform plan and the deployment summary."
} > "$NOTES_FILE"

gh release create "$TAG" \
  --title "Release ${TAG}" \
  --notes-file "$NOTES_FILE" \
  --target "$GITHUB_SHA"

# Attach reports. Directories are zipped so the release stays navigable.
if [ -d release-artifacts ]; then
  cd release-artifacts
  for dir in */; do
    name="${dir%/}"
    zip -qr "../${name}.zip" "$dir"
    echo "Packaged ${name}.zip"
  done
  cd ..

  for zipfile in *.zip; do
    [ -f "$zipfile" ] || continue
    gh release upload "$TAG" "$zipfile" --clobber
    echo "Uploaded ${zipfile}"
  done
fi

echo "Release ${TAG} published."
