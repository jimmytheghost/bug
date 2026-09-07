# Bug implementation plan

## Confirmed scope

macOS personal use first. Native menu bar app matching Worklog. Record all capturable system audio with optional microphone, show a live waveform and elapsed time, stop explicitly, keep a small local recording library, export high-quality WAV or MP3. No accounts, network service, or uploads.

## Architecture

Swift Package targeting macOS 15+, SwiftUI MenuBarExtra, ScreenCaptureKit, AVFoundation. Main actor store owns user-visible state. Capture runs on a serial sample queue and writes timestamp-aligned system and optional microphone tracks to disk. Export mixes tracks offline, preserving source files. Library lives in Application Support/Bug; capture sessions use unique directories. UI retains errors and protects active capture when quitting.

## Current milestone status · 2026-09-07

- [x] Confirm scope with user: system audio plus optional microphone, persistent library, macOS personal use first.
- [x] Scaffold native Swift package and Worklog-style interface.
- [x] Implement capture, waveform, library, playback, rename, and WAV/MP3 export.
- [x] Bundle the MP3 encoder and create a local signed application.
- [x] Run 21 synthetic tests, release build, and signature verification.
- [x] Initialize Git and push `main` to the private GitHub repository.
- [x] Publish repo-local agent handoff and canonical architecture documentation.
- [ ] Complete live permission/capture/playback/export and login-item acceptance checks.
- [ ] Investigate and prioritize the known gaps in [HANDOFF.md](HANDOFF.md) after live testing.

The original lead/capture/export subagent split is complete. Future work starts from committed source; no running agents or pending patches need collection.

## Module contracts

CaptureEngine: `onLevel: ((Float) -> Void)?`, `onFailure: ((Error) -> Void)?`, `func start(directory: URL, includeMicrophone: Bool) async throws`, `func stop() async throws -> CaptureResult`. Callbacks may run off-main. `CaptureResult` exposes `systemURL: URL`, `microphoneURL: URL?`, `duration: TimeInterval`. Capture outputs timestamp-aligned tracks beginning at a common epoch; silence pads any delayed source. Failed captures preserve any recoverable disk data.

AudioExporter: `enum AudioExportFormat: String, CaseIterable { case wav, mp3 }`; `func export(systemURL: URL, microphoneURL: URL?, to destination: URL, format: AudioExportFormat) async throws`. Offline stereo mix; WAV 48 kHz/24-bit PCM; MP3 320 kbps. No shell command interpolation; atomic destination replacement and source preservation. LAME 3.100 is built locally and bundled in `Contents/Frameworks/libmp3lame.dylib`.

## Validation

Automated implementation validation is recorded in [VALIDATION.md](VALIDATION.md). Run `scripts/test.sh`, not just plain `swift test`, and require an executed test count. Offscreen layout was inspected; desktop automation timed out. Remaining manual tests are tracked in [ACCEPTANCE.md](ACCEPTANCE.md).

## Limits

First recording requires macOS permission. Protected sources may prevent capture. Microphone can capture speaker playback; headphones avoid this. Distribution signing/notarization is outside the first release.

## Scope deferred

Distribution signing/notarization, automatic updates, accounts/cloud sync, per-app capture selection, pause/resume, and global shortcuts are not part of the confirmed first release. Do not silently expand into these features. Canonical implementation details are in [ARCHITECTURE.md](ARCHITECTURE.md).
