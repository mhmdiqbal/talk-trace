import { spawn, type ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";
import path from "node:path";
import { app } from "electron";
import type { Command, HelperEvent } from "./protocol";

export class Helper extends EventEmitter {
  private child: ChildProcess | null = null;
  private buffer = "";

  get binaryPath(): string {
    return app.isPackaged
      ? path.join(process.resourcesPath, "RecorderHelper")
      : path.join(app.getAppPath(), "resources", "RecorderHelper");
  }

  get running(): boolean {
    return this.child !== null;
  }

  start(): void {
    if (this.child) return;

    const child = spawn(this.binaryPath, [], { stdio: ["pipe", "pipe", "pipe"] });
    this.child = child;

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => { this.consume(chunk); });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => process.stderr.write(chunk));

    child.on("error", (error) => {
      this.emitEvent({
        ev: "error",
        code: "spawnFailed",
        message: `cannot run the audio helper: ${error.message}`,
      });
    });

    child.on("exit", (code, signal) => {
      this.child = null;
      this.buffer = "";
      this.emit("exit", { code, signal });
    });
  }

  send(command: Command): boolean {
    const stdin = this.child?.stdin;
    if (!stdin?.writable) return false;
    return stdin.write(`${JSON.stringify(command)}\n`);
  }

  kill(): void {
    this.child?.kill("SIGTERM");
  }

  private consume(chunk: string): void {
    this.buffer += chunk;
    let newline = this.buffer.indexOf("\n");
    while (newline >= 0) {
      const line = this.buffer.slice(0, newline).trim();
      this.buffer = this.buffer.slice(newline + 1);
      if (line) this.parse(line);
      newline = this.buffer.indexOf("\n");
    }
  }

  private parse(line: string): void {
    try {
      this.emitEvent(JSON.parse(line) as HelperEvent);
    } catch {
      process.stderr.write(`[helper] unreadable line: ${line}\n`);
    }
  }

  private emitEvent(event: HelperEvent): void {
    this.emit("event", event);
  }
}
