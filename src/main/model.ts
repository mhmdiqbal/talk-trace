import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { app, net } from "electron";

const FILE_NAME = "ggml-small.en.bin";
const SOURCE = `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${FILE_NAME}`;
// Both values are published upstream in whisper.cpp models/README.md.
const EXPECTED_BYTES = 487_614_201;
const EXPECTED_SHA1 = "db8a495a91d927739e50b3fc1cc4c6b8f6c2d022";
const ATTEMPTS = 2;

export type ProgressHandler = (percent: number) => void;

type DownloadState = {
  out: fs.WriteStream;
  hash: crypto.Hash;
  received: number;
  lastPercent: number;
  onProgress: ProgressHandler;
};

let inFlight: Promise<boolean> | null = null;

export function modelPath(): string {
  return path.join(app.getPath("userData"), "models", FILE_NAME);
}

export function modelReady(): boolean {
  try {
    return fs.statSync(modelPath()).size === EXPECTED_BYTES;
  } catch {
    return false;
  }
}

/**
 * Resolves true once the model is on disk. Concurrent callers share the one
 * download, so a job that starts waiting mid-download is woken by the same
 * promise instead of starting a second fetch.
 */
export function ensureModel(onProgress: ProgressHandler): Promise<boolean> {
  if (modelReady()) return Promise.resolve(true);
  inFlight ??= downloadWithRetry(onProgress).finally(() => { inFlight = null; });
  return inFlight;
}

async function downloadWithRetry(onProgress: ProgressHandler): Promise<boolean> {
  for (let attempt = 0; attempt < ATTEMPTS; attempt += 1) {
    if (await attempt1(onProgress)) return true;
  }
  return false;
}

function partPath(): string {
  return `${modelPath()}.part`;
}

function receive(state: DownloadState, chunk: Buffer): boolean {
  state.received += chunk.length;
  state.hash.update(chunk);
  const percent = Math.min(100, Math.floor((state.received / EXPECTED_BYTES) * 100));
  if (percent !== state.lastPercent) {
    state.lastPercent = percent;
    state.onProgress(percent);
  }
  return state.out.write(chunk);
}

function verify(state: DownloadState): boolean {
  return state.received === EXPECTED_BYTES && state.hash.digest("hex") === EXPECTED_SHA1;
}

// A .part file plus a size and SHA-1 check, so a cut-off or corrupt download
// never becomes a model that fails later with a confusing whisper error.
function attempt1(onProgress: ProgressHandler): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    fs.mkdirSync(path.dirname(modelPath()), { recursive: true });
    fs.rmSync(partPath(), { force: true });

    const state: DownloadState = {
      out: fs.createWriteStream(partPath()),
      hash: crypto.createHash("sha1"),
      received: 0,
      lastPercent: -1,
      onProgress,
    };

    const fail = () => {
      state.out.destroy();
      fs.rmSync(partPath(), { force: true });
      resolve(false);
    };

    const finish = () => {
      if (!verify(state)) {
        fs.rmSync(partPath(), { force: true });
        resolve(false);
        return;
      }
      fs.renameSync(partPath(), modelPath());
      resolve(true);
    };

    const request = net.request(SOURCE);
    request.on("error", fail);
    request.on("response", (response) => {
      if (response.statusCode !== 200) { fail(); return; }
      response.on("data", (chunk: Buffer) => { drain(state, response, chunk); });
      response.on("end", () => { state.out.end(finish); });
      response.on("error", fail);
    });
    request.end();
  });
}

// 488 MB arrives far faster than the disk takes it, so honour backpressure or
// the whole file queues up in memory.
//
// Electron's IncomingMessage implements the Readable stream interface, but its
// .d.ts declares only NodeEventEmitter, so pause/resume need the cast.
function drain(state: DownloadState, response: NodeJS.EventEmitter, chunk: Buffer): void {
  if (receive(state, chunk)) return;
  const stream = response as unknown as { pause: () => void; resume: () => void };
  stream.pause();
  state.out.once("drain", () => { stream.resume(); });
}
