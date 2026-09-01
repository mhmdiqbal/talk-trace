# Recorder

A macOS menu bar app that records what your Mac plays, plus your microphone,
into one `.m4a` file.

No virtual audio driver. No BlackHole. No Loopback. macOS 15+ can do this on
its own through `ScreenCaptureKit`.

## What it does

- Records the system audio mix and your mic, mixed into one stereo file
- Saves to `~/Music/Recordings/YYYY-MM-DD_HH-mm-ss.m4a` (AAC, 48 kHz, 128 kbps)
- About 44 to 70 MB per hour. AAC is variable rate, so loud music costs more
- Global hotkey `⌥⌘R` to start and stop from any app
- Live level bars for Mac sound and mic, so you can see a dead mic
- Pause and resume. The paused time is removed from the file
- Blocks system sleep while recording
- Picks the microphone. Shows the current output device as read-only text
- Writes a transcript next to the audio when a recording stops, made on the
  machine by whisper.cpp. No cloud service and no API key

## Transcripts

When a recording stops, the app transcribes it and writes
`~/Music/Recordings/YYYY-MM-DD_HH-mm-ss.srt` beside the `.m4a`. A macOS
notification says when it is ready; click it to show the file in Finder.

It runs on your Mac. Nothing is uploaded.

- **English only.** A recording in another language gives nonsense, not an error.
- **First launch downloads 488 MB**, the `ggml-small.en` Whisper model, into
  `~/Library/Application Support/Recorder/models/`. The size and SHA-1 are
  checked before the file is used. Until it lands, recordings queue up.
- While the job runs you see `Transcribing 40%` in the popup message line.
- A file ending in `.partial.srt` is a job that was cut short, by quitting or by
  a new recording. It is valid SRT as far as it goes. The app finds it on the
  next launch and does the whole recording again.
- **A recording always wins.** Whisper uses every core and the GPU, so starting
  a recording kills any running job and restarts it after the recording stops.
- Jobs run one at a time, in order.
- A recording with no speech gets no file at all, and the message says
  `No speech found`.
- Set `RECORDER_NO_TRANSCRIBE=1` to turn the whole feature off, including the
  download.

Speed on Apple silicon is roughly 50x faster than real time, so an hour of audio
takes about a minute. It needs about 850 MB of RAM while it runs.

## What it cannot do

**You cannot choose which output device to record.** `ScreenCaptureKit` records
the whole system mix, whatever speaker or headphone plays it. This is a limit of
the API, not of this app. The popup shows the current output name so you know
what you are getting.

## Permissions

Two are needed, and macOS asks for each once:

1. **Screen Recording** — needed even though we only take audio. This is how
   `ScreenCaptureKit` works. No picture is ever captured or saved.
2. **Microphone** — so your voice is in the file.

If one is missing, the popup says which and gives you a button to the right
System Settings page.

The grant belongs to the audio helper, not to Electron. The helper gets its own
code identity: `scripts/build-helper.sh` embeds `build/helper-Info.plist` into
the binary with `-sectcreate __TEXT __info_plist`, then signs it as
`com.mmdiqbal.recorder.helper` with an Apple Development certificate.

This was tested, and it means the grant holds no matter who starts the helper —
a shell, `pnpm start`, `Recorder.app` in `release/`, or `Recorder.app` in
`/Applications`. Because the certificate is stable, the grant also survives a
rebuild. `electron-builder` re-signs the helper when it packages, and both the
identifier and the `audio-input` entitlement survive that.

## Build and run

```bash
pnpm install
pnpm start          # builds both binaries and the TypeScript, then runs Electron
pnpm run dist       # builds release/mac-arm64/Recorder.app and release/Recorder-1.0.0-arm64.dmg
```

The first build also downloads and compiles whisper.cpp into `native/vendor/`,
which takes a few minutes and needs `cmake` (`brew install cmake`). A stamp file
makes every later build skip it.

This project uses pnpm 11, pinned by the `packageManager` field. Run
`corepack enable` once so the pinned version is the one that runs.

To install locally, open the generated `.dmg` in `release/Recorder-1.0.0-arm64.dmg`
and drag Recorder into `/Applications` (or directly copy
`release/mac-arm64/Recorder.app` to `/Applications`). Look for the ring icon in
the menu bar. It turns into a red dot while recording.

`pnpm start` automatically detects any valid `Apple Development` certificate in
your macOS Keychain. If none is found, it falls back to ad-hoc (`-`) signing.
You can specify a certificate explicitly with `RECORDER_IDENTITY="..."`.
For distribution outside development, sign with a Developer ID Application
certificate and notarize via `CSC_NAME="..." pnpm run dist`.

