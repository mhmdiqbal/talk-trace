#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolve_identity() {
  local id="${TALKTRACE_IDENTITY:-${RECORDER_IDENTITY:-}}"
  if [[ -n "$id" ]]; then
    echo "$id"
    return
  fi

  local detected
  detected="$(security find-identity -v -p codesigning 2>/dev/null | grep -E '"(Apple Development|Developer ID Application):' | head -1 | sed -E 's/.*"((Apple Development|Developer ID Application): .*)".*/\1/' || true)"

  if [[ -n "$detected" ]]; then
    echo "$detected"
  else
    echo "-"
  fi
}

IDENTITY="$(resolve_identity)"
if [[ "$IDENTITY" = "-" ]]; then
  echo "Notice: No Apple Development identity found in Keychain; using ad-hoc (-) signing."
  echo "        Set TALKTRACE_IDENTITY=\"...\" to sign with a specific certificate."
else
  echo "Signing helper with identity: $IDENTITY"
fi
PLIST="$ROOT/build/helper-Info.plist"
ENTITLEMENTS="$ROOT/build/entitlements.mac.plist"

cd "$ROOT/native/TalkTraceHelper"
swift build -c release --arch arm64 \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PLIST"

BINARY="$(swift build -c release --arch arm64 --show-bin-path)/TalkTraceHelper"

codesign --force --timestamp=none --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --identifier com.mmdiqbal.talktrace.helper \
  --sign "$IDENTITY" \
  "$BINARY"

mkdir -p "$ROOT/resources"
cp "$BINARY" "$ROOT/resources/TalkTraceHelper"
echo "helper -> $ROOT/resources/TalkTraceHelper"
codesign -dv "$ROOT/resources/TalkTraceHelper" 2>&1 | grep -E "Identifier|Authority|Signature" | head -4
