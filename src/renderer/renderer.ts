import type { UiState } from "../main/protocol";
import type { TalkTraceApi } from "../preload/preload";

declare global {
  interface Window {
    talkTrace: TalkTraceApi;
  }
}

const FLOOR_DB = -60;
const CLIP_FRACTION = 0.97;
const PEAK_FALL_PER_SECOND = 0.55;

function el(id: string): HTMLElement {
  const node = document.getElementById(id);
  if (!node) throw new Error(`missing element #${id}`);
  return node;
}

const nodes = {
  root: el("root"),
  takeover: el("takeover"),
  takeoverText: el("takeoverText"),
  takeoverAction: el("takeoverAction") as HTMLButtonElement,
  body: el("body"),
  start: el("start") as HTMLButtonElement,
  status: el("status"),
  statusLabel: el("statusLabel"),
  timer: el("timer"),
  meters: el("meters"),
  systemBar: el("systemBar"),
  systemPeak: el("systemPeak"),
  micBar: el("micBar"),
  micPeak: el("micPeak"),
  transport: el("transport"),
  pause: el("pause") as HTMLButtonElement,
  stop: el("stop") as HTMLButtonElement,
  micRow: el("micRow") as HTMLButtonElement,
  micName: el("micName"),
  micNote: el("micNote"),
  micNoteAction: el("micNoteAction") as HTMLButtonElement,
  output: el("output"),
  message: el("message"),
  hotkey: el("hotkey"),
  reveal: el("reveal") as HTMLButtonElement,
  quit: el("quit") as HTMLButtonElement,
};

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function formatTime(total: number): string {
  const whole = Math.max(0, Math.floor(total));
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor((whole % 3600) / 60);
  const seconds = whole % 60;
  const mm = hours > 0 ? String(minutes).padStart(2, "0") : String(minutes);
  const pad = String(seconds).padStart(2, "0");
  return hours > 0 ? `${String(hours)}:${mm}:${pad}` : `${mm}:${pad}`;
}

// Levels arrive as a linear peak. A dB scale makes the bar move the way an
// audio meter is expected to move.
function meterFraction(peak: number): number {
  if (peak <= 0) return 0;
  const db = 20 * Math.log10(peak);
  return Math.max(0, Math.min(1, (db - FLOOR_DB) / -FLOOR_DB));
}

// MARK: peak hold. The only renderer state that is not pushed from main.

const held = { system: 0, mic: 0 };
let peakFrame: number | null = null;
let peakLastAt = 0;

function drawPeaks(now: number): void {
  const step = peakLastAt === 0 ? 0 : (now - peakLastAt) / 1000;
  peakLastAt = now;
  for (const key of ["system", "mic"] as const) {
    held[key] = Math.max(0, held[key] - PEAK_FALL_PER_SECOND * step);
    const tick = key === "system" ? nodes.systemPeak : nodes.micPeak;
    tick.hidden = held[key] <= 0.01;
    tick.style.left = `${String(held[key] * 100)}%`;
  }
  peakFrame = requestAnimationFrame(drawPeaks);
}

function startPeakLoop(): void {
  if (peakFrame !== null || reducedMotion.matches) return;
  peakLastAt = 0;
  peakFrame = requestAnimationFrame(drawPeaks);
}

function stopPeakLoop(): void {
  if (peakFrame !== null) cancelAnimationFrame(peakFrame);
  peakFrame = null;
  held.system = 0;
  held.mic = 0;
  nodes.systemPeak.hidden = true;
  nodes.micPeak.hidden = true;
}

// MARK: render

// Only a missing screen grant blocks recording. The helper drops the mic and
// records system audio on its own when the mic grant is missing, so that is a
// note, not a wall.
function renderTakeover(state: UiState): boolean {
  if (state.screenPermission) return false;
  nodes.takeoverText.innerHTML =
    "<strong>Screen Recording is off.</strong> TalkTrace needs it to capture what your Mac plays. No picture is saved.";
  nodes.takeoverAction.textContent = "Open Screen Recording settings";
  nodes.takeoverAction.onclick = () => void window.talkTrace.openPermission("screen");
  return true;
}

function renderMeters(state: UiState): void {
  const bars = [
    { fill: nodes.systemBar, key: "system" as const, level: state.systemLevel },
    { fill: nodes.micBar, key: "mic" as const, level: state.micLevel },
  ];
  for (const bar of bars) {
    const fraction = meterFraction(bar.level);
    bar.fill.style.width = `${String(fraction * 100)}%`;
    bar.fill.classList.toggle("clipping", fraction >= CLIP_FRACTION);
    held[bar.key] = Math.max(held[bar.key], fraction);
  }
}

function render(state: UiState): void {
  const recording = state.state !== "idle";
  nodes.root.dataset.state = state.state;
  document.documentElement.style.setProperty("--accent", state.accentColor);
  document.body.dataset.reducedTransparency = String(state.reducedTransparency);

  const blocked = renderTakeover(state);
  nodes.takeover.hidden = !blocked;
  nodes.body.hidden = blocked;

  nodes.start.hidden = recording;
  nodes.status.hidden = !recording;
  nodes.meters.hidden = !recording;
  nodes.transport.hidden = !recording;

  nodes.statusLabel.textContent = state.state === "paused" ? "Paused" : "Recording";
  nodes.timer.textContent = formatTime(state.elapsedSeconds);
  nodes.pause.textContent = state.state === "paused" ? "Resume" : "Pause";

  renderMeters(state);
  if (recording && !blocked) startPeakLoop();
  else stopPeakLoop();

  const selected = state.mics.find((mic) => mic.id === state.selectedMicID);
  nodes.micName.textContent = selected ? selected.name : "System default";
  nodes.micNote.hidden = state.micPermission;

  nodes.output.textContent = state.currentOutput;
  nodes.hotkey.textContent = state.hotkey;
  nodes.hotkey.classList.toggle("taken", !state.hotkeyRegistered);
  nodes.hotkey.title = state.hotkeyRegistered ? "" : `${state.hotkey} is taken by another app`;

  nodes.message.textContent = state.message ?? "";
  nodes.message.hidden = !state.message;
}

nodes.start.addEventListener("click", () => void window.talkTrace.toggleRecording());
nodes.stop.addEventListener("click", () => void window.talkTrace.toggleRecording());
nodes.pause.addEventListener("click", () => void window.talkTrace.togglePause());
nodes.micRow.addEventListener("click", () => void window.talkTrace.openMicMenu());
nodes.micNoteAction.addEventListener("click", () => void window.talkTrace.openPermission("mic"));
nodes.reveal.addEventListener("click", () => void window.talkTrace.revealLastFile());
nodes.quit.addEventListener("click", () => void window.talkTrace.quit());

window.talkTrace.onState(render);
void window.talkTrace.getState().then(render);