## Linting

```bash
pnpm lint         # all five checks below
pnpm typecheck    # types only, writes nothing
```

`scripts/lint.sh` runs, and stops at the first failure:

| Check | Tool | Covers |
|---|---|---|
| types | `tsc --noEmit` | both tsconfigs |
| TypeScript | ESLint 10 + typescript-eslint `strictTypeChecked` | `src/`, `build/*.cjs` |
| Swift | `swift format lint --strict` | `native/RecorderHelper/Sources` |
| shell | `shellcheck` | `scripts/*.sh` |
| Python | `ruff check` and `ruff format --check` | `scripts/*.py` |

Two of these are not on a Mac by default. `pnpm lint` fails with the install
command if either is missing:

```bash
brew install shellcheck ruff
```

`swift format` ships with the Swift toolchain, so it needs no install.
`.swift-format` sets 4-space indent and a 110-column limit.

`pnpm test` runs `pnpm lint` first, through the `pretest` script.

## Code analysis

SonarQube runs locally in podman. It is separate from `pnpm lint` and is never
part of a build.

```bash
./scripts/sonarqube.sh start   # SonarQube + Postgres on http://localhost:9000
pnpm sonar                     # start the server if needed, then scan
./scripts/sonarqube.sh stop
```

**Swift is not analysed.** SonarQube Community has no Swift analyzer at any
version, so `native/RecorderHelper` is invisible here. `swift format lint
--strict` in `scripts/lint.sh` stays the only gate on that code. What Sonar
sees is `src/**` TypeScript and `scripts/*.py`.

First-time setup, in the browser:

1. Open `http://localhost:9000`, log in with `admin` / `admin`, set a password.
2. Go to My Account > Security and create a user token.
3. Put it in `.env` as `SONAR_TOKEN=...`. That file is gitignored.

The quality gate is the default "Sonar way", and it judges new code only. New
code means "since previous version". `scripts/sonar.sh` passes the version from
`package.json`, so while you leave that at `1.0.0` there is no new code and the
gate reads OK. Bump it and the coverage condition wakes up and fails, because
there are no tests and no coverage report. `pnpm sonar` exits 0 either way; read
the issue list, not the colour.

Two things that are pinned on purpose:

- The image is `sonarqube:26.8.0.126808-community`, an exact build. The
  `lts-community` tag is frozen at 9.9.8 from 2023, because the Community line
  has no LTA any more.
- The database is Postgres in its own container. Modern SonarQube dropped the
  embedded H2 database, so this is required, not a preference.

`sonar-project.properties` names both tsconfigs. Without that the renderer
falls back to weaker, non type-aware rules.

## How it is put together

Two processes:

- **`native/RecorderHelper`** — Swift. Owns all audio. Runs `SCStream` with
  `capturesAudio` and `captureMicrophone`, resamples the mic to the write
  format, mixes, and writes the `.m4a` with `AVAudioFile`.
- **`src/main`** — Electron. Owns the menu bar icon, the popup, the hotkey, the
  sleep blocker, and settings. Touches no audio.

They talk over stdin and stdout, one JSON object per line. Electron sends
commands, the helper sends events. See `src/main/protocol.ts` and
`native/RecorderHelper/Sources/Protocol.swift` — keep those two in step by hand.

Closing stdin does **not** stop a recording. Only a `stop` command, a signal, or
the parent process dying does. That way a hiccup in the pipe cannot lose a file.

Shutdown is the part that needs care. Quitting the app while recording used to
leave the `.m4a` without its MP4 index, so it would not play. Three rules keep
that from coming back:

- Electron quits **gracefully**. `before-quit` calls `preventDefault()`, sends
  `stop`, and waits for the `stopped` event (or 5 s) before it kills anything.
  The file is closed by the ordinary `stop` path.
- The helper's signal shutdown is idempotent and waits for any in-flight
  command, so a signal cannot exit while `stop()` is still writing.
- The helper stops itself if `getppid()` becomes 1, so an orphan cannot record
  until the disk fills.

`Trace.swift` writes to the file named by `RECORDER_TRACE`. Use it when
debugging shutdown — stdout and stderr are exactly what you cannot trust while
the process is dying.

## Testing

```bash
./scripts/build-helper.sh                        # build and sign the helper

# drive the helper by hand over a FIFO
./scripts/smoke.sh /tmp/t.m4a                    # plays system sounds, records
./scripts/quiet.sh /tmp/t.m4a '' 6               # record 6s, nothing played

python3 scripts/energy.py /tmp/t.m4a             # RMS and peak of a file
python3 scripts/spectrum.py /tmp/t.m4a           # dominant frequencies

# drive the whole Electron app with no key presses
RECORDER_DEBUG=1 RECORDER_SELFTEST=1 pnpm exec electron .
```

