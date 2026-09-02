import path from "node:path";
import {
  app,
  BrowserWindow,
  globalShortcut,
  ipcMain,
  nativeImage,
  nativeTheme,
  powerSaveBlocker,
  shell,
  systemPreferences,
  Tray,
} from "electron";
import { Helper } from "./helper";
import { formatSeconds, helperExitMessage } from "./messages";
import { openMicMenu } from "./micMenu";
import { newRecordingPath, recordingsDir } from "./paths";
import { runSelfTest } from "./selftest";
import * as settings from "./settings";
import * as transcribe from "./transcribe";
import type { HelperEvent, UiState } from "./protocol";

const HOTKEY = "Alt+Command+R";
const MAX_RESPAWNS = 5;
const SHUTDOWN_GRACE_MS = 5000;
const POPUP_WIDTH = 300;
const POPUP_HEIGHT_IDLE = 168;
const POPUP_HEIGHT_BLOCKED = 208;
const POPUP_HEIGHT_ACTIVE = 238;
const POPUP_HEIGHT_MESSAGE_EXTRA = 38;
const POPUP_HEIGHT_MIC_NOTE_EXTRA = 34;
const FALLBACK_ACCENT = "#007aff";

const SETTINGS_URLS = {
  screen:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
  mic: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
} as const;

const helper = new Helper();
let tray: Tray | null = null;
let popup: BrowserWindow | null = null;
let blockerId: number | null = null;
let ticker: NodeJS.Timeout | null = null;

let recordedMs = 0;
let segmentStartedAt: number | null = null;
let shownAt = 0;
let respawnAttempts = 0;
let respawnTimer: NodeJS.Timeout | null = null;
let quitting = false;
let shutdownDone = false;
let menuOpen = false;
let appliedHeight = 0;

const ui: UiState = {
  state: "idle",
  screenPermission: false,
  micPermission: false,
  mics: [],
  selectedMicID: settings.load().selectedMicID,
  currentOutput: "",
  systemLevel: 0,
  micLevel: 0,
  elapsedSeconds: 0,
  hotkey: "⌥⌘R",
  hotkeyRegistered: false,
  lastFile: null,
  message: null,
  accentColor: FALLBACK_ACCENT,
  reducedTransparency: false,
};

// getAccentColor returns RGBA hex with no leading "#", e.g. "007AFFFF".
// That is a different channel order from BrowserWindow backgroundColor.
function readAccentColor(): string {
  try {
    const rgba = systemPreferences.getAccentColor();
    return /^[0-9a-f]{6,8}$/i.test(rgba) ? `#${rgba.slice(0, 6)}` : FALLBACK_ACCENT;
  } catch {
    return FALLBACK_ACCENT;
  }
}

function resource(name: string): string {
  return app.isPackaged
    ? path.join(process.resourcesPath, name)
    : path.join(app.getAppPath(), "resources", name);
}

// A destroyed BrowserWindow keeps its JS reference, so `popup` alone is not a
// liveness check. Every use goes through this.
function livePopup(): BrowserWindow | null {
  return popup && !popup.isDestroyed() ? popup : null;
}

// Mirrors the views the renderer can show. Only a missing Screen Recording
// grant takes over the popup; the helper still records system audio when the
// mic is denied, so that stays an inline note over the normal body.
function popupHeight(): number {
  const messageExtra = ui.message ? POPUP_HEIGHT_MESSAGE_EXTRA : 0;
  if (!ui.screenPermission) return POPUP_HEIGHT_BLOCKED + messageExtra;
  const base = ui.state === "idle" ? POPUP_HEIGHT_IDLE : POPUP_HEIGHT_ACTIVE;
  const micNoteExtra = ui.micPermission ? 0 : POPUP_HEIGHT_MIC_NOTE_EXTRA;
  return base + messageExtra + micNoteExtra;
}

// pushState runs on every level event, so resize only on a real change or the
// macOS resize animation restarts ten times a second.
function syncPopupHeight(): void {
  const window = livePopup();
  if (!window) return;
  const height = popupHeight();
  if (height === appliedHeight) return;
  appliedHeight = height;
  const { x, y } = window.getBounds();
  window.setBounds({ x, y, width: POPUP_WIDTH, height }, window.isVisible());
}

function pushState(): void {
  syncPopupHeight();
  livePopup()?.webContents.send("ui:state", ui);
}

function setTrayIcon(): void {
  if (!tray || tray.isDestroyed()) return;
  const recording = ui.state !== "idle";
  const icon = nativeImage.createFromPath(
    resource(recording ? "trayRecording.png" : "trayTemplate.png"),
  );
  icon.setTemplateImage(!recording);
  tray.setImage(icon);
  tray.setToolTip(recording ? "TalkTrace — recording" : "TalkTrace");
}

// MARK: elapsed time. Pause removes the gap, so we count recorded time only.

function elapsedSeconds(): number {
  const live = segmentStartedAt ? Date.now() - segmentStartedAt : 0;
  return (recordedMs + live) / 1000;
}

