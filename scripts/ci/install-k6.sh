#!/usr/bin/env bash
set -euo pipefail

K6_VERSION="0.55.0"

curl -sSfL \
  "https://github.com/grafana/k6/releases/download/v${K6_VERSION}/k6-v${K6_VERSION}-linux-amd64.tar.gz" \
  -o /tmp/k6.tar.gz

tar -xzf /tmp/k6.tar.gz -C /tmp
sudo mv "/tmp/k6-v${K6_VERSION}-linux-amd64/k6" /usr/local/bin/k6
sudo chmod +x /usr/local/bin/k6

k6 version
