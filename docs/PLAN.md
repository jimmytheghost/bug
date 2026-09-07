# Bug implementation plan

## Confirmed scope

macOS personal use first. Native menu bar app matching Worklog. Record all capturable system audio with optional microphone, show a live waveform and elapsed time, stop explicitly, keep a small local recording library, export high-quality WAV or MP3. No accounts, network service, or uploads.

## Architecture

Swift Package targeting macOS 15+, SwiftUI MenuBarExtra, ScreenCaptureKit, AVFoundation. Main actor store owns user-visible state. Capture runs on a serial sample queue and writes timestamp-aligned system and optional microphone tracks to disk. Export mixes tracks offline, preserving source files. Library lives in Application Support/Bug; capture sessions use unique directories. UI retains errors and protects active capture when quitting.

## Work allocation

- Lead: repository scaffold, application state, library, interface, integration, validation.
- Capture agent: CaptureEngine.swift and capture-specific helpers/tests.
- Export agent: AudioExporter.swift, encoder integration and export-specific helpers/tests.

## Module contracts

CaptureEngine: `onLevel: ((Float) -> Void)?`, `onFailure: ((Error) -> Void)?`, `func start(directory: URL, includeMicrophone: Bool) async throws`, `func stop() async throws -> CaptureResult`. Callbacks may run off-main. `CaptureResult` exposes `systemURL: URL`, `microphoneURL: URL?`, `duration: TimeInterval`. Capture outputs timestamp-aligned tracks beginning at a common epoch; silence pads any delayed source. Failed captures preserve any recoverable disk data.

AudioExporter: `enum AudioExportFormat: String, CaseIterable { case wav, mp3 }`; `func export(systemURL: URL, microphoneURL: URL?, to destination: URL, format: AudioExportFormat) async throws`. Offline stereo mix; WAV 48 kHz/24-bit PCM; MP3 320 kbps. No shell command interpolation; atomic destination replacement and source preservation. Include encoder in packaged app if feasible.

## Validation

Compile/debug and release package. Test library persistence and failure cases, PCM conversion/mixing and export with synthetic audio. Inspect UI without capturing user audio. Manual acceptance: grant macOS permissions, record system audio, test optional microphone and headphones, stop/reopen library, play both exported formats, test permission denial and interruptions.

## Limits

First recording requires macOS permission. Protected sources may prevent capture. Microphone can capture speaker playback; headphones avoid this. Distribution signing/notarization is outside the first release.
