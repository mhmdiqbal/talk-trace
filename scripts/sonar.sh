#!/usr/bin/env bash
# Runs a SonarQube scan of this repo against the local server.
# Starts the containers first. Does not fail on a red quality gate.

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v sonar-scanner >/dev/null 2>&1; then
  echo "Error: sonar-scanner is not installed. Fix with: brew install sonar-scanner" >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "Error: .env is missing. Create it with: SONAR_TOKEN=<your token>" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091 # .env is gitignored and not present at lint time
source .env
set +a

if [[ -z "${SONAR_TOKEN:-}" ]]; then
  echo "Error: SONAR_TOKEN is empty in .env." >&2
  echo "Make a token at http://localhost:9000 under My Account > Security." >&2
  exit 1
fi

./scripts/sonarqube.sh start

echo "==> sonar-scanner"
version="$(node -p "require('./package.json').version")"
sonar-scanner -Dsonar.token="$SONAR_TOKEN" -Dsonar.projectVersion="$version"

echo
echo "Dashboard: http://localhost:9000/dashboard?id=record-app"
