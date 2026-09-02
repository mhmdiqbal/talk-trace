# Contributing to TalkTrace

Thank you for your interest in contributing to TalkTrace! This document outlines the development workflow, prerequisites, architecture rules, and quality gates for the project.

---

## Prerequisites

To build and test TalkTrace locally, you will need:

- **Hardware & OS**: Apple Silicon Mac (M1/M2/M3/M4) running **macOS 15 (Sequoia)** or later (`ScreenCaptureKit` audio capture requires macOS 15+).
- **Node.js & Package Manager**: Node.js `>= 22` and **pnpm 11** (run `corepack enable` to use the pinned version).
- **Swift / Xcode**: Xcode or Command Line Tools with `swift` and `clang` installed.
- **Build Tools & Linters**:
  ```bash
  brew install cmake shellcheck ruff
  ```
  *(Note: `swift-format` is included with the Xcode/Swift toolchain).*

---

## Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/mhmdiqbal/talk-trace.git
   cd talk-trace
   ```

2. **Install dependencies**:
   ```bash
   pnpm install
   ```

3. **Build and run locally**:
   ```bash
   pnpm start
   ```
   *Note: On your first build, `scripts/build-whisper.sh` downloads and compiles `whisper.cpp` into `native/vendor/`. This takes a couple of minutes and is cached thereafter.*

---

## Code Signing & Permissions

### Code Signing
TalkTrace relies on a signed audio helper binary (`TalkTraceHelper`) to maintain persistent macOS `Screen Recording` and `Microphone` TCC grants.

- By default, `scripts/build-helper.sh` and `scripts/build-transcriber.sh` auto-detect any valid `Apple Development` certificate in your macOS Keychain.
- If you have multiple certificates or want to specify one explicitly:
  ```bash
  TALKTRACE_IDENTITY="Apple Development: Your Name (TEAMID)" pnpm start
  ```
- If no Apple Developer certificate is found, build scripts fall back to ad-hoc (`-`) signing.

### macOS Permissions
`TalkTrace.app` requires two macOS permissions:
1. **Screen Recording**: Required by macOS `ScreenCaptureKit` to capture system audio. No video is ever recorded.
2. **Microphone**: Required to record your voice into the audio mix.

The permissions belong to the helper binary (`TalkTraceHelper`), not Electron. Grant them when prompted or via **System Settings > Privacy & Security**.

---

## Architectural Rules & Guardrails

When modifying the codebase, please adhere to these core rules:

### 1. Dual Protocol Synchronization
There are two protocol pairs that must remain in sync by hand:
- **Audio Protocol**: [`src/main/protocol.ts`](file:///Users/mmdiqbal/Projects/record-app/src/main/protocol.ts) ↔ [`native/TalkTraceHelper/Sources/Protocol.swift`](file:///Users/mmdiqbal/Projects/record-app/native/TalkTraceHelper/Sources/Protocol.swift)
- **Transcript Protocol**: [`src/main/transcriptProtocol.ts`](file:///Users/mmdiqbal/Projects/record-app/src/main/transcriptProtocol.ts) ↔ [`native/TalkTraceTranscriber/Sources/TalkTraceTranscriber/TranscriptProtocol.swift`](file:///Users/mmdiqbal/Projects/record-app/native/TalkTraceTranscriber/Sources/TalkTraceTranscriber/TranscriptProtocol.swift)

Any change to command or event payloads must update both the TypeScript definition and the Swift Codable struct together.

### 2. Three-Process Architecture
- **Electron Main/Renderer (`src/`)**: Owns the menu bar tray, popup UI, global hotkeys, and application lifecycle.
- **TalkTraceHelper (`native/TalkTraceHelper/`)**: Signed Swift binary holding the audio pipeline. Communicates with Electron via newline-delimited JSON over stdout. Recording state lives in Swift as the source of truth.
- **TalkTraceTranscriber (`native/TalkTraceTranscriber/`)**: Standalone Swift binary embedding `whisper.cpp`. Spawned on-demand per transcription job.

### 3. Popup Sizing & Vibrancy
- The popup window uses macOS vibrancy (`vibrancy: "popover"`).
- Window height is managed in [`src/main/main.ts`](file:///Users/mmdiqbal/Projects/record-app/src/main/main.ts) via `popupHeight()`. If you modify renderer layout dimensions, recalculate the bounding dimensions.
- Keep `[hidden] { display: none !important }` as the first rule in [`src/renderer/tokens.css`](file:///Users/mmdiqbal/Projects/record-app/src/renderer/tokens.css).

### 4. Modular Main Process
Keep `src/main/main.ts` concise and modular:
- IPC handlers are registered in `registerIpc()`.
- Menu logic belongs in [`src/main/micMenu.ts`](file:///Users/mmdiqbal/Projects/record-app/src/main/micMenu.ts).
- User-facing message formatters belong in [`src/main/messages.ts`](file:///Users/mmdiqbal/Projects/record-app/src/main/messages.ts).

---

## Quality Gates & Testing

Before submitting a pull request, ensure all checks pass:

### Linting
```bash
pnpm lint
```
This runs all 5 linting passes and fails at the first error:
1. `tsc --noEmit` (TypeScript typechecks for both main and renderer configs)
2. `eslint` (Strict TypeScript and stylistic rules)
3. `swift format lint --strict`
4. `shellcheck scripts/*.sh`
5. `ruff check` & `ruff format --check`

### Regression Testing
```bash
pnpm run dist
rm -rf /Applications/TalkTrace.app && cp -R release/mac-arm64/TalkTrace.app /Applications/
pnpm test
```
The regression suite runs 9 automated checks verifying recording, pausing, mic levels, orphan cleanup, signal handling, and transcriber execution.

---

## Submitting Pull Requests

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. Commit your changes with clear, conventional commit messages (`feat:`, `fix:`, `docs:`, `chore:`).
3. Ensure `pnpm lint` and tests pass cleanly.
4. Push your branch to GitHub and open a Pull Request using the provided PR template.
5. Participate in the code review process.
