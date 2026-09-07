# Validation · 2026-09-07

## Current release · v0.3.0 Silence reminder

- The user reported an accidentally forgotten recording producing over 1 GB of silence. This is the motivation for the reminder; it does not establish live signal quality or all earlier acceptance results.
- `swift build` and release packaging passed. v0.3.0 Info.plist and `codesign --verify --deep --strict` passed. The previous bundle was preserved under ignored `dist/previous/`, with no termination of the running app. Quit/reopen is required to load the new code.
- `scripts/test.sh`: **46 executed tests in 6 suites passed**, including all 33 prior tests and 13 new reminder state/store tests.
- New tests use an injected clock, fake capture with tiny synthetic CAF files, and a fake presenter. They cover 15/30/60-second deadlines, initial/no-buffer and later silence, Off/idle, quiet and invalid levels, ignored reminders, Keep resetting the clock, automatic dismissal on resumed audio, live setting changes, preference persistence, stale actions after restart, normal Stop/save exactly once, and start/stop error cleanup.
- The store reminder tests instantiate no menu bar view, verifying that timer/action routing does not depend on the popover being open. They do not verify actual macOS popup visibility.
- Isolated offscreen renders of the actual popup content and gear settings were visually inspected. No live audio was captured by these tests and no real reminder was shown to the user during verification.
- Documentation links and diff formatting checked. Real source/microphone detection, popup button interaction, visibility over other apps/Spaces/full-screen, and remaining recording acceptance require the checklist in [ACCEPTANCE.md](ACCEPTANCE.md).

## Previous release · v0.2.0 Trim

- `swift build` passed on the same Apple Silicon/macOS/Swift host documented below.
- `scripts/test.sh`: **33 executed tests in 4 suites passed**, including 12 Trim tests and all 21 existing tests.
- Verified the 8-second silent head / 10-second silent tail example, 0.5-second padding, internal-pause preservation, stereo channels, quiet audio, phase-cancelling sources, microphone resampling, no-op/silent/short tracks, and adjustable/clamped padding.
- Verified trimmed WAV samples/duration and actual MP3 decode duration; source bytes stay unchanged. Invalid bounds/cancellation preserve an existing destination. Metadata read/write tests cover legacy recordings, saved Trim across relaunch, Undo, stale rename requests, repeated Trim, missing sources, and write failures for both Trim and Undo.
- Offscreen isolated-fixture layout checks covered the **Trim** button, **Undo**/trimmed duration, and padding settings. They did not exercise live UI clicks or capture real audio.
- v0.2.0 release packaging, Info.plist, bundled encoder notices, and `codesign --verify --deep --strict` passed. Updated `dist/Bug.app` is approximately 3.3 MB.
- The prior running app was not terminated. Its bundle was preserved under ignored `dist/previous/` before the new bundle was moved into place. Quit and reopen to use v0.2.0; no active recording was deliberately interrupted.
- Documentation links and diff formatting checked. Real-device and live-listening Trim acceptance remains pending in [ACCEPTANCE.md](ACCEPTANCE.md).

## Original release evidence · v0.1.0

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
