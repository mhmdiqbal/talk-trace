import array
import math
import os
import subprocess
import sys
import tempfile
import wave

src = sys.argv[1]
with tempfile.TemporaryDirectory() as tmp:
    wav = os.path.join(tmp, "energy.wav")
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", "LEI16", src, wav],
        check=True,
        capture_output=True,
    )
    with wave.open(wav) as w:
        frames = w.readframes(w.getnframes())
        n = w.getnframes()
samples = array.array("h")
samples.frombytes(frames)
if not len(samples):
    print(f"{src}: EMPTY")
    sys.exit()
rms = math.sqrt(sum(s * s for s in samples) / len(samples))
peak = max(abs(s) for s in samples)
db = 20 * math.log10(rms / 32768) if rms > 0 else -999
print(f"{src}: {n / 48000:.1f}s  rms={rms:8.1f}  peak={peak:6d}  rms_dbfs={db:7.1f}")
