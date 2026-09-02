import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import { newRecordingPath, recordingsDir, resourcePath } from "../src/main/paths";

vi.mock("node:fs", () => ({
  default: {
    mkdirSync: vi.fn(),
  },
}));

describe("recordingsDir", () => {
  it("resolves to ~/Music/Recordings", () => {
    const expected = path.join(os.homedir(), "Music", "Recordings");
    expect(recordingsDir()).toBe(expected);
  });
});

describe("newRecordingPath", () => {
  it("formats date components with 2-digit padding", () => {
    // 2026-04-05 09:07:08
    const mockDate = new Date(2026, 3, 5, 9, 7, 8);
    const result = newRecordingPath(mockDate);

    expect(fs.mkdirSync).toHaveBeenCalledWith(recordingsDir(), { recursive: true });
    expect(result).toBe(path.join(recordingsDir(), "2026-04-05_09-07-08.m4a"));
  });

  it("handles double-digit months, days, and times", () => {
    // 2026-11-25 18:45:59
    const mockDate = new Date(2026, 10, 25, 18, 45, 59);
    const result = newRecordingPath(mockDate);

    expect(result).toBe(path.join(recordingsDir(), "2026-11-25_18-45-59.m4a"));
  });
});

describe("resourcePath", () => {
  it("uses process.resourcesPath when packaged", () => {
    const original = Object.getOwnPropertyDescriptor(process, "resourcesPath");
    try {
      Object.defineProperty(process, "resourcesPath", {
        value: "/Applications/TalkTrace.app/Contents/Resources",
        configurable: true,
        writable: true,
      });
      const res = resourcePath("TalkTraceHelper", true, "/fake/app");
      expect(res).toBe("/Applications/TalkTrace.app/Contents/Resources/TalkTraceHelper");
    } finally {
      if (original) {
        Object.defineProperty(process, "resourcesPath", original);
      } else {
        delete (process as unknown as { resourcesPath?: string }).resourcesPath;
      }
    }
  });

  it("uses appPath/resources when not packaged", () => {
    const res = resourcePath("TalkTraceHelper", false, "/workspace/record-app");
    expect(res).toBe("/workspace/record-app/resources/TalkTraceHelper");
  });
});
