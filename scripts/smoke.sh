#!/bin/bash
# Drives the helper over a FIFO so stdin stays open. $1 = out file, $2 = extra start fields
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-/tmp/t.m4a}"
EXTRA="${2:-}"
FIFO=$(mktemp -u /tmp/rec.XXXXXX.fifo)
mkfifo "$FIFO"
rm -f "$OUT"

"$ROOT/resources/RecorderHelper" < "$FIFO" | grep --line-buffered -v '"ev":"level"' &
HELPER=$!
exec 3>"$FIFO"

echo "{\"cmd\":\"start\",\"path\":\"$OUT\",\"sampleRate\":48000,\"bitrate\":128000$EXTRA}" >&3
sleep 1
for s in Glass Ping Submarine Hero Glass Ping; do
  afplay "/System/Library/Sounds/$s.aiff" 2>/dev/null
done
sleep 1
echo '{"cmd":"stop"}' >&3
sleep 1
kill -TERM "$HELPER" 2>/dev/null
exec 3>&-
wait "$HELPER" 2>/dev/null
rm -f "$FIFO"
echo "--- afinfo ---"
afinfo "$OUT" 2>&1 | grep -Ei "file type|data format|duration|bit rate|channels" | head -6
