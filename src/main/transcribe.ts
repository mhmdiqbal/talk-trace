import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { app } from "electron";
import { ensureModel, modelPath, modelReady } from "./model";
import { transcriptReady } from "./notify";
import { recordingsDir } from "./paths";
import type { TranscriberEvent } from "./transcriptProtocol";

export type Hooks = { onMessage: (text: string | null) => void };

type Outcome = "running" | "done" | "empty" | "failed";

type Job = {
  audio: string;
  child: ChildProcess;
  buffer: string;
  outcome: Outcome;
  aborted: boolean;
};

const PARTIAL_SUFFIX = ".partial.srt";

const queue: string[] = [];
let hooks: Hooks | null = null;
let job: Job | null = null;
let suspended = false;
let quitting = false;

function disabled(): boolean {
  return process.env.RECORDER_NO_TRANSCRIBE === "1";
}

function binaryPath(): string {
  return app.isPackaged
    ? path.join(process.resourcesPath, "RecorderTranscriber")
    : path.join(app.getAppPath(), "resources", "RecorderTranscriber");
}

function baseOf(audio: string): string {
  return audio.replace(/\.m4a$/, "");
}

function message(text: string | null): void {
  hooks?.onMessage(text);
}

// MARK: public surface

/** Also starts the one-time model download, so the env guard lives in one place. */
export function start(next: Hooks): void {
  hooks = next;
  scanForPartials();
  if (disabled() || modelReady()) return;
  void ensureModel(onDownloadProgress).then((ready) => {
    message(ready ? null : "The transcript model could not be downloaded.");
    if (ready) pump();
  });
}

export function enqueue(audio: string): void {
  if (disabled() || !audio.endsWith(".m4a")) return;
  if (!queue.includes(audio) && job?.audio !== audio) queue.push(audio);
  pump();
}

/**
 * Whisper takes every core and the GPU, so a job must not run next to a live
 * recording. There is no pause in the whisper API, so this kills the child and
 * puts the job back at the head of the queue to start over.
 */
export function suspend(): void {
  suspended = true;
  if (!job) return;
  job.aborted = true;
  job.child.kill("SIGTERM");
}

export function resume(): void {
  suspended = false;
  pump();
}

export function kill(): void {
  quitting = true;
  job?.child.kill("SIGTERM");
}

/** A leftover .partial.srt means a job was cut short. Redo it, no queue file. */
function scanForPartials(): void {
  if (disabled()) return;
  const dir = recordingsDir();
  let names: string[];
  try {
    names = fs.readdirSync(dir);
  } catch {
    return;
  }
  for (const name of names) {
    if (!name.endsWith(PARTIAL_SUFFIX)) continue;
    const audio = path.join(dir, `${name.slice(0, -PARTIAL_SUFFIX.length)}.m4a`);
    if (fs.existsSync(audio)) enqueue(audio);
  }
}

// MARK: queue

function pump(): void {
  if (disabled() || suspended || quitting || job !== null) return;
  const audio = queue[0];
  if (audio === undefined) return;

  if (!modelReady()) {
    message("Waiting for the transcript model");
    void ensureModel(onDownloadProgress).then((ready) => { if (ready) pump(); });
    return;
  }

  queue.shift();
  run(audio);
}

function onDownloadProgress(percent: number): void {
  message(`Downloading transcript model ${String(percent)}%`);
}

function run(audio: string): void {
  const args = ["--model", modelPath(), "--audio", audio, "--out", `${baseOf(audio)}${PARTIAL_SUFFIX}`];
  const child = spawn(binaryPath(), args, { stdio: ["ignore", "pipe", "pipe"] });
  const started: Job = { audio, child, buffer: "", outcome: "running", aborted: false };
  job = started;

  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk: string) => { consume(started, chunk); });
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk: string) => process.stderr.write(chunk));
  child.on("error", (error) => {
    started.outcome = "failed";
    message(`Cannot run the transcriber: ${error.message}`);
    onExit();
  });
  child.on("exit", onExit);
}

function onExit(): void {
  const finished = job;
  job = null;
  if (!finished) return;

  if (finished.aborted) {
    if (!quitting && !queue.includes(finished.audio)) queue.unshift(finished.audio);
  } else {
    settle(finished);
  }
  pump();
}

function settle(finished: Job): void {
  const partial = `${baseOf(finished.audio)}${PARTIAL_SUFFIX}`;
  if (finished.outcome === "done") {
    const srt = `${baseOf(finished.audio)}.srt`;
    try {
      fs.renameSync(partial, srt);
    } catch {
      message("The transcript could not be saved.");
      return;
    }
    message("Transcript saved");
    transcriptReady(srt);
    return;
  }
  if (finished.outcome === "empty") {
    fs.rmSync(partial, { force: true });
    message("No speech found");
    return;
  }
  message("The transcript did not finish. The recording is safe.");
}

// MARK: transcriber events

function consume(target: Job, chunk: string): void {
  target.buffer += chunk;
  let newline = target.buffer.indexOf("\n");
  while (newline >= 0) {
    const line = target.buffer.slice(0, newline).trim();
    target.buffer = target.buffer.slice(newline + 1);
    if (line) parse(line);
    newline = target.buffer.indexOf("\n");
  }
}

function parse(line: string): void {
  try {
    onEvent(JSON.parse(line) as TranscriberEvent);
  } catch {
    process.stderr.write(`[transcriber] unreadable line: ${line}\n`);
  }
}

function onEvent(event: TranscriberEvent): void {
  if (!job) return;
  switch (event.ev) {
    case "ready":
      message("Transcribing…");
      break;
    case "progress":
      message(`Transcribing ${String(event.percent)}%`);
      break;
    case "segment":
      break;
    case "done":
      job.outcome = "done";
      break;
    case "empty":
      job.outcome = "empty";
      break;
    case "error":
      job.outcome = "failed";
      message(`Transcript failed: ${event.message}`);
      break;
  }
}
