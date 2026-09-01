type Actions = {
  toggleRecording: () => void;
  togglePause: () => void;
  snapshot: () => unknown;
};

/// Drives the real start/pause/resume/stop path so the Electron side can be
/// tested without a human pressing keys. Enabled by RECORDER_SELFTEST=1 only.
export function runSelfTest(actions: Actions): void {
  const step = (afterMs: number, label: string, body: () => void) =>
    setTimeout(() => {
      process.stderr.write(`[selftest] ${label}\n`);
      body();
    }, afterMs);

  const recordMs = Number(process.env.RECORDER_SELFTEST_SECONDS ?? 12) * 1000;
  const pauseMs = recordMs >= 60_000 ? 0 : 4000;
  const half = Math.round(recordMs / 2);

  step(1500, "start", actions.toggleRecording);
  if (pauseMs > 0) {
    step(1500 + half, "pause", actions.togglePause);
    step(1500 + half + pauseMs, "resume", actions.togglePause);
  }
  step(1500 + recordMs + pauseMs, "stop", actions.toggleRecording);
  step(3500 + recordMs + pauseMs, "snapshot", () => {
    process.stderr.write(`[selftest] state ${JSON.stringify(actions.snapshot())}\n`);
    process.stderr.write("[selftest] done\n");
  });
}
