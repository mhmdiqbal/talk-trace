import Foundation

struct StartOptions {
    let path: String
    let micDeviceID: String?
    let includeMic: Bool
    let sampleRate: Double
    let bitrate: Int
}

enum Command {
    case permissions
    case listDevices
    case start(StartOptions)
    case pause
    case resume
    case stop
}

enum CommandError: Error, CustomStringConvertible {
    case notJSON
    case unknown(String)
    case missingField(String)

    var description: String {
        switch self {
        case .notJSON: return "line is not a JSON object with a cmd field"
        case .unknown(let name): return "unknown cmd \(name)"
        case .missingField(let name): return "missing field \(name)"
        }
    }
}

extension Command {
    static func parse(_ line: String) throws -> Command {
        guard let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = object["cmd"] as? String
        else { throw CommandError.notJSON }

        switch name {
        case "permissions": return .permissions
        case "listDevices": return .listDevices
        case "pause": return .pause
        case "resume": return .resume
        case "stop": return .stop
        case "start":
            guard let path = object["path"] as? String else {
                throw CommandError.missingField("path")
            }
            return .start(
                StartOptions(
                    path: path,
                    micDeviceID: object["micDeviceID"] as? String,
                    includeMic: object["includeMic"] as? Bool ?? true,
                    sampleRate: (object["sampleRate"] as? NSNumber)?.doubleValue ?? 48_000,
                    bitrate: (object["bitrate"] as? NSNumber)?.intValue ?? 128_000))
        default:
            throw CommandError.unknown(name)
        }
    }
}

enum Emit {
    private static let lock = NSLock()

    /// Raw write(2) on a non-blocking descriptor, with a short bounded retry.
    ///
    /// This runs on the audio callback queue. If stdout is a pipe whose reader
    /// stopped, a blocking write fills the 64 KB buffer and then parks the audio
    /// queue forever; SCStream.stopCapture waits on that same queue, so the
    /// process deadlocks and the .m4a is never finalised. Dropping an event is
    /// always better than that, so give up after `budget` and move on.
    private static func writeLine(_ data: Data, to descriptor: Int32) {
        var payload = data
        payload.append(0x0A)
        let budget = Date().addingTimeInterval(0.05)

        payload.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(
                    descriptor,
                    buffer.baseAddress!.advanced(by: offset),
                    buffer.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                let blocked = errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR
                if !blocked || Date() > budget { return }
                usleep(2_000)
            }
        }
    }

    /// Must run before any event is written.
    static func makeOutputNonBlocking() {
        for descriptor in [Int32(1), Int32(2)] {
            let flags = fcntl(descriptor, F_GETFL, 0)
            if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) }
        }
    }

    static func event(_ name: String, _ fields: [String: Any] = [:]) {
        var object = fields
        object["ev"] = name
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        lock.lock()
        writeLine(data, to: 1)
        lock.unlock()
    }

    static func error(_ code: String, _ message: String) {
        event("error", ["code": code, "message": message])
    }

    static func log(_ message: String) {
        lock.lock()
        writeLine(Data("[helper] \(message)".utf8), to: 2)
        lock.unlock()
    }
}
