import array
import cmath
import math
import os
import subprocess
import sys
import tempfile
import wave

src = sys.argv[1]
with tempfile.TemporaryDirectory() as tmp:
    wav = os.path.join(tmp, "spec.wav")
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", "LEI16", src, wav],
        check=True,
        capture_output=True,
    )
    with wave.open(wav) as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        w.readframes(sr)  # skip 1 s of start-up
        raw = w.readframes(4096)
s = array.array("h")
s.frombytes(raw)
mono = [s[i * ch] / 32768.0 for i in range(len(s) // ch)]
N = 2048
if len(mono) < N:
    print(f"{src}: too short")
    sys.exit()
mono = mono[:N]
win = [mono[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (N - 1))) for i in range(N)]
best = []
for k in range(1, N // 2):
    acc = sum(win[n] * cmath.exp(-2j * math.pi * k * n / N) for n in range(N))
    best.append((abs(acc), k * sr / N))
best.sort(reverse=True)
print(
    f"{src}: sr={sr} top peaks -> "
    + ", ".join(f"{f:.0f}Hz({m:.1f})" for m, f in best[:4])
)
