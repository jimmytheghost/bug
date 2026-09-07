# Canonical architecture

Updated **2026-09-07** against the v0.2.0 implementation. Product scope is in [PLAN.md](PLAN.md); current gaps and next work are in [HANDOFF.md](HANDOFF.md).

## Product and design decisions

Bug is a native macOS 15+ SwiftUI menu bar app for personal use. It follows Worklog's 360-point panel, mint accent, system typography, subtle rounded cards, header settings control, and footer actions. `LSUIElement` removes the normal Dock presence. There is no web runtime, server, account, upload, or sibling-project runtime dependency.

The user explicitly chose optional microphone capture and a persistent recording library. A Record click starts the permission/start flow; no capture begins on launch. Once authorized, capture starts without a source-selection step. Stop finalizes lossless sources before adding the recording to the library. WAV and MP3 are export formats, not the live capture storage format.

## Source map

| File in `Sources/Bug/` | Responsibility |
| --- | --- |
| `BugApp.swift` | `MenuBarExtra`, persistent store, recording menu icon, termination protection |
| `BugMenuView.swift` | Recorder panel, waveform canvas, library rows/actions, settings and login-item control |
| `RecorderStore.swift` | Main-actor state, capture callbacks, library coordination, save panel, playback and errors |
| `RecordingLibrary.swift` | Recording metadata, per-session paths, JSON persistence, sorted load, Trash |
| `CaptureEngine.swift` | ScreenCaptureKit configuration, permissions, lifecycle actor, bounded callback delivery, recovery |
| `CapturePCMWriter.swift` | Float32 CAF writes, timestamp alignment, silence padding and readable-track salvage |
| `AudioExporter.swift` | Streaming resampling/mixing, peak scan, WAV serialization, destination protection and atomic commit |
| `AudioTrimmer.swift` | Conservative boundary scan and persistent 48 kHz trim range |
| `ExportMP3Encoder.swift` | Dynamically loaded LAME API, 320 kbps MP3 encoding |

`Resources/Info.plist` defines bundle ID `com.jimmyweber.bug`, version 0.2.0, deployment target, usage descriptions, and menu-only behavior. `Package.swift` uses a Swift 5.9 manifest/Swift 5 language mode; tests use Swift Testing. The verified compiler is Swift 6.3.3.

## State and user actions

`RecorderStore.Phase` is `idle → starting → recording → stopping → idle`. Start failures return to idle with an error. Controls disable repeated start/stop and microphone changes while busy. The store handles a capture failure arriving during startup, and attempts to finalize recoverable audio when interrupted while recording.

The menu bar recording symbol persists while the panel is closed. A 50 ms timer updates elapsed time and a fixed 64-level waveform history. The engine reports RMS at most about 20 times/second; levels older than 200 ms become silence. The displayed elapsed clock begins after startup succeeds; source alignment uses the earlier host-clock capture epoch.

Starting capture stops preview playback. Preview is disabled during capture and uses a temporary mixed WAV plus `AVAudioPlayer`. Quit is blocked while capture is starting/running/stopping or a Trim analysis or export/save dialog is active. The microphone preference is stored under `includeMicrophone` in UserDefaults. Login at startup uses `SMAppService.mainApp` and macOS approval state.

## Capture contract and concurrency

```swift
CaptureEngine.onLevel: ((Float) -> Void)?
CaptureEngine.onFailure: ((Error) -> Void)?
CaptureEngine.start(directory: URL, includeMicrophone: Bool) async throws
CaptureEngine.stop() async throws -> CaptureResult
// CaptureResult: systemURL: URL, microphoneURL: URL?, duration: TimeInterval
```

Callbacks may execute off-main; the store hops to the main actor. A lifecycle actor serializes start/stop and coalesces concurrent stops. Capture has separate serial ingress/writer queues, a gate, and a 16-slot semaphore. Oversized buffers (over 16,384 samples or 1 MiB) or overload stop acceptance and report failure rather than allowing an unbounded retained-buffer queue.

ScreenCaptureKit uses the first available display with no excluded windows. It captures system audio at 48 kHz stereo, includes the current process's audio, and optionally captures the default microphone at its native rate. Screen output is configured minimally and discarded. Microphone permission is requested before system capture when enabled. PCM ingestion supports mono/stereo at 8–192 kHz.

Each source's timestamps are relative to one host-clock epoch. Writers insert leading/intermediate/trailing silence and trim pre-epoch samples/overlaps. System sources are 48 kHz stereo Float32 CAF; microphone sources retain native mono/stereo rate in Float32 CAF. Writes and padding use bounded buffers. Format changes and write failures trigger best-effort recovery; source files are not deleted on failure. Recovery can return shorter readable tracks, and export pads their tails.

## Persistence contract

```text
~/Library/Application Support/Bug/Recordings/
  <UUID>/
    system.caf
    microphone.caf       # optional
    recording.json       # created on successful finalization/recovery
```

