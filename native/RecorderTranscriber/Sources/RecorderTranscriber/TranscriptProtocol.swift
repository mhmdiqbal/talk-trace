import Foundation

/// Mirrors src/main/transcriptProtocol.ts. The two files are synced by hand.
///
/// Input arrives on argv, not stdin, and a cancel arrives as SIGTERM, so this
/// side only has events.
enum Emit {
    private static let lock = NSLock()

    private static func writeLine(_ data: Data) {
        var payload = data
        payload.append(0x0A)
        payload.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(1, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                if errno != EINTR { return }
            }
        }
    }

    static func event(_ name: String, _ fields: [String: Any] = [:]) {
        var object = fields
        object["ev"] = name
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        lock.lock()
        defer { lock.unlock() }
        writeLine(data)
    }

    static func ready() { event("ready") }
    static func progress(_ percent: Int) { event("progress", ["percent": percent]) }
    static func segment(_ index: Int) { event("segment", ["index": index]) }
    static func done(_ segments: Int) { event("done", ["segments": segments]) }
    static func empty() { event("empty") }

    static func error(_ code: String, _ message: String) {
        event("error", ["code": code, "message": message])
    }
}

enum TranscribeError: Error {
    case badArguments(String)
    case cannotOpenAudio(String)
    case cannotWrite(String)
    case cannotLoadModel(String)
    case whisperFailed(Int32)

    var code: String {
        switch self {
        case .badArguments: return "badArguments"
        case .cannotOpenAudio: return "cannotOpenAudio"
        case .cannotWrite: return "cannotWrite"
        case .cannotLoadModel: return "cannotLoadModel"
        case .whisperFailed: return "whisperFailed"
        }
    }

    var message: String {
        switch self {
        case .badArguments(let detail): return detail
        case .cannotOpenAudio(let path): return "cannot read the recording at \(path)"
        case .cannotWrite(let path): return "cannot write the transcript at \(path)"
        case .cannotLoadModel(let path): return "cannot load the model at \(path)"
        case .whisperFailed(let status): return "whisper failed with status \(status)"
        }
    }
}
