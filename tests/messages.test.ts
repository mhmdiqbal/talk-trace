import { describe, expect, it } from "vitest";
import { formatSeconds, helperExitMessage } from "../src/main/messages";

describe("formatSeconds", () => {
  it("formats zero seconds as 0:00", () => {
    expect(formatSeconds(0)).toBe("0:00");
  });

  it("formats single-digit seconds with leading zero", () => {
    expect(formatSeconds(7)).toBe("0:07");
  });

  it("formats multi-digit seconds correctly", () => {
    expect(formatSeconds(45)).toBe("0:45");
  });

  it("formats exact minutes", () => {
    expect(formatSeconds(60)).toBe("1:00");
    expect(formatSeconds(120)).toBe("2:00");
  });

  it("formats fractional seconds by flooring to whole integer", () => {
    expect(formatSeconds(65.8)).toBe("1:05");
  });

  it("formats long recording durations over an hour", () => {
    expect(formatSeconds(3665)).toBe("61:05");
  });
});

describe("helperExitMessage", () => {
  it("returns crash message when giveUp is true, regardless of recording state", () => {
    expect(helperExitMessage(true, false, 1, null)).toBe(
      "The audio helper keeps crashing. Quit TalkTrace and check Console for details.",
    );
    expect(helperExitMessage(true, true, null, "SIGKILL")).toBe(
      "The audio helper keeps crashing. Quit TalkTrace and check Console for details.",
    );
  });

  it("returns null if the helper exited normally while not recording", () => {
    expect(helperExitMessage(false, false, 0, null)).toBeNull();
  });

  it("formats exit message with exit code if stopped during recording", () => {
    expect(helperExitMessage(false, true, 137, null)).toBe(
      "The audio helper stopped during a recording (code 137). The file may be short.",
    );
  });

  it("formats exit message with signal if stopped during recording with null code", () => {
    expect(helperExitMessage(false, true, null, "SIGTERM")).toBe(
      "The audio helper stopped during a recording (code SIGTERM). The file may be short.",
    );
  });
});
