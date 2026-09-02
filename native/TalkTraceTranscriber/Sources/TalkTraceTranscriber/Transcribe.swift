import CWhisper
import Foundation

/// Set from the SIGTERM and SIGINT handlers. whisper checks it through
/// abort_callback before every ggml computation, so a cancel lands quickly.
var abortRequested: sig_atomic_t = 0

/// Callback state. C function pointers cannot capture, so this travels as
/// user_data instead.
final class JobContext {
    let writer: SrtWriter
    let chunkCount: Int
    var chunkIndex = 0
    var chunkOffsetMs = 0
    private var lastPercent = -1
    private var lastEmit = Date.distantPast

    init(writer: SrtWriter, chunkCount: Int) {
        self.writer = writer
        self.chunkCount = max(1, chunkCount)
    }

    func report(chunkPercent: Int) {
        let overall = min(100, (chunkIndex * 100 + chunkPercent) / chunkCount)
        let now = Date()
        guard overall != lastPercent, now.timeIntervalSince(lastEmit) >= 1 else { return }
        lastPercent = overall
        lastEmit = now
        Emit.progress(overall)
    }
}

private let onNewSegment: whisper_new_segment_callback = { ctx, _, newCount, userData in
    guard let ctx, let userData else { return }
    let job = Unmanaged<JobContext>.fromOpaque(userData).takeUnretainedValue()
    let total = whisper_full_n_segments(ctx)
    var index = max(0, total - newCount)
    while index < total {
        let start = Int(whisper_full_get_segment_t0(ctx, index)) * 10
        let end = Int(whisper_full_get_segment_t1(ctx, index)) * 10
        let text = whisper_full_get_segment_text(ctx, index).map { String(cString: $0) } ?? ""
        let written = job.writer.append(
            startMs: job.chunkOffsetMs + start,
            endMs: job.chunkOffsetMs + end,
            text: text)
        if written { Emit.segment(job.writer.blocksWritten) }
        index += 1
    }
}

private let onProgress: whisper_progress_callback = { _, _, progress, userData in
    guard let userData else { return }
    Unmanaged<JobContext>.fromOpaque(userData).takeUnretainedValue().report(chunkPercent: Int(progress))
}

private let onAbort: ggml_abort_callback = { _ in abortRequested != 0 }

final class Transcriber {
    /// params.language is a borrowed C string, so it has to outlive the call.
    private static let english = strdup("en")

    private let ctx: OpaquePointer
    private let job: JobContext

    init(modelPath: String, writer: SrtWriter, chunkCount: Int) throws {
        var options = whisper_context_default_params()
        options.use_gpu = true
        options.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(modelPath, options) else {
            throw TranscribeError.cannotLoadModel(modelPath)
        }
        self.ctx = ctx
        self.job = JobContext(writer: writer, chunkCount: chunkCount)
    }

    deinit {
        whisper_free(ctx)
    }

    func run(_ chunk: AudioChunk, index: Int) throws {
        job.chunkIndex = index
        job.chunkOffsetMs = Int(chunk.startSeconds * 1000)

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.language = UnsafePointer(Transcriber.english)
        params.detect_language = false
        params.translate = false
        params.no_timestamps = false
        params.single_segment = false
        // suppress_nst stays off. With it on, whisper replaces its honest
        // [BLANK_AUDIO] marker for a silent stretch with a hallucinated word,
        // which no filter can catch. The marker is dropped in SrtWriter.
        // print_progress defaults to true and writes to stderr.
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.n_threads = Int32(min(8, ProcessInfo.processInfo.activeProcessorCount))

        let opaque = Unmanaged.passUnretained(job).toOpaque()
        params.new_segment_callback = onNewSegment
        params.new_segment_callback_user_data = opaque
        params.progress_callback = onProgress
        params.progress_callback_user_data = opaque
        params.abort_callback = onAbort
        params.abort_callback_user_data = nil

        let status = chunk.samples.withUnsafeBufferPointer { buffer in
            whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
        }
        guard abortRequested == 0 else { return }
        if status != 0 { throw TranscribeError.whisperFailed(status) }
    }
}

/// whisper and ggml both log to stderr, which Electron forwards to its own.
/// They have separate log sinks, and ggml's Metal shader compile alone prints
/// dozens of lines per run, so both have to be muted.
func silenceWhisperLog() {
    let sink: ggml_log_callback = { _, text, _ in
        let debug =
            ProcessInfo.processInfo.environment["TALKTRACE_DEBUG"]
            ?? ProcessInfo.processInfo.environment["RECORDER_DEBUG"]
        guard debug == "1", let text else { return }
        fputs(String(cString: text), stderr)
    }
    whisper_log_set(sink, nil)
    ggml_log_set(sink, nil)
}
