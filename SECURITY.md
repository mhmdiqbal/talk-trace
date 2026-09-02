# Security Policy

## Supported Versions

We provide security updates for the following versions of TalkTrace:

| Version | Supported          |
| ------- | ------------------ |
| `main`  | :white_check_mark: |
| Latest  | :white_check_mark: |
| < 1.0.0 | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability or potential privacy issue in TalkTrace, please report it privately through GitHub:

1. Navigate to the **Security** tab of this repository.
2. Click **Report a vulnerability** to open a draft Security Advisory.
3. Include details of the vulnerability, reproduction steps, affected versions, and potential impact.

Please do not open public issues or discussions for undisclosed security vulnerabilities. You can expect an initial response within 48 hours, along with coordinated disclosure timelines.

## Privacy & Security Architecture

TalkTrace is designed with strict on-device privacy principles:

- **Local-Only Audio Processing**: Audio capture via macOS `ScreenCaptureKit` and microphone input are mixed in-memory by a dedicated helper process and written strictly to your local storage (`~/Music/Recordings/`).
- **Local Transcription**: Transcription is executed on your Mac using `whisper.cpp` (Metal accelerated). No audio or text is ever sent to any external server or cloud service.
- **Integrity Verification**: Whisper models downloaded during setup are verified with pre-configured SHA-1 checksums before being loaded into memory.
- **Zero Telemetry**: TalkTrace contains no analytics, telemetry, tracking, or remote logging.
- **Minimal Permissions**: The app requests only the minimum macOS permissions required to function (`Screen Recording` for system audio and `Microphone` for voice). No camera, bluetooth, or location entitlements are requested.
