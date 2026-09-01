#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "lint: $1 is not installed. Run: $2" >&2
    exit 1
  fi
}

need swift "install Xcode or the Swift toolchain"
need shellcheck "brew install shellcheck"
need ruff "brew install ruff"

echo "==> typecheck"
pnpm run typecheck

echo "==> eslint"
pnpm exec eslint .

echo "==> swift-format"
swift format lint --strict --recursive \
  --configuration "$ROOT/.swift-format" \
  native/RecorderHelper/Sources \
  native/RecorderTranscriber/Sources

echo "==> shellcheck"
shellcheck scripts/*.sh

echo "==> ruff"
ruff check scripts/
ruff format --check scripts/

echo "lint: all checks passed"
