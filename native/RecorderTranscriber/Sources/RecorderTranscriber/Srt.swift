import Foundation

/// Writes one SRT block at a time and flushes each one, so a killed run still
/// leaves a file that ends on a whole block.
final class SrtWriter {
    /// whisper still labels a silent stretch instead of returning nothing, so a
    /// recording with no speech would otherwise produce a one-block file.
    private static let nonSpeech: Set<String> = [
        "[blank_audio]", "[silence]", "(silence)", "[ silence ]", "[no speech]",
    ]

    private let handle: FileHandle
    private(set) var blocksWritten = 0

    init(path: String) throws {
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw TranscribeError.cannotWrite(path)
        }
        try? handle.truncate(atOffset: 0)
        self.handle = handle
    }

    /// Returns false when the block was dropped as non-speech.
    @discardableResult
    func append(startMs: Int, endMs: Int, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !SrtWriter.nonSpeech.contains(trimmed.lowercased()) else { return false }
        blocksWritten += 1
        let stamps = "\(SrtWriter.stamp(startMs)) --> \(SrtWriter.stamp(max(endMs, startMs)))"
        let block = "\(blocksWritten)\n\(stamps)\n\(trimmed)\n\n"
        guard let data = block.data(using: .utf8) else { return false }
        try? handle.write(contentsOf: data)
        try? handle.synchronize()
        return true
    }

    func close() {
        try? handle.close()
    }

    static func stamp(_ totalMs: Int) -> String {
        let value = max(0, totalMs)
        let hours = value / 3_600_000
        let minutes = (value / 60_000) % 60
        let seconds = (value / 1_000) % 60
        let millis = value % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }
}
