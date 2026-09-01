#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${RECORDER_IDENTITY:-Apple Development: Muhamad Iqbal (2KL7MN2RPU)}"
PLIST="$ROOT/build/helper-Info.plist"
ENTITLEMENTS="$ROOT/build/entitlements.mac.plist"

cd "$ROOT/native/RecorderHelper"
swift build -c release --arch arm64 \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST"

BINARY="$(swift build -c release --arch arm64 --show-bin-path)/RecorderHelper"

codesign --force --timestamp=none --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --identifier com.mmdiqbal.recorder.helper \
  --sign "$IDENTITY" \
  "$BINARY"

mkdir -p "$ROOT/resources"
cp "$BINARY" "$ROOT/resources/RecorderHelper"
echo "helper -> $ROOT/resources/RecorderHelper"
codesign -dv "$ROOT/resources/RecorderHelper" 2>&1 | grep -E "Identifier|Authority|Signature" | head -4
