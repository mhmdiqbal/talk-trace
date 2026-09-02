import fs from "node:fs";
import { app } from "electron";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { load, save } from "../src/main/settings";

vi.mock("electron", () => ({
  app: {
    getPath: vi.fn(),
  },
}));

vi.mock("node:fs", () => ({
  default: {
    readFileSync: vi.fn(),
    writeFileSync: vi.fn(),
    mkdirSync: vi.fn(),
  },
}));

describe("settings module", () => {
  const fakeUserData = "/fake/userData";

  beforeEach(() => {
    vi.mocked(app.getPath).mockReturnValue(fakeUserData);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("load", () => {
    it("returns defaults when settings file does not exist", () => {
      vi.mocked(fs.readFileSync).mockImplementation(() => {
        throw new Error("ENOENT: no such file or directory");
      });

      const settings = load();
      expect(settings).toEqual({
        selectedMicID: null,
        micEnabled: true,
      });
    });

    it("returns defaults when settings file contains invalid JSON", () => {
      vi.mocked(fs.readFileSync).mockReturnValue("invalid json content");

      const settings = load();
      expect(settings).toEqual({
        selectedMicID: null,
        micEnabled: true,
      });
    });

    it("returns defaults when settings file contains a non-object JSON primitive", () => {
      vi.mocked(fs.readFileSync).mockReturnValue(JSON.stringify("not-an-object"));

      const settings = load();
      expect(settings).toEqual({
        selectedMicID: null,
        micEnabled: true,
      });
    });

    it("loads valid settings accurately", () => {
      vi.mocked(fs.readFileSync).mockReturnValue(
        JSON.stringify({
          selectedMicID: "mic-12345",
          micEnabled: false,
        }),
      );

      const settings = load();
      expect(settings).toEqual({
        selectedMicID: "mic-12345",
        micEnabled: false,
      });
    });

    it("sanitizes unexpected property types to defaults", () => {
      vi.mocked(fs.readFileSync).mockReturnValue(
        JSON.stringify({
          selectedMicID: 9999,
          micEnabled: "not-a-boolean",
        }),
      );

      const settings = load();
      expect(settings).toEqual({
        selectedMicID: null,
        micEnabled: true,
      });
    });
  });

  describe("save", () => {
    it("ensures directory exists and writes formatted JSON", () => {
      save({
        selectedMicID: "mic-789",
        micEnabled: true,
      });

      expect(fs.mkdirSync).toHaveBeenCalledWith(fakeUserData, { recursive: true });
      expect(fs.writeFileSync).toHaveBeenCalledWith(
        "/fake/userData/settings.json",
        JSON.stringify(
          {
            selectedMicID: "mic-789",
            micEnabled: true,
          },
          null,
          2,
        ),
      );
    });

    it("catches write errors and writes to stderr without crashing", () => {
      const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
      vi.mocked(fs.writeFileSync).mockImplementation(() => {
        throw new Error("EACCES: permission denied");
      });

      expect(() => {
        save({ selectedMicID: null, micEnabled: true });
      }).not.toThrow();

      expect(stderrSpy).toHaveBeenCalledWith(
        expect.stringContaining("[settings] cannot save: Error: EACCES: permission denied"),
      );

      stderrSpy.mockRestore();
    });
  });
});
