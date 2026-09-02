/**
 * Mirrors native/TalkTraceTranscriber/Sources/TalkTraceTranscriber/TranscriptProtocol.swift.
 * The two files are synced by hand, like protocol.ts and Protocol.swift.
 *
 * There is no command type. The transcriber takes its input on argv and a
 * cancel arrives as SIGTERM, so only events cross the pipe.
 */
export type TranscriberEvent =
  | { ev: "ready" }
  | { ev: "progress"; percent: number }
  | { ev: "segment"; index: number }
  | { ev: "done"; segments: number }
  | { ev: "empty" }
  | { ev: "error"; code: string; message: string };
