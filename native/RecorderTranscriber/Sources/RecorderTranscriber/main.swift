import Foundation

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func transcribe(model: String, audio: String, out: String) throws {
    let reader = try AudioReader(path: audio)
    let writer = try SrtWriter(path: out)
    defer { writer.close() }

    silenceWhisperLog()
    let transcriber = try Transcriber(modelPath: model, writer: writer, chunkCount: reader.chunkCount)
    Emit.ready()

    var index = 0
    while let chunk = try reader.next() {
        guard abortRequested == 0 else { break }
        // Below 0.1 s there is nothing for whisper to find and it would still
        // pad the input out to a full 30 s window.
        if chunk.samples.count >= 1_600 {
            try transcriber.run(chunk, index: index)
        }
        index += 1
    }

    guard abortRequested == 0 else { return }
    if writer.blocksWritten == 0 {
        Emit.empty()
    } else {
        Emit.progress(100)
        Emit.done(writer.blocksWritten)
    }
}

setvbuf(stdout, nil, _IONBF, 0)
signal(SIGPIPE, SIG_IGN)
signal(SIGTERM) { _ in abortRequested = 1 }
signal(SIGINT) { _ in abortRequested = 1 }

do {
    guard let model = argument("--model"), let audio = argument("--audio"), let out = argument("--out")
    else {
        throw TranscribeError.badArguments("usage: RecorderTranscriber --model M --audio A --out O")
    }
    try transcribe(model: model, audio: audio, out: out)
    exit(0)
} catch let error as TranscribeError {
    Emit.error(error.code, error.message)
    exit(1)
} catch {
    Emit.error("unknown", error.localizedDescription)
    exit(1)
}
