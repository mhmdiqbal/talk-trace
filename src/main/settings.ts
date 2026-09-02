import fs from "node:fs";
import path from "node:path";
import { app } from "electron";

type Settings = { selectedMicID: string | null; micEnabled: boolean };

const defaults: Settings = { selectedMicID: null, micEnabled: true };

function file(): string {
  return path.join(app.getPath("userData"), "settings.json");
}

export function load(): Settings {
  try {
    const raw: unknown = JSON.parse(fs.readFileSync(file(), "utf8"));
    if (typeof raw !== "object" || raw === null) return { ...defaults };
    const { selectedMicID, micEnabled } = raw as Record<string, unknown>;
    return {
      selectedMicID: typeof selectedMicID === "string" ? selectedMicID : null,
      micEnabled: typeof micEnabled === "boolean" ? micEnabled : true,
    };
  } catch {
    return { ...defaults };
  }
}

export function save(settings: Settings): void {
  try {
    fs.mkdirSync(path.dirname(file()), { recursive: true });
    fs.writeFileSync(file(), JSON.stringify(settings, null, 2));
  } catch (error) {
    process.stderr.write(`[settings] cannot save: ${String(error)}\n`);
  }
}
