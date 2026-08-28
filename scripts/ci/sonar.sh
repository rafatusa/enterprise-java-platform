#!/usr/bin/env bash
# SonarQube / SonarCloud analysis with quality-gate wait.
#
# SonarQube needs a server this project does not provision. Rather than
# hard-failing every deploy on a missing external dependency, the stage SKIPS
# with a visible warning when the credential is absent, and runs for real
# (including -Dsonar.qualitygate.wait=true, which fails the build on a red gate)
# once it is configured.
#
# The credential is read from the environment only — it is never written here.
set -euo pipefail

if [ -z "${SONAR_TOKEN:-}" ]; then
  echo "::warning title=SonarQube skipped::SONAR_TOKEN is not configured. Add SONAR_TOKEN and SONAR_HOST_URL as repository secrets to enable SonarQube analysis and its quality gate."
  exit 0
fi

HOST="${SONAR_HOST_URL:-https://sonarcloud.io}"
PROJECT_KEY="${SONAR_PROJECT_KEY:-enterprise-java-platform}"

echo "Running SonarQube analysis against ${HOST}"

# sonar.token is read by the scanner from the environment variable of the same
# name, so it never appears on the command line (where it would land in ps output).
export SONAR_TOKEN
mvn -B -ntp verify sonar:sonar \
  -DskipTests \
  -Dsonar.projectKey="$PROJECT_KEY" \
  -Dsonar.host.url="$HOST" \
  -Dsonar.qualitygate.wait=true

echo "SonarQube quality gate passed."