`Recording` has `id: UUID`, `createdAt: Date`, `title: String`, `duration: TimeInterval`, `systemFilename: String`, and `microphoneFilename: String?`. The default `JSONEncoder`/`JSONDecoder` strategies encode dates as seconds relative to Foundation's reference date (2001-01-01), not ISO strings or Unix timestamps. `trimRange: AudioTrimRange?` is an optional backward-compatible edit field; older metadata without it decodes as untrimmed. `duration` remains the full original duration, and `playbackDuration` reflects the trim when present. Metadata has no schema version or migration layer. Preserve compatibility or introduce an explicit migration when changing it.

JSON writes are atomic. Load orders recordings newest first, skips directories without metadata, and rejects mismatched directory/recording IDs or source filenames containing paths. An invalid metadata entry currently throws for the entire load. Rename only rewrites metadata. Delete moves the whole source directory to Trash; exported copies remain elsewhere. Capture storage and exported destinations are separate; there is no automatic retention.

## Export contract

```swift
enum AudioExportFormat: String, CaseIterable, Sendable { case wav, mp3 }
AudioExporter.export(systemURL: URL, microphoneURL: URL?,
                     to destination: URL, format: AudioExportFormat,
                     trimRange: AudioTrimRange? = nil) async throws
```

Export runs in a detached utility task with cancellation forwarding. Tracks must be finalized and immutable. Streaming conversion uses 4096-frame buffers, resamples to 48 kHz, duplicates mono into stereo, and pads shorter tracks. When a trim is present, both passes consume only its half-open frame range; invalid or out-of-file bounds fail without replacing a destination. Pass one measures the selected audio's summed peak; pass two applies constant gain `min(1, 0.95 / peak)`, without boosting silence/quiet material. This is sample-peak headroom, not a true-peak limiter.

WAV is little-endian stereo 24-bit PCM in classic RIFF, with a 4 GiB limit (about 4.14 hours). MP3 uses bundled LAME 3.100, CBR 320 kbps, 48 kHz joint stereo, quality 2, normalized float input. MP3 has encoder delay/padding and no gapless Xing/LAME header. WAV quantization rounds without dither.

Source equality, symlinks, and hard-link aliases are checked before writing and before committing. Output is written to a hidden same-directory staging file and renamed atomically after synchronization and a cancellation check. Errors/cancellation before commit preserve sources and an existing destination. A crash can leave the staging file; cancellation after commit cannot undo the completed export.

## Trim contract

`AudioTrimmer.analyze(systemURL:microphoneURL:padding:) async throws -> AudioTrimRange?` reads finalized sources using the same `ExportTrack` 48 kHz resampler as export. It scans each source independently and checks each stereo sample's absolute peak against 0.001 (-60 dBFS). The first/last above-threshold frame across all sources sets the outer activity bounds. Channels and sources are not summed for detection, so phase cancellation cannot erase activity. Interior silence is never removed.

Padding defaults to 0.5 seconds, validates within 0–2 seconds, and clamps the proposed bounds to the available source timeline. No new silence is inserted. All-silent/empty sources and ranges with no removable silence return nil. The scan uses bounded buffers, runs off-main in a utility task, and forwards cancellation. It scans the entire recording, so long recordings take time; the UI shows a spinner without a progress estimate or a cancel button.

`AudioTrimRange` stores `startFrame: Int64` and `endFrame: Int64` (exclusive) in the 48 kHz timeline. The loader validates nonnegative, increasing bounds; export verifies that the end exists in source data. Analysis never changes CAF files. The store saves the optional range atomically in `recording.json`, then updates the displayed duration. Rename resolves current state so an older UI snapshot cannot discard the edit. Undo clears the saved range and restores the original duration, also after relaunch. Failure to save metadata does not pretend the edit succeeded. Repeated Trim requests on an already trimmed recording are ignored; Undo permits a new analysis from the original sources.

During Trim, capture/playback/other trims and exports are blocked, and the target cannot be renamed or deleted. Trim and Undo stop active preview playback to avoid playing stale audio. Save/export blocks Trim so the bounds cannot change while an export dialog or encoding task is active. Settings stores `trimPadding` in UserDefaults; changes affect future analyses only.

This is fixed-threshold boundary detection, not semantic song/speech detection or noise removal. Above-threshold noise stays; extremely quiet material below the threshold may be excluded beyond the retained padding. Existing exports are never retroactively edited. The original source storage size is unchanged.

## Packaging and dependencies

`scripts/prepare-encoder.sh` downloads pinned LAME source, verifies SHA-256, applies the documented export-list adjustment, builds locally, and writes ignored encoder artifacts. `scripts/package-app.sh` builds release Bug and places the dylib in `Contents/Frameworks`; source archive, license, notice, and build recipe go in `Contents/Resources/Encoder`. The nested dylib is ad-hoc signed before the app. No global Homebrew/FFmpeg dependency is used.

Default MP3 loading uses only the absolute bundled dylib path. Unbundled tests pass an explicit encoder URL. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) for the pinned dependency and exact packaging details.

## Validation boundaries

Use [VALIDATION.md](VALIDATION.md) for dated results and [ACCEPTANCE.md](ACCEPTANCE.md) for real-device checks. Synthetic PCM tests validate writers, conversion, export, and metadata; they do not exercise ScreenCaptureKit permission dialogs or an actual system audio stream. App appearance previews do not prove interaction behavior.
