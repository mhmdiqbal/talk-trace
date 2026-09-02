import Foundation

let recorder = Recorder()
let pendingWork = DispatchGroup()

func async(_ body: @escaping () async -> Void) {
    pendingWork.enter()
    Task {
        await body()
        pendingWork.leave()
    }
}

func handle(_ command: Command) {
    switch command {
    case .permissions:
        async {
            let permissions = await PermissionCheck.current()
            Emit.event("permissions", ["screen": permissions.screen, "mic": permissions.mic])
        }
    case .listDevices:
        Emit.event(
            "devices",
            [
                "mics": Devices.mics().map { ["id": $0.id, "name": $0.name] },
                "currentOutput": Devices.defaultOutputName(),
            ])
    case .start(let options):
        async { await recorder.start(options) }
    case .pause:
        recorder.pause()
    case .resume:
        recorder.resume()
    case .stop:
        async { await recorder.stop() }
    case .muteMic(let muted):
        recorder.setMicMuted(muted)
    }
}

let shutdownLock = NSLock()
var shuttingDown = false

/// A second signal during shutdown must not call exit() while the first one is
/// still closing the file, or the .m4a is left truncated and unplayable.
func beginShutdown() {
    shutdownLock.lock()
    let alreadyGoing = shuttingDown
    shuttingDown = true
    shutdownLock.unlock()
    Trace.mark("beginShutdown alreadyGoing=\(alreadyGoing) recording=\(recorder.isRecording)")
    if alreadyGoing { return }

    // A `stop` command already in flight must finish before we exit, or it
    // clears the recording flag and we quit before the .m4a index is written.
    // Own thread, because this blocks.
    Thread {
        pendingWork.wait()
        Trace.mark("pendingWork done, recording=\(recorder.isRecording)")
        if recorder.isRecording {
            let finished = DispatchSemaphore(value: 0)
            Task {
                Trace.mark("shutdown task started")
                await recorder.stop()
                Trace.mark("shutdown task stop returned")
                finished.signal()
            }
            finished.wait()
        }
        Trace.mark("exiting")
        exit(0)
    }.start()
}

func installSignalHandlers() -> [DispatchSourceSignal] {
    [SIGTERM, SIGINT, SIGHUP].map { number in
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler {
            Trace.mark("signal \(number)")
            beginShutdown()
        }
        source.resume()
        return source
    }
}

/// EOF on stdin must never end a recording, but a dead parent must. When the
/// parent exits we are reparented to launchd (pid 1), so nothing will ever send
/// us a stop and we would record until the disk fills.
func watchForOrphaning() -> DispatchSourceTimer {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 2, repeating: 2)
    timer.setEventHandler {
        if getppid() == 1 {
            Trace.mark("orphaned")
            Emit.log("parent process is gone, closing the recording")
            beginShutdown()
        }
    }
    timer.resume()
    return timer
}

// A broken stdout pipe must not kill us mid-recording. Without this, the parent
// dying takes the .m4a down with it before the index is written.
signal(SIGPIPE, SIG_IGN)
Emit.makeOutputNonBlocking()
Trace.mark("startup")

let signalSources = installSignalHandlers()
let orphanWatch = watchForOrphaning()

let stdinReader = Thread {
    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        do {
            handle(try Command.parse(trimmed))
        } catch {
            Emit.error("badCommand", "\(error)")
        }
    }
    // EOF must never end a running recording. Only stop or a signal does.
    // Wait for in-flight commands first, or a one-shot pipe exits before it answers.
    pendingWork.wait()
    if !recorder.isRecording { exit(0) }
}
stdinReader.name = "stdin"
stdinReader.start()

Emit.event(
    "ready",
    [
        "pid": ProcessInfo.processInfo.processIdentifier,
        "sources": signalSources.count,
        "orphanWatch": !orphanWatch.isCancelled,
    ])
RunLoop.main.run()
