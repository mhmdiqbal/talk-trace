#!/bin/bash
# Full regression against the installed /Applications/TalkTrace.app.
# Run scripts/build-helper.sh and `pnpm run dist` and install it first.
APP="${TALKTRACE_APP:-${RECORDER_APP:-/Applications/TalkTrace.app}}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0

check() {
  if [[ "$2" = "ok" ]]; then echo "  PASS  $1"; pass=$((pass+1));
  else echo "  FAIL  $1 ($2)"; fail=$((fail+1)); fi
}
duration() { afinfo "$1" 2>&1 | grep -i "estimated duration" | grep -oE "[0-9]+\.[0-9]+"; }
noise() { for s in Glass Ping Submarine Hero; do afplay "/System/Library/Sounds/$s.aiff" 2>/dev/null; done; }
run_app() {
  TALKTRACE_DEBUG=1 TALKTRACE_SELFTEST=1 TALKTRACE_SELFTEST_SECONDS="$1" \
    "$APP/Contents/MacOS/TalkTrace" > "$2" 2>&1 &
  echo $!
}
helper_record() {  # $1 = out file, returns after start
  FIFO=$(mktemp -u /tmp/reg.XXXX.fifo); mkfifo "$FIFO"; rm -f "$1"
  "$ROOT/resources/TalkTraceHelper" < "$FIFO" > /dev/null 2>&1 &
  exec 3>"$FIFO"
  echo "{\"cmd\":\"start\",\"path\":\"$1\",\"includeMic\":false}" >&3
}

echo "=== REGRESSION ==="

P=$(run_app 8 /tmp/reg1.log); sleep 3; noise; sleep 12
F=$(grep -o '/Users/[^"]*\.m4a' /tmp/reg1.log | head -1)
kill "$P" 2>/dev/null; sleep 2; pkill -f "TalkTrace.app/Contents" 2>/dev/null; sleep 1
D=$(duration "$F")
check "record/pause/resume/stop -> ${D:-none}s" "$([[ -n "$D" ]] && echo ok || echo 'no duration')"
COV=$(grep -o '"micFramesMixed":[0-9]*' /tmp/reg1.log | head -1 | cut -d: -f2)
check "mic mixed (${COV:-0} frames)" "$([[ "${COV:-0}" -gt 100000 ]] && echo ok || echo 'mic missing')"
check "pause gap removed" "$(awk -v d="${D:-0}" 'BEGIN{print (d>6 && d<10)?"ok":"got "d}')"
check "permissions granted" "$(grep -q '"screen":true' /tmp/reg1.log && grep -q '"mic":true' /tmp/reg1.log && echo ok || echo denied)"

P=$(run_app 60 /tmp/reg2.log); sleep 5; noise; sleep 2
F2=$(grep -o '/Users/[^"]*\.m4a' /tmp/reg2.log | head -1)
kill "$P" 2>/dev/null; sleep 8; pkill -f "TalkTrace.app/Contents" 2>/dev/null; sleep 1
check "kill mid-recording -> valid $(duration "$F2")s file" \
  "$([[ -n "$(duration "$F2")" ]] && echo ok || echo 'file corrupt')"
check "no orphan helpers" "$([[ "$(pgrep -f TalkTraceHelper | wc -l | tr -d ' ')" = "0" ]] && echo ok || echo 'orphans alive')"

helper_record /tmp/reg3.m4a; sleep 4
H=$(pgrep -f "resources/TalkTraceHelper" | head -1)
kill -TERM "$H"; kill -TERM "$H" 2>/dev/null; kill -TERM "$H" 2>/dev/null
sleep 3; exec 3>&-
check "triple SIGTERM -> valid file" "$(afinfo /tmp/reg3.m4a 2>&1 | grep -qi duration && echo ok || echo corrupt)"

helper_record /tmp/reg4.m4a; sleep 4
H=$(pgrep -f "resources/TalkTraceHelper" | head -1)
echo '{"cmd":"stop"}' >&3; kill -TERM "$H"
sleep 3; exec 3>&-
check "stop + immediate SIGTERM -> valid file" "$(afinfo /tmp/reg4.m4a 2>&1 | grep -qi duration && echo ok || echo corrupt)"

MODEL="$HOME/Library/Application Support/TalkTrace/models/ggml-small.en.bin"
if [[ ! -f "$MODEL" ]]; then
  echo "  SKIP  transcript (model not downloaded)"
else
  # The selftest above plays system sounds, not speech, so it correctly yields
  # no transcript at all. Drive the transcriber with known speech instead.
  say -o /tmp/reg-speech.aiff "The quick brown fox jumps over the lazy dog."
  afconvert -f m4af -d aac /tmp/reg-speech.aiff /tmp/reg-speech.m4a 2>/dev/null
  rm -f /tmp/reg-speech.srt
  "$ROOT/resources/TalkTraceTranscriber" --model "$MODEL" \
    --audio /tmp/reg-speech.m4a --out /tmp/reg-speech.srt >/tmp/reg-tr.log 2>&1
  check "transcript -> srt with times" \
    "$(grep -q -- '-->' /tmp/reg-speech.srt 2>/dev/null && echo ok || echo 'no srt')"
fi

pkill -TERM -f TalkTraceHelper 2>/dev/null
echo
echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
