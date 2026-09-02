import { systemPreferences } from "electron";
import { describe, expect, it, vi } from "vitest";
import {
  FALLBACK_ACCENT,
  POPUP_HEIGHT_ACTIVE,
  POPUP_HEIGHT_BLOCKED,
  POPUP_HEIGHT_IDLE,
  POPUP_HEIGHT_MESSAGE_EXTRA,
  POPUP_HEIGHT_MIC_NOTE_EXTRA,
  POPUP_WIDTH,
  popupHeight,
  readAccentColor,
} from "../src/main/popupLayout";

vi.mock("electron", () => ({
  systemPreferences: {
    getAccentColor: vi.fn(),
  },
}));

describe("popupLayout constants", () => {
  it("exports expected dimension and fallback constants", () => {
    expect(POPUP_WIDTH).toBe(300);
    expect(POPUP_HEIGHT_IDLE).toBe(168);
    expect(POPUP_HEIGHT_BLOCKED).toBe(208);
    expect(POPUP_HEIGHT_ACTIVE).toBe(238);
    expect(POPUP_HEIGHT_MESSAGE_EXTRA).toBe(38);
    expect(POPUP_HEIGHT_MIC_NOTE_EXTRA).toBe(34);
    expect(FALLBACK_ACCENT).toBe("#007aff");
  });
});

describe("readAccentColor", () => {
  it("converts 8-character RGBA hex to 6-character RGB hex with # prefix", () => {
    vi.mocked(systemPreferences.getAccentColor).mockReturnValue("007AFFFF");
    expect(readAccentColor()).toBe("#007AFF");
  });

  it("converts 6-character RGB hex with # prefix", () => {
    vi.mocked(systemPreferences.getAccentColor).mockReturnValue("FF3B30");
    expect(readAccentColor()).toBe("#FF3B30");
  });

  it("returns FALLBACK_ACCENT for invalid hex values", () => {
    vi.mocked(systemPreferences.getAccentColor).mockReturnValue("invalid");
    expect(readAccentColor()).toBe(FALLBACK_ACCENT);
  });

  it("returns FALLBACK_ACCENT if getAccentColor throws", () => {
    vi.mocked(systemPreferences.getAccentColor).mockImplementation(() => {
      throw new Error("System preferences unavailable");
    });
    expect(readAccentColor()).toBe(FALLBACK_ACCENT);
  });
});

describe("popupHeight", () => {
  it("calculates blocked base height when screen permission is missing", () => {
    const height = popupHeight({
      screenPermission: false,
      message: null,
      state: "idle",
      micPermission: true,
      micEnabled: true,
    });
    expect(height).toBe(POPUP_HEIGHT_BLOCKED);
  });

  it("adds message extra to blocked base height when message is present", () => {
    const height = popupHeight({
      screenPermission: false,
      message: "Grant Screen Recording",
      state: "idle",
      micPermission: false,
      micEnabled: true,
    });
    expect(height).toBe(POPUP_HEIGHT_BLOCKED + POPUP_HEIGHT_MESSAGE_EXTRA);
  });

  it("calculates idle base height when screen is granted and state is idle", () => {
    const height = popupHeight({
      screenPermission: true,
      message: null,
      state: "idle",
      micPermission: true,
      micEnabled: true,
    });
    expect(height).toBe(POPUP_HEIGHT_IDLE);
  });

  it("adds mic note extra when mic is enabled but permission is missing", () => {
    const height = popupHeight({
      screenPermission: true,
      message: null,
      state: "idle",
      micPermission: false,
      micEnabled: true,
    });
    expect(height).toBe(POPUP_HEIGHT_IDLE + POPUP_HEIGHT_MIC_NOTE_EXTRA);
  });

  it("does NOT add mic note extra when mic is disabled even if permission is missing", () => {
    const height = popupHeight({
      screenPermission: true,
      message: null,
      state: "idle",
      micPermission: false,
      micEnabled: false,
    });
    expect(height).toBe(POPUP_HEIGHT_IDLE);
  });

  it("calculates active recording height with message extra and mic note extra", () => {
    const height = popupHeight({
      screenPermission: true,
      message: "Low disk space",
      state: "recording",
      micPermission: false,
      micEnabled: true,
    });
    expect(height).toBe(
      POPUP_HEIGHT_ACTIVE + POPUP_HEIGHT_MESSAGE_EXTRA + POPUP_HEIGHT_MIC_NOTE_EXTRA,
    );
  });
});
