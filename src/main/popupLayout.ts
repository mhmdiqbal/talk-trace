import { systemPreferences } from "electron";
import type { UiState } from "./protocol";

export const POPUP_WIDTH = 300;
export const POPUP_HEIGHT_IDLE = 168;
export const POPUP_HEIGHT_BLOCKED = 208;
export const POPUP_HEIGHT_ACTIVE = 238;
export const POPUP_HEIGHT_MESSAGE_EXTRA = 38;
export const POPUP_HEIGHT_MIC_NOTE_EXTRA = 34;
export const FALLBACK_ACCENT = "#007aff";

// getAccentColor returns RGBA hex with no leading "#", e.g. "007AFFFF".
// That is a different channel order from BrowserWindow backgroundColor.
export function readAccentColor(): string {
  try {
    const rgba = systemPreferences.getAccentColor();
    return /^[0-9a-f]{6,8}$/i.test(rgba) ? `#${rgba.slice(0, 6)}` : FALLBACK_ACCENT;
  } catch {
    return FALLBACK_ACCENT;
  }
}

export function popupHeight(
  ui: Pick<UiState, "message" | "screenPermission" | "state" | "micPermission" | "micEnabled">,
): number {
  const messageExtra = ui.message ? POPUP_HEIGHT_MESSAGE_EXTRA : 0;
  if (!ui.screenPermission) return POPUP_HEIGHT_BLOCKED + messageExtra;
  const base = ui.state === "idle" ? POPUP_HEIGHT_IDLE : POPUP_HEIGHT_ACTIVE;
  const micNoteExtra = ui.micPermission || !ui.micEnabled ? 0 : POPUP_HEIGHT_MIC_NOTE_EXTRA;
  return base + messageExtra + micNoteExtra;
}
