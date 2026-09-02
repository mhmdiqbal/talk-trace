import AVFoundation

struct AudioChunk {
    let samples: [Float]
    let startSeconds: Double
}

/// Decodes the recorded .m4a to the only format whisper accepts: 16 kHz mono
/// Float32. Yields it in chunks of about ten minutes so memory stays flat no
/// matter how long the recording is.
final class AudioReader {
    static let sampleRate: Double = 16_000
    private static let chunkSeconds: Double = 600
    private static let searchSeconds: Double = 5
    private static let readFrames: AVAudioFrameCount = 16_384

    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var pending: [Float] = []
    private var emittedSamples = 0
    private var drained = false

    let totalSeconds: Double

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard let file = try? AVAudioFile(forReading: url) else {
            throw TranscribeError.cannotOpenAudio(path)
        }
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AudioReader.sampleRate,
                channels: 1,
                interleaved: false),
            let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat)
        else {
            throw TranscribeError.cannotOpenAudio(path)
        }
        self.file = file
        self.converter = converter
        self.outputFormat = outputFormat
        let rate = file.processingFormat.sampleRate
        self.totalSeconds = rate > 0 ? Double(file.length) / rate : 0
    }

    var chunkCount: Int {
        max(1, Int(ceil(totalSeconds / AudioReader.chunkSeconds)))
    }

    /// Next chunk, or nil once the file is used up.
    func next() throws -> AudioChunk? {
        let ideal = Int(AudioReader.chunkSeconds * AudioReader.sampleRate)
        let search = Int(AudioReader.searchSeconds * AudioReader.sampleRate)

        while !drained && pending.count < ideal + search {
            try fill()
        }

        guard !pending.isEmpty else { return nil }

        let cut =
            drained && pending.count <= ideal + search
            ? pending.count
            : AudioReader.cutPoint(in: pending, ideal: ideal, search: search)

        let chunk = AudioChunk(
            samples: Array(pending[0..<cut]),
            startSeconds: Double(emittedSamples) / AudioReader.sampleRate)
        pending.removeFirst(cut)
        emittedSamples += cut
        return chunk
    }

    private func fill() throws {
        guard
            let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AudioReader.readFrames)
        else {
            drained = true
            return
        }

        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            guard
                let input = AVAudioPCMBuffer(
                    pcmFormat: self.file.processingFormat,
                    frameCapacity: AudioReader.readFrames)
            else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try self.file.read(into: input)
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
            if input.frameLength == 0 {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return input
        }

        if status == .error {
            throw TranscribeError.cannotOpenAudio(file.url.path)
        }
        if let channel = output.floatChannelData?[0], output.frameLength > 0 {
            pending.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        }
        if status == .endOfStream || status == .inputRanDry && output.frameLength == 0 {
            drained = true
        }
    }

    /// Picks the quietest 100 ms window near the ideal cut so a boundary is
    /// less likely to land in the middle of a word. No overlap is used, so no
    /// text can be duplicated across chunks.
    static func cutPoint(in samples: [Float], ideal: Int, search: Int) -> Int {
        let window = Int(sampleRate / 10)
        let low = max(0, ideal - search)
        let high = min(samples.count - window, ideal + search)
        guard window > 0, low < high else { return min(ideal, samples.count) }

        var best = min(ideal, samples.count)
        var bestEnergy = Float.greatestFiniteMagnitude
        var position = low
        while position < high {
            var energy: Float = 0
            for index in position..<(position + window) {
                energy += samples[index] * samples[index]
            }
            if energy < bestEnergy {
                bestEnergy = energy
                best = position + window / 2
            }
            position += window / 2
        }
        return best
    }
}
