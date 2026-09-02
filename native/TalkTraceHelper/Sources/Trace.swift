import Foundation

/// Appends to a file, so the last moments of the process are visible even when
/// stdout and stderr are broken pipes. Off unless RECORDER_TRACE is set.
enum Trace {
    private static let path =
        ProcessInfo.processInfo.environment["TALKTRACE_TRACE"]
        ?? ProcessInfo.processInfo.environment["RECORDER_TRACE"]
    private static let lock = NSLock()

    static func mark(_ message: String) {
        guard let path else { return }
        let line = "\(Date().timeIntervalSince1970) pid=\(getpid()) ppid=\(getppid()) \(message)\n"
        lock.lock()
        let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        if descriptor >= 0 {
            _ = line.withCString { write(descriptor, $0, strlen($0)) }
            close(descriptor)
        }
        lock.unlock()
    }
}
