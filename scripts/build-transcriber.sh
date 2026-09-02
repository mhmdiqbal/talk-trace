#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolve_identity() {
  local id="${TALKTRACE_IDENTITY:-${RECORDER_IDENTITY:-}}"
  if [ -n "$id" ]; then
    echo "$id"
    return
  fi

  local detected
  detected="$(security find-identity -v -p codesigning 2>/dev/null | grep -E '"(Apple Development|Developer ID Application):' | head -1 | sed -E 's/.*"((Apple Development|Developer ID Application): .*)".*/\1/' || true)"

  if [ -n "$detected" ]; then
    echo "$detected"
  else
    echo "-"
  fi
}

IDENTITY="$(resolve_identity)"
if [ "$IDENTITY" = "-" ]; then
  echo "Notice: No Apple Development identity found in Keychain; using ad-hoc (-) signing."
  echo "        Set TALKTRACE_IDENTITY=\"...\" to sign with a specific certificate."
else
  echo "Signing transcriber with identity: $IDENTITY"
fi
ENTITLEMENTS="$ROOT/build/entitlements.mac.plist"

"$ROOT/scripts/build-whisper.sh"

cd "$ROOT/native/TalkTraceTranscriber"
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BINARY="$BIN_DIR/TalkTraceTranscriber"

# SwiftPM does not track the whisper archives, so a rebuilt whisper leaves a
# stale executable behind. Drop it to force a relink.
rm -f "$BINARY"
swift build -c release --arch arm64

# No -sectcreate Info.plist here. Unlike the audio helper this binary only reads
# a file, so it needs no Screen Recording or Microphone grant and therefore no
# code identity of its own for TCC to key on.
codesign --force --timestamp=none --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --identifier com.mmdiqbal.talktrace.transcriber \
  --sign "$IDENTITY" \
  "$BINARY"

mkdir -p "$ROOT/resources"
cp "$BINARY" "$ROOT/resources/TalkTraceTranscriber"
echo "transcriber -> $ROOT/resources/TalkTraceTranscriber"
codesign -dv "$ROOT/resources/TalkTraceTranscriber" 2>&1 | grep -E "Identifier|Authority|Signature" | head -4