function startTicker(): void {
  if (ticker) return;
  ticker = setInterval(() => {
    ui.elapsedSeconds = elapsedSeconds();
    pushState();
  }, 250);
}

function stopTicker(): void {
  if (!ticker) return;
  clearInterval(ticker);
  ticker = null;
}

function blockSleep(on: boolean): void {
  if (on && blockerId === null) {
    blockerId = powerSaveBlocker.start("prevent-app-suspension");
    return;
  }
  if (!on && blockerId !== null) {
    powerSaveBlocker.stop(blockerId);
    blockerId = null;
  }
}

// MARK: commands the UI can trigger

function toggleRecording(): void {
  if (ui.state === "idle") {
    if (!ui.screenPermission) {
      showPopup();
      return;
    }
    ui.message = null;
    helper.send({
      cmd: "start",
      path: newRecordingPath(),
      includeMic: true,
      ...(ui.selectedMicID ? { micDeviceID: ui.selectedMicID } : {}),
      sampleRate: 48000,
      bitrate: 128000,
    });
    return;
  }
  helper.send({ cmd: "stop" });
}

function togglePause(): void {
  if (ui.state === "recording") helper.send({ cmd: "pause" });
  else if (ui.state === "paused") helper.send({ cmd: "resume" });
}

// MARK: helper events

function onHelperEvent(event: HelperEvent): void {
  const debug = process.env.TALKTRACE_DEBUG ?? process.env.RECORDER_DEBUG;
  if (debug && event.ev !== "level") {
    process.stderr.write(`[event] ${JSON.stringify(event)}\n`);
  }

  switch (event.ev) {
    case "ready":
      helper.send({ cmd: "permissions" });
      helper.send({ cmd: "listDevices" });
      break;

    case "permissions":
      ui.screenPermission = event.screen;
      ui.micPermission = event.mic;
      break;

    case "devices":
      ui.mics = event.mics;
      ui.currentOutput = event.currentOutput;
      if (!ui.mics.some((mic) => mic.id === ui.selectedMicID)) {
        ui.selectedMicID = null;
      }
      break;

    case "started":
      respawnAttempts = 0;
      ui.lastFile = event.path;
      recordedMs = 0;
      segmentStartedAt = Date.now();
      blockSleep(true);
      startTicker();
      break;

    case "state":
      applyState(event.state);
      break;

    case "level":
      ui.systemLevel = event.system;
      ui.micLevel = event.mic;
      break;

    case "stopped":
      ui.lastFile = event.path;
      ui.elapsedSeconds = event.seconds;
      recordedMs = 0;
      ui.message = `Saved ${formatSeconds(event.seconds)} to ${path.basename(event.path)}`;
      transcribe.enqueue(event.path);
      break;

    case "warning":
      ui.message = event.message;
      break;

    case "error":
      ui.message = event.message;
      if (event.code === "noScreenPermission") ui.screenPermission = false;
      if (event.code === "noMicPermission") ui.micPermission = false;
      break;
  }
  pushState();
}

function onHelperExit(code: number | null, signal: string | null): void {
  const wasRecording = ui.state !== "idle";
  ui.state = "idle";
  blockSleep(false);
  stopTicker();
  setTrayIcon();

  if (quitting) return;

  respawnAttempts += 1;
  const giveUp = respawnAttempts > MAX_RESPAWNS;
  ui.message = helperExitMessage(giveUp, wasRecording, code, signal);
  pushState();

  if (giveUp) return;
  // Back off so a crash loop cannot spin once a second forever.
  const delay = Math.min(1000 * 2 ** (respawnAttempts - 1), 30_000);
  respawnTimer = setTimeout(() => { helper.start(); }, delay);
}

function pickMic(micID: string | null): void {
  ui.selectedMicID = micID;
  settings.save({ selectedMicID: micID });
  pushState();
}

function applyState(state: UiState["state"]): void {
  ui.state = state;
  if (state === "paused" && segmentStartedAt !== null) {
    recordedMs += Date.now() - segmentStartedAt;
    segmentStartedAt = null;
  }
  if (state === "recording" && segmentStartedAt === null) {
    segmentStartedAt = Date.now();
  }
  if (state === "idle") {
    segmentStartedAt = null;
    ui.systemLevel = 0;
    ui.micLevel = 0;
    blockSleep(false);
    stopTicker();
  }
  // Whisper takes every core and the GPU. Audio always wins.
  if (state === "idle") transcribe.resume();
  else transcribe.suspend();
  setTrayIcon();
}

// MARK: window and tray

