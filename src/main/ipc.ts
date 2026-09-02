import { ipcMain, shell, app, type BrowserWindow } from "electron";
import { openMicMenu } from "./micMenu";
import { recordingsDir } from "./paths";
import type { UiState } from "./protocol";

export const SETTINGS_URLS = {
  screen:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
  mic: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
} as const;

export type IpcActions = {
  getUiState: () => UiState;
  getPopup: () => BrowserWindow | null;
  toggleRecording: () => void;
  togglePause: () => void;
  toggleMicMute: () => void;
  pickMic: (enabled: boolean, micID: string | null) => void;
  onMenuOpenChange: (open: boolean) => void;
};

export function registerIpc(actions: IpcActions): void {
  ipcMain.handle("ui:getState", () => actions.getUiState());
  ipcMain.handle("ui:toggleRecording", () => { actions.toggleRecording(); });
  ipcMain.handle("ui:togglePause", () => { actions.togglePause(); });
  ipcMain.handle("ui:toggleMicMute", () => { actions.toggleMicMute(); });
  ipcMain.handle("ui:selectMic", (_event, enabled: boolean, micID: string | null) => {
    actions.pickMic(enabled, micID);
  });
  ipcMain.handle("ui:openPermission", (_event, which: "screen" | "mic") =>
    shell.openExternal(SETTINGS_URLS[which]),
  );
  ipcMain.handle("ui:openMicMenu", () => {
    const window = actions.getPopup();
    if (!window) return;
    const ui = actions.getUiState();
    openMicMenu({
      window,
      mics: ui.mics,
      selectedMicID: ui.selectedMicID,
      micEnabled: ui.micEnabled,
      onPick: actions.pickMic,
      onOpenChange: (open) => {
        actions.onMenuOpenChange(open);
        if (!open) actions.getPopup()?.focus();
      },
    });
  });
  ipcMain.handle("ui:revealLastFile", () => {
    const { lastFile } = actions.getUiState();
    if (lastFile) shell.showItemInFolder(lastFile);
    else void shell.openPath(recordingsDir());
  });
  ipcMain.handle("ui:quit", () => { app.quit(); });
}
