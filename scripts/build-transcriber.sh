#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${RECORDER_IDENTITY:-Apple Development: Muhamad Iqbal (2KL7MN2RPU)}"
ENTITLEMENTS="$ROOT/build/entitlements.mac.plist"

"$ROOT/scripts/build-whisper.sh"

cd "$ROOT/native/RecorderTranscriber"
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BINARY="$BIN_DIR/RecorderTranscriber"

# SwiftPM does not track the whisper archives, so a rebuilt whisper leaves a
# stale executable behind. Drop it to force a relink.
rm -f "$BINARY"
swift build -c release --arch arm64

# No -sectcreate Info.plist here. Unlike the audio helper this binary only reads
# a file, so it needs no Screen Recording or Microphone grant and therefore no
# code identity of its own for TCC to key on.
codesign --force --timestamp=none --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --identifier com.mmdiqbal.recorder.transcriber \
  --sign "$IDENTITY" \
  "$BINARY"

mkdir -p "$ROOT/resources"
cp "$BINARY" "$ROOT/resources/RecorderTranscriber"
echo "transcriber -> $ROOT/resources/RecorderTranscriber"
codesign -dv "$ROOT/resources/RecorderTranscriber" 2>&1 | grep -E "Identifier|Authority|Signature" | head -4
