import { contextBridge, ipcRenderer } from "electron";
import type { UiState } from "../main/protocol";

const api = {
  getState: (): Promise<UiState> => ipcRenderer.invoke("ui:getState"),
  toggleRecording: (): Promise<void> => ipcRenderer.invoke("ui:toggleRecording"),
  togglePause: (): Promise<void> => ipcRenderer.invoke("ui:togglePause"),
  toggleMicMute: (): Promise<void> => ipcRenderer.invoke("ui:toggleMicMute"),
  selectMic: (enabled: boolean, micID: string | null): Promise<void> =>
    ipcRenderer.invoke("ui:selectMic", enabled, micID),
  openPermission: (which: "screen" | "mic"): Promise<void> =>
    ipcRenderer.invoke("ui:openPermission", which),
  openMicMenu: (): Promise<void> => ipcRenderer.invoke("ui:openMicMenu"),
  revealLastFile: (): Promise<void> => ipcRenderer.invoke("ui:revealLastFile"),
  quit: (): Promise<void> => ipcRenderer.invoke("ui:quit"),
  onState: (handler: (state: UiState) => void): void => {
    ipcRenderer.on("ui:state", (_event, state: UiState) => { handler(state); });
  },
};

export type TalkTraceApi = typeof api;

contextBridge.exposeInMainWorld("talkTrace", api);
