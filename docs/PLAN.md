# Bug implementation plan

## Confirmed scope

macOS personal use first. Native menu bar app matching Worklog. Record all capturable system audio with optional microphone, show a live waveform and elapsed time, stop explicitly, keep a small local recording library, export high-quality WAV or MP3. Editing includes automatic **Trim** with configurable padding and inline **Custom Trim** with a full-recording waveform and draggable head/tail bounds; both share persistent reversible metadata and Undo. The silence reminder covers initial and later silence: 15/30/60 seconds or Off, 30-second default, either audio source counts, Keep Recording resets the interval, Stop Recording saves, and ignoring continues recording. Library management includes visible Trash controls, size reporting, refresh, and confirmed Delete All including unfinished session folders. No accounts, network service, or uploads.

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
- [x] Add Trim/Undo, configurable padding, persistent non-destructive bounds, and trimmed playback/exports (v0.2.0).
- [x] Pass 33 synthetic tests including Trim and metadata compatibility.
- [x] Add the independent silence reminder panel and persistent gear setting (v0.3.0).
- [x] Pass 46 synthetic tests including reminder timing and store action/lifecycle tests.
- [x] Add visible Trash controls, file and library sizes, and panel refresh (v0.4.0); pass 49 tests in 7 suites.
- [x] Add Settings Delete All with confirmation, snapshot scope, and partial-failure handling (v0.4.1); pass 50 tests in 7 suites.
- [x] v0.4.2: include empty/unfinished UUID session folders in confirmed bulk cleanup; 51 tests pass.

- [x] v0.4.3: move bulk confirmation out of MenuBarExtra into standalone NSAlert; 52 tests pass. User confirmed the successful Delete All flow; broader Cancel/recovery checks remain pending.

- [x] v0.4.4: restore footer breathing room and intrinsic panel sizing after deletion; user confirmed v0.4.3 Delete All works.
- [x] v0.5.0: add inline Custom Trim with bounded waveform analysis, draggable start/end handles, audition controls, Save/Cancel, and shared playback/export bounds; 56 tests in 8 suites pass.
- [ ] Verify live capture after [canonical installation and scoped permission repair](PERMISSIONS.md), including the next changed build. Stable certificate signing is optional future work; the user accepts normal reapproval.
- [ ] Complete live permission/capture/playback/export and login-item acceptance checks.
- [ ] Investigate and prioritize the known gaps in [HANDOFF.md](HANDOFF.md) after live testing.

The original lead/capture/export subagent split is complete. Future work starts from committed source; no running agents or pending patches need collection.

## Module contracts

CaptureEngine: `onLevel: ((Float) -> Void)?`, `onFailure: ((Error) -> Void)?`, `func start(directory: URL, includeMicrophone: Bool) async throws`, `func stop() async throws -> CaptureResult`. Callbacks may run off-main. `CaptureResult` exposes `systemURL: URL`, `microphoneURL: URL?`, `duration: TimeInterval`. Capture outputs timestamp-aligned tracks beginning at a common epoch; silence pads any delayed source. Failed captures preserve any recoverable disk data.

AudioExporter: `enum AudioExportFormat: String, CaseIterable { case wav, mp3 }`; `func export(systemURL: URL, microphoneURL: URL?, to destination: URL, format: AudioExportFormat, trimRange: AudioTrimRange? = nil) async throws`. Offline stereo mix; WAV 48 kHz/24-bit PCM; MP3 320 kbps. No shell command interpolation; atomic destination replacement and source preservation. LAME 3.100 is built locally and bundled in `Contents/Frameworks/libmp3lame.dylib`.

## Validation

Automated implementation validation is recorded in [VALIDATION.md](VALIDATION.md). Run `scripts/test.sh`, not just plain `swift test`, and require an executed test count. Offscreen layout was inspected; desktop automation timed out. Remaining manual tests are tracked in [ACCEPTANCE.md](ACCEPTANCE.md).

## Limits

First recording requires macOS permission. Protected sources may prevent capture. Microphone can capture speaker playback; headphones avoid this. Distribution signing/notarization is outside the first release.

## Scope deferred

Automatic retention and low-disk warnings are follow-up candidates; Trash/size/refresh shipped in v0.4.0; confirmed bulk deletion shipped in v0.4.1.


Distribution signing/notarization, automatic updates, accounts/cloud sync, per-app capture selection, pause/resume, and global shortcuts are not part of the confirmed first release. Do not silently expand into these features. Canonical implementation details are in [ARCHITECTURE.md](ARCHITECTURE.md).

- [x] Add canonical installer with identity comparison and scoped reset before reapproval; require it for every future delivery. Actual post-repair capture verification remains pending.
