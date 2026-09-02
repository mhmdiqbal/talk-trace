export type MicDevice = { id: string; name: string };

export type RecorderState = "idle" | "recording" | "paused";

export type Command =
  | { cmd: "permissions" }
  | { cmd: "listDevices" }
  | {
      cmd: "start";
      path: string;
      micDeviceID?: string;
      includeMic?: boolean;
      sampleRate?: number;
      bitrate?: number;
    }
  | { cmd: "pause" }
  | { cmd: "resume" }
  | { cmd: "stop" }
  | { cmd: "muteMic"; muted: boolean };

export type HelperEvent =
  | { ev: "ready"; pid: number }
  | { ev: "permissions"; screen: boolean; mic: boolean }
  | { ev: "devices"; mics: MicDevice[]; currentOutput: string }
  | { ev: "started"; path: string; mic: boolean }
  | { ev: "level"; system: number; mic: number }
  | { ev: "state"; state: RecorderState }
  | { ev: "micMuted"; muted: boolean }
  | {
      ev: "stopped";
      path: string;
      seconds: number;
      bytes: number;
      micFramesMixed: number;
    }
  | { ev: "warning"; code: string; message: string }
  | { ev: "error"; code: string; message: string };

/** What the popup renders from. The main process owns it. */
export type UiState = {
  state: RecorderState;
  screenPermission: boolean;
  micPermission: boolean;
  mics: MicDevice[];
  selectedMicID: string | null;
  micEnabled: boolean;
  micMuted: boolean;
  currentOutput: string;
  systemLevel: number;
  micLevel: number;
  elapsedSeconds: number;
  hotkey: string;
  hotkeyRegistered: boolean;
  muteHotkey: string;
  muteHotkeyRegistered: boolean;
  lastFile: string | null;
  message: string | null;
  accentColor: string;
  reducedTransparency: boolean;
};
