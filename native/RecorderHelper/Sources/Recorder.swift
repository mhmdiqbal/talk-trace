import AVFoundation
import CoreMedia
import ScreenCaptureKit

enum RecorderError: Error, CustomStringConvertible {
    case noDisplay

    var description: String {
        switch self {
        case .noDisplay: return "no display is available to attach the audio stream to"
        }
    }
}

final class Recorder: NSObject {
    private let systemGain: Float = 1.0
    private let micGain: Float = 1.0

    private let writeQueue = DispatchQueue(label: "recorder.write")
    private let micQueue = DispatchQueue(label: "recorder.mic")
    private let screenQueue = DispatchQueue(label: "recorder.screen")

    private let state = NSLock()
    private var recording = false
    private var paused = false
    private var latestMicLevel: Float = 0

    private var stream: SCStream?
    private var outputURL: URL?
    private var micRing: FloatRing?

    private var file: AVAudioFile?
    private var writeFormat: AVAudioFormat?
    private var systemResampler: Resampler?
    private var framesWritten: AVAudioFramePosition = 0
    private var lastLevelAt = Date.distantPast

    private var micResampler: Resampler?

    var isRecording: Bool {
        state.lock()
        defer { state.unlock() }
        return recording
    }

    private var isPaused: Bool {
        state.lock()
        defer { state.unlock() }
        return paused
    }

    private func setRecording(_ value: Bool) {
        state.lock()
        recording = value
        state.unlock()
    }

    private func setPaused(_ value: Bool) {
        state.lock()
        paused = value
        state.unlock()
    }

    // MARK: - Commands

    func start(_ options: StartOptions) async {
        guard !isRecording else {
            Emit.error("alreadyRecording", "a recording is already running")
            return
        }

        guard await PermissionCheck.screenAuthorized() else {
            Emit.error(
                "noScreenPermission",
                "Screen Recording permission is needed, even to record audio only")
            return
        }

        var wantsMic = options.includeMic
        if wantsMic, await PermissionCheck.requestMic() == false {
            Emit.event(
                "warning",
                [
                    "code": "noMicPermission",
                    "message": "Microphone permission was refused. Recording system audio only.",
                ])
            wantsMic = false
        }

        let url = URL(fileURLWithPath: options.path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

            let audioFile = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: options.sampleRate,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: options.bitrate,
                ])
            let format = audioFile.processingFormat

            writeQueue.sync {
                file = audioFile
                writeFormat = format
                systemResampler = Resampler(target: format)
                framesWritten = 0
                lastLevelAt = .distantPast
            }
            micQueue.sync { micResampler = Resampler(target: format) }
            micRing = FloatRing(capacityFrames: Int(options.sampleRate * 2), channels: 2)
            outputURL = url

            try await startStream(options: options, wantsMic: wantsMic)

            setPaused(false)
            setRecording(true)
            Emit.event("started", ["path": url.path, "mic": wantsMic])
            Emit.event("state", ["state": "recording"])
        } catch {
            tearDown()
            try? FileManager.default.removeItem(at: url)
            Emit.error("startFailed", "\(error)")
        }
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        setPaused(true)
        micRing?.reset()
        Emit.event("state", ["state": "paused"])
    }

    func resume() {
        guard isRecording, isPaused else { return }
        micRing?.reset()
        setPaused(false)
        Emit.event("state", ["state": "recording"])
    }

    func stop() async {
        Trace.mark("stop: entered")
        guard isRecording else {
            Emit.error("notRecording", "no recording is running")
            return
        }
        setRecording(false)

        if let stream {
            Trace.mark("stop: before stopCapture")
            do { try await stream.stopCapture() } catch { Emit.log("stopCapture: \(error)") }
            Trace.mark("stop: after stopCapture")
        }

        let url = outputURL
        var seconds = 0.0
        Trace.mark("stop: before writeQueue.sync")
        writeQueue.sync {
            seconds = Double(framesWritten) / (writeFormat?.sampleRate ?? 48_000)
        }
        Trace.mark("stop: after writeQueue.sync")
        let micFramesMixed = micRing?.framesMixed ?? 0
        tearDown()
        Trace.mark("stop: after tearDown")

        guard let url else { return }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
        Emit.event(
            "stopped",
            [
                "path": url.path,
                "seconds": seconds,
                "bytes": bytes ?? 0,
                "micFramesMixed": micFramesMixed,
            ])
        Emit.event("state", ["state": "idle"])
    }

    private func tearDown() {
        Trace.mark("tearDown: entered")
        stream = nil
        writeQueue.sync {
            file = nil
            writeFormat = nil
            systemResampler = nil
        }
        Trace.mark("tearDown: writeQueue done")
        micQueue.sync { micResampler = nil }
        Trace.mark("tearDown: micQueue done")
        micRing = nil
        outputURL = nil
        setPaused(false)
    }

    // MARK: - Stream setup

    private func startStream(options: StartOptions, wantsMic: Bool) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw RecorderError.noDisplay }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = Int(options.sampleRate)
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 6
        if wantsMic {
            configuration.captureMicrophone = true
            configuration.microphoneCaptureDeviceID = options.micDeviceID
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)

        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writeQueue)
        if wantsMic {
            try newStream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: micQueue)
        }
        // Build order step 2: prove whether a stream with no .screen output starts at all.
        if ProcessInfo.processInfo.environment["RECORDER_ATTACH_SCREEN"] == "1" {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQueue)
            Emit.log("screen output attached for the isolation test")
        }

        try await newStream.startCapture()
        stream = newStream
    }

    // MARK: - Audio paths

    private func handleSystem(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, !isPaused, let file, let systemResampler else { return }
        guard let raw = Self.pcmBuffer(from: sampleBuffer),
            let mix = systemResampler.process(raw)
        else { return }

        let systemLevel = AudioMath.peak(mix)
        AudioMath.scale(mix, by: systemGain)
        micRing?.drain(frames: Int(mix.frameLength), into: mix, gain: micGain)
        AudioMath.clamp(mix)

        do {
            try file.write(from: mix)
            framesWritten += AVAudioFramePosition(mix.frameLength)
        } catch {
            Emit.error("writeFailed", "\(error)")
        }
        sendLevel(system: systemLevel)
    }

    private func handleMic(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, !isPaused, let micRing, let micResampler else { return }
        guard let raw = Self.pcmBuffer(from: sampleBuffer) else { return }

        let level = AudioMath.peak(raw)
        state.lock()
        latestMicLevel = level
        state.unlock()

        guard let ready = micResampler.process(raw) else { return }
        micRing.write(ready)
    }

    private func sendLevel(system: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelAt) >= 0.1 else { return }
        lastLevelAt = now

        state.lock()
        let mic = latestMicLevel
        state.unlock()

        Emit.event("level", ["system": Double(system), "mic": Double(mic)])
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
            let format = AVAudioFormat(streamDescription: asbd)
        else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }

        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}

extension Recorder: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        switch type {
        case .audio: handleSystem(sampleBuffer)
        case .microphone: handleMic(sampleBuffer)
        default: break
        }
    }
}

extension Recorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Emit.error("streamStopped", "\(error)")
        Task { await stop() }
    }
}