function createPopup(): BrowserWindow {
  const window = new BrowserWindow({
    width: POPUP_WIDTH,
    height: POPUP_HEIGHT_IDLE,
    show: false,
    frame: false,
    resizable: false,
    fullscreenable: false,
    movable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    vibrancy: "popover",
    visualEffectState: "active",
    webPreferences: {
      preload: path.join(__dirname, "..", "preload", "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  void window.loadFile(path.join(__dirname, "..", "renderer", "index.html"));
  window.on("blur", () => {
    // A native Menu takes key focus, so without this the popup hides itself
    // the moment the mic menu opens.
    if (menuOpen) return;
    if (Date.now() - shownAt < 250) return;
    window.hide();
  });
  window.on("closed", () => {
    popup = null;
  });
  return window;
}

function positionPopup(window: BrowserWindow): void {
  if (!tray || tray.isDestroyed()) return;
  const iconBounds = tray.getBounds();
  const x = Math.round(iconBounds.x + iconBounds.width / 2 - POPUP_WIDTH / 2);
  const y = Math.round(iconBounds.y + iconBounds.height + 4);
  appliedHeight = popupHeight();
  window.setBounds({ x, y, width: POPUP_WIDTH, height: appliedHeight });
}

function showPopup(): void {
  const window = livePopup();
  if (!window) return;
  helper.send({ cmd: "permissions" });
  helper.send({ cmd: "listDevices" });
  positionPopup(window);
  shownAt = Date.now();
  window.show();
  window.focus();
}

function togglePopup(): void {
  const window = livePopup();
  if (!window) return;
  if (window.isVisible()) {
    window.hide();
    return;
  }
  showPopup();
}

function registerIpc(): void {
  ipcMain.handle("ui:getState", () => ui);
  ipcMain.handle("ui:toggleRecording", () => { toggleRecording(); });
  ipcMain.handle("ui:togglePause", () => { togglePause(); });
  ipcMain.handle("ui:selectMic", (_event, micID: string | null) => { pickMic(micID); });
  ipcMain.handle("ui:openPermission", (_event, which: "screen" | "mic") =>
    shell.openExternal(SETTINGS_URLS[which]),
  );
  ipcMain.handle("ui:openMicMenu", () => {
    const window = livePopup();
    if (!window) return;
    openMicMenu({
      window,
      mics: ui.mics,
      selectedMicID: ui.selectedMicID,
      onPick: pickMic,
      onOpenChange: (open) => {
        menuOpen = open;
        if (!open) livePopup()?.focus();
      },
    });
  });
  ipcMain.handle("ui:revealLastFile", () => {
    if (ui.lastFile) shell.showItemInFolder(ui.lastFile);
    else void shell.openPath(recordingsDir());
  });
  ipcMain.handle("ui:quit", () => { app.quit(); });
}

// MARK: startup

void app.whenReady().then(() => {
  app.dock.hide();

  const icon = nativeImage.createFromPath(resource("trayTemplate.png"));
  icon.setTemplateImage(true);
  tray = new Tray(icon);
  tray.setToolTip("TalkTrace");
  tray.on("click", togglePopup);
  tray.on("right-click", togglePopup);

  ui.accentColor = readAccentColor();
  ui.reducedTransparency = nativeTheme.prefersReducedTransparency;

  popup = createPopup();

  helper.on("event", onHelperEvent);
  helper.on("exit", ({ code, signal }: { code: number | null; signal: string | null }) => {
    onHelperExit(code, signal);
  });
  helper.start();

  transcribe.start({
    onMessage: (text) => {
      ui.message = text;
      pushState();
    },
  });

  ui.hotkeyRegistered = globalShortcut.register(HOTKEY, toggleRecording);
  if (!ui.hotkeyRegistered) {
    ui.message = `The hotkey ${ui.hotkey} is already taken by another app.`;
  }

  registerIpc();

  const selftest =
    process.env.TALKTRACE_SELFTEST ?? process.env.RECORDER_SELFTEST;
  if (selftest === "1") {
    runSelfTest({
      toggleRecording,
      togglePause,
      snapshot: () => ({
        state: ui.state,
        elapsedSeconds: Number(ui.elapsedSeconds.toFixed(2)),
        lastFile: ui.lastFile,
        message: ui.message,
      }),
    });
  }
});

app.on("window-all-closed", () => {
  // A menu bar app stays alive with no windows open.
});

// Quitting has to be graceful. A signal-based shutdown left the .m4a without
// its index and unplayable, so we ask the helper to stop and wait for it to
// confirm before the process goes away.
app.on("before-quit", (event) => {
  if (shutdownDone) return;
  event.preventDefault();
  quitting = true;
  if (respawnTimer) clearTimeout(respawnTimer);
  globalShortcut.unregisterAll();
  blockSleep(false);
  stopTicker();

  const finish = () => {
    if (shutdownDone) return;
    shutdownDone = true;
    tray?.destroy();
    tray = null;
    transcribe.kill();
    helper.kill();
    app.quit();
  };

  if (!helper.running || ui.state === "idle") {
    finish();
    return;
  }

  helper.once("exit", finish);
  const onEvent = (helperEvent: HelperEvent) => {
    if (helperEvent.ev === "stopped" || helperEvent.ev === "error") finish();
  };
  helper.on("event", onEvent);
  setTimeout(finish, SHUTDOWN_GRACE_MS);
  helper.send({ cmd: "stop" });
});
