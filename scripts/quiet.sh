#!/bin/bash
# Record with no system sound playing. $1 = out, $2 = extra start fields, $3 = seconds
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$1"; EXTRA="${2:-}"; SECS="${3:-6}"
FIFO=$(mktemp -u /tmp/rec.XXXXXX.fifo); mkfifo "$FIFO"; rm -f "$OUT"
"$ROOT/resources/RecorderHelper" < "$FIFO" | grep --line-buffered -E '"ev":"(started|stopped|error|warning)"' &
exec 3>"$FIFO"
echo "{\"cmd\":\"start\",\"path\":\"$OUT\",\"sampleRate\":48000,\"bitrate\":128000$EXTRA}" >&3
sleep "$SECS"
echo '{"cmd":"stop"}' >&3
sleep 1
exec 3>&-
rm -f "$FIFO"