`RECORDER_DEBUG=1` prints every helper event. `RECORDER_SELFTEST=1` runs a
start / pause / resume / stop cycle on a timer.

The `stopped` event carries `micFramesMixed`. Divide it by
`seconds × 48000` — it should be about 0.99. If it is 0, the mic is not
reaching the file.

`RECORDER_ATTACH_SCREEN=1` attaches a `.screen` output and throws the frames
away. It is not needed (audio works without it) but it is kept for debugging.

`RECORDER_TRACE=/tmp/trace.log` makes the helper append its lifecycle to a file.

`RECORDER_NO_TRANSCRIBE=1` turns transcripts off. With `RECORDER_DEBUG=1` the
transcriber also prints the whisper and ggml logs, which are silent otherwise.

You can run the transcriber by hand:

```bash
./resources/RecorderTranscriber \
  --model ~/Library/Application\ Support/Recorder/models/ggml-small.en.bin \
  --audio ~/Music/Recordings/SOME.m4a \
  --out /tmp/out.srt
```

It writes newline-delimited JSON events on stdout. `SIGTERM` cancels it; it then
exits 0 and leaves a valid SRT that ends on a whole block.

### Regression suite

```bash
pnpm run dist
rm -rf /Applications/Recorder.app && cp -R release/mac-arm64/Recorder.app /Applications/
pnpm test         # runs lint first, then scripts/regression.sh, 9 checks
```

It covers the normal cycle, the pause gap, whether the mic really reaches the
file, killing the app mid-recording, orphan cleanup, and repeated signals.

The ninth check drives the transcriber against a sentence made by `say`. The
selftest recording plays system sounds, not speech, so it correctly produces no
transcript and cannot be used for this. The check prints `SKIP` and passes when
the model is not on the machine.

## Files

```
native/RecorderHelper/Sources/
  main.swift          stdin loop, signals, command dispatch
  Recorder.swift      SCStream setup, mixing, writing
  Resampler.swift     AVAudioConverter wrapper, one per queue
  FloatRing.swift     mic ring buffer, drains into the system buffer
  AudioMath.swift     peak, scale, clamp
  Devices.swift       mic list, default output name
  Permissions.swift   screen and mic checks
  Protocol.swift      JSON commands and events

native/RecorderTranscriber/Sources/RecorderTranscriber/
  main.swift              argv, signals, the chunk loop
  Decode.swift            .m4a to 16 kHz mono float, in ten minute chunks
  Transcribe.swift        whisper.cpp calls and its callbacks
  Srt.swift               one SRT block at a time, flushed
  TranscriptProtocol.swift  JSON events

src/main/     main.ts, helper.ts, paths.ts, settings.ts, protocol.ts, selftest.ts,
              transcribe.ts, model.ts, notify.ts, micMenu.ts, messages.ts,
              transcriptProtocol.ts
src/preload/  preload.ts
src/renderer/ index.html, tokens.css, style.css, renderer.ts, icons/
scripts/      build-helper.sh, build-transcriber.sh, build-whisper.sh, lint.sh,
              smoke.sh, quiet.sh, energy.py, spectrum.py
build/        helper-Info.plist, entitlements.mac.plist, afterPack.cjs, icon.icns
```

## If clipping is audible

`Recorder.swift` sums both sources then clamps. With loud music and a hot mic
this can clip. Change `systemGain` and `micGain` at the top of the class to
`0.7`.

## Privacy & Security

Recorder is built with local-first privacy:
- Audio capture and mic inputs are mixed in-memory and saved directly to your local disk (`~/Music/Recordings/`).
- Local speech-to-text is powered by `whisper.cpp` with Apple Silicon Metal acceleration.
- Zero analytics, telemetry, or remote network requests.

For vulnerability disclosure and full security details, see [SECURITY.md](file:///Users/mmdiqbal/Projects/record-app/SECURITY.md).

## Contributing

Contributions, bug reports, and feature requests are welcome!
- Please read our [CONTRIBUTING.md](file:///Users/mmdiqbal/Projects/record-app/CONTRIBUTING.md) for local setup, development guidelines, and architecture rules.
- Review our [CODE_OF_CONDUCT.md](file:///Users/mmdiqbal/Projects/record-app/CODE_OF_CONDUCT.md) before participating in discussions or issues.

## License

This project is open-source software licensed under the [MIT License](file:///Users/mmdiqbal/Projects/record-app/LICENSE).


