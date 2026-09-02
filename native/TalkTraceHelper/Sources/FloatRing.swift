import AVFoundation

final class FloatRing {
    private let capacityFrames: Int
    private let channels: Int
    private var storage: [Float]
    private var writeIndex = 0
    private var available = 0
    private var mixedFrames = 0
    private let lock = NSLock()

    var framesMixed: Int {
        lock.lock()
        defer { lock.unlock() }
        return mixedFrames
    }

    init(capacityFrames: Int, channels: Int) {
        self.capacityFrames = capacityFrames
        self.channels = channels
        self.storage = [Float](repeating: 0, count: capacityFrames * channels)
    }

    func reset() {
        lock.lock()
        writeIndex = 0
        available = 0
        lock.unlock()
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        guard let source = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let sourceChannels = Int(buffer.format.channelCount)
        guard frames > 0 else { return }

        lock.lock()
        for frame in 0..<frames {
            let base = writeIndex * channels
            for channel in 0..<channels {
                let sourceChannel = min(channel, sourceChannels - 1)
                storage[base + channel] = source[sourceChannel][frame]
            }
            writeIndex = (writeIndex + 1) % capacityFrames
        }
        available = min(available + frames, capacityFrames)
        lock.unlock()
    }

    /// Adds the oldest `frames` frames into `destination` and drops them.
    /// Missing frames are treated as silence, so the caller always advances.
    func drain(frames: Int, into destination: AVAudioPCMBuffer, gain: Float) {
        guard let target = destination.floatChannelData, frames > 0 else { return }
        let targetChannels = Int(destination.format.channelCount)

        lock.lock()
        let usable = min(frames, available)
        var readIndex = (writeIndex - available + capacityFrames) % capacityFrames
        for frame in 0..<usable {
            let base = readIndex * channels
            for channel in 0..<targetChannels {
                target[channel][frame] += storage[base + min(channel, channels - 1)] * gain
            }
            readIndex = (readIndex + 1) % capacityFrames
        }
        available -= usable
        mixedFrames += usable
        lock.unlock()
    }
}
