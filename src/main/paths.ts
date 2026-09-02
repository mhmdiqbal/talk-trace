import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export function recordingsDir(): string {
  return path.join(os.homedir(), "Music", "Recordings");
}

export function newRecordingPath(now = new Date()): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  const name =
    `${String(now.getFullYear())}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}` +
    `_${pad(now.getHours())}-${pad(now.getMinutes())}-${pad(now.getSeconds())}.m4a`;

  const dir = recordingsDir();
  fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, name);
}

export function resourcePath(name: string, isPackaged: boolean, appPath: string): string {
  return isPackaged
    ? path.join(process.resourcesPath, name)
    : path.join(appPath, "resources", name);
}
