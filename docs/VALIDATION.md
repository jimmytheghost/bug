# Validation · 2026-09-07

Host: Apple Silicon, macOS 26.6.2, Swift 6.3.3 Command Line Tools. App deployment target: macOS 15.

Implementation baseline: `f468070`. This is a historical evidence record, not a claim that tests were rerun for later documentation-only commits. See [HANDOFF.md](HANDOFF.md) for current status and [ARCHITECTURE.md](ARCHITECTURE.md) for implementation contracts.

## Passed

- Debug build and release packaging.
- `scripts/test.sh`: **21 executed tests in 3 suites**, all passed.
- Capture tests: timestamp alignment, leading/trailing silence, gaps/overlaps, native microphone format, integer PCM conversion, real RMS, invalid samples/timestamps, recoverable interruptions, disk-write failure, and idle-stop behavior.
- Export tests: 24-bit WAV header, stereo and mono mixing, 44.1 → 48 kHz conversion, constant peak attenuation, longer microphone tail, actual 320 kbps MP3 encoding and AVFoundation decoding, atomic replacement, cancellation/failure preservation, and source-path protection.
- Library tests: metadata round trip, chronological ordering, rename persistence, unfinished-session filtering, and path validation.
- `codesign --verify --deep --strict dist/Bug.app`; Info.plist validation.
- Bundled encoder, license, source archive, and build recipe present. No global encoder dependency. Package approximately 3.1 MB.
- Packaged app launched successfully; process remained running without starting capture.

## Not yet verified

Desktop automation timed out reading Bug's menu bar UI. An offscreen SwiftUI/AppKit render was used for layout inspection; this does not verify interactive behavior.

Live ScreenCaptureKit capture, macOS permission prompts, microphone/system sound alignment with real devices, long-running sessions, FaceTime, sleep/device changes, and login-item behavior require the hands-on checks in [ACCEPTANCE.md](ACCEPTANCE.md). No live user audio was captured during development. User feedback did not explicitly confirm those checks. Intel, a universal app, and a separate macOS 15 host have not been tested.

## Test runner note

Plain `swift test` initially compiled the suite but executed zero tests because SwiftPM's generated runner could not import the standalone CLT Testing framework. `scripts/test.sh` supplies framework search paths to the generated runner as well as the test target. The explicit 21-test result above is from this corrected runner.

The corrected runner exposed a test-side buffer-lifetime crash. Capture tests now retain their `AVAudioPCMBuffer` and use `withExtendedLifetime` around unsafe channel reads; the full 21-test suite passed afterward. Keep these lifetimes explicit when adding pointer-based assertions.

## Documentation and repository check · 2026-09-07

GitHub reported `jimmytheghost/bug` as PRIVATE, with `main` synchronized to the initial implementation before documentation edits. README, agent instructions, plan, acceptance status, and encoder packaging notes were reconciled against source. Added canonical architecture and a current handoff. Repository-local Markdown links, code fences, and the documentation diff were checked. This review did not launch the app, record audio, or rerun the audio suite.
