## Description

<!-- Describe what your PR accomplishes, why it is needed, and link any related issues. -->

Fixes # <!-- (issue number, if applicable) -->

## Type of Change

- [ ] 🐛 Bug fix (non-breaking change fixing an issue)
- [ ] ✨ New feature (non-breaking change adding functionality)
- [ ] 🛠️ Refactoring / Code cleanup
- [ ] 📝 Documentation update
- [ ] 🔧 Build / CI / Tooling improvement

## Contributor Checklist

- [ ] I have read the [CONTRIBUTING.md](file:///Users/mmdiqbal/Projects/record-app/CONTRIBUTING.md) guide.
- [ ] `pnpm lint` passes with 0 errors (`typecheck`, `eslint`, `swift format`, `shellcheck`, `ruff`).
- [ ] If changing audio or transcript payloads, both `protocol.ts` / `transcriptProtocol.ts` and their Swift counterparts (`Protocol.swift` / `TranscriptProtocol.swift`) were updated in sync.
- [ ] Verified manually on an Apple Silicon Mac running macOS 15+.
- [ ] Regression suite passes (`pnpm test`) if modifying core audio, helper, or transcriber behavior.
