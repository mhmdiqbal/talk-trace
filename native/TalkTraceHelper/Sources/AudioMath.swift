import AVFoundation

enum AudioMath {
    static func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        var highest: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<frames {
                highest = max(highest, abs(samples[frame]))
            }
        }
        return min(highest, 1)
    }

    static func scale(_ buffer: AVAudioPCMBuffer, by gain: Float) {
        guard gain != 1, let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<frames {
                samples[frame] *= gain
            }
        }
    }

    static func clamp(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<frames {
                samples[frame] = min(max(samples[frame], -1), 1)
            }
        }
    }
}
