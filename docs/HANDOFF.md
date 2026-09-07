# Agent handoff

Last updated: **2026-09-07**. Version **0.3.0**. This is the current-state entry point; [ARCHITECTURE.md](ARCHITECTURE.md) is the implementation canon.

## Where we left off

Bug's first implementation is complete and committed as `f468070` (`Build Bug native menu bar audio recorder`). It was pushed to the private [jimmytheghost/bug](https://github.com/jimmytheghost/bug) repository. The default branch is `main`, tracking `origin/main`. v0.2.0 added Trim/Undo (`28cf6cd`); v0.3.0 adds silence reminders. Use `git log` for the current revision.

The user confirmed system audio with an optional microphone, a small local library with WAV/MP3 export, and macOS personal use first. They approved the appearance and requested private GitHub hosting and complete handoff documentation. They then approved a feature named **Trim**, immediate application with Undo, and 0.5-second default padding. That feature is implemented in v0.2.0. They reported forgetting an active recording and finding over 1 GB of silence. This motivated the v0.3.0 silence reminder. They approved initial/later silence detection, 30 seconds by default with 15/60/Off options, either source as activity, Keep Recording/Stop Recording, and continued recording if ignored. This report does not establish audio signal quality or full acceptance coverage.

The local checkout used for development is `/Users/jimmytheghost/Dropbox/_Personal Projects/bug`. The design reference is the sibling `/Users/jimmytheghost/Dropbox/_Personal Projects/agent-dashboard` (Worklog). That app was inspected, not modified. Bug has no runtime dependency on that checkout.

The local artifact is v0.3.0 at `dist/Bug.app`; bundle ID `com.jimmyweber.bug`. Previous bundles are preserved under ignored `dist/previous/` when updating the local package; no active recording is terminated. The user must quit/reopen to load an update. **Do not assume the running app matches the latest build:** inspect current state, and never terminate a potentially active recording to refresh a build. No installer, GitHub release, CI workflow, or remote build service is configured.

## Verified baseline

- Apple Silicon, macOS 26.6.2, Swift 6.3.3 Command Line Tools.
- Debug build, release bundle, and ad-hoc signature verification passed.
- 46 executed Swift Testing tests in 6 suites passed, including real MP3 encode/decode, Trim bounds, persistent Undo, source preservation, and silence reminder timing/actions using synthetic audio.
- Offscreen AppKit/SwiftUI layout inspected; desktop automation timed out.
- Development tests captured no live user audio. The user reported a long accidental silent recording; live signal quality, permission flows, FaceTime, device changes, sleep, reminder window behavior, and launch at login still need acceptance checks.

See [VALIDATION.md](VALIDATION.md) for evidence and [ACCEPTANCE.md](ACCEPTANCE.md) for pending tests. macOS 15 is the deployment target, not a separately tested host; Intel has not been tested.

## Resume commands

Run from the repository root on macOS:

```sh
git status --short --branch
git remote -v
swift build
# Required on a fresh clone before the MP3 test; no global installation.
./scripts/prepare-encoder.sh
./scripts/test.sh
./scripts/package-app.sh
codesign --verify --deep --strict dist/Bug.app
```

`scripts/test.sh` must print a test count. Plain `swift test` previously built tests but silently executed none because the generated runner lacked the CLT Testing framework search path. MP3 tests require `Resources/Encoder/libmp3lame.dylib` and fail explicitly when it is missing. The `.build/` directory, `dist/`, encoder dylib, and encoder source archive are ignored by Git. The upstream license and app icon are committed.

Packaging builds the host architecture. The encoder script supports `ARCHS="arm64 x86_64"`, but that alone does not create a universal app executable. Rebuild the encoder if moving a cached checkout between architectures. Packaging only checks whether the dylib exists; rerun preparation if companion source/license artifacts are missing. Network access is used only to acquire the pinned build dependency, not at app runtime.

### Offscreen layout preview

The render helper now injects an isolated temporary library and preference suite; it does not read personal recordings or record audio. Use `--trim-fixture`, `--trimmed-fixture`, `--settings`, or `--silence-reminder` for synthetic layout states. Fixture metadata is only for layout and has no playable source files.

On the original Apple Silicon host:

```sh
mkdir -p .build/qa
swiftc -parse-as-library -target arm64-apple-macosx15.0 \
  Sources/Bug/AudioExporter.swift Sources/Bug/AudioTrimmer.swift Sources/Bug/ExportMP3Encoder.swift \
  Sources/Bug/CaptureEngine.swift Sources/Bug/CapturePCMWriter.swift \
  Sources/Bug/RecordingLibrary.swift Sources/Bug/RecorderStore.swift \
  Sources/Bug/SilenceMonitor.swift Sources/Bug/SilenceReminderPresenter.swift \
  Sources/Bug/BugMenuView.swift scripts/render-preview.swift \
  -o .build/qa/render-preview
.build/qa/render-preview .build/qa/bug-panel.png --trim-fixture
```

AppKit hosting is intentional: a pure SwiftUI `ImageRenderer` rendered native switches as unsupported placeholders. This preview checks layout only, not clicks or menu bar behavior.

## Next actions

1. Run the live acceptance checklist with a deliberate test source and the user's permissions. Record the observed outcomes; do not infer them from the synthetic suite.
2. Investigate any real capture or export failures before adding features. Preserve source files when troubleshooting.
3. Prioritize the known gaps below with the user. They are observations and follow-up candidates, not approved scope expansion.
4. Update the affected canon and validation record, commit, and push completed changes. Preserve the repository's private visibility.

## Trim handoff

The feature is named **Trim** throughout the UI. Each saved recording has a visible button (and menu action); after analysis the button becomes **Undo** and the displayed duration uses the selected bounds. Undo survives relaunch. Settings offers 0, 0.25, 0.5 (default), 1, and 2 seconds of padding. Existing edits are unchanged by settings changes; Undo before retrimming with different padding.

Original CAF files are immutable. Only optional `trimRange` metadata is saved; playback and both export formats pass this range to the exporter. Legacy recordings decode as untrimmed. No-op and analysis/save errors preserve the recording. The 33-test result covers the user's 8-second/10-second example, interior pauses, stereo and microphone/resampling behavior, silent/short/noisy tracks, invalid bounds, cancellation, persistent Undo/rename, and metadata write failures.

Detection uses a fixed -60 dBFS sample-peak threshold and is conservative, not semantic: noise may prevent trimming and very quiet fades may be excluded beyond padding. Live listening/interaction acceptance is still pending. See [ARCHITECTURE.md](ARCHITECTURE.md#trim-contract) for exact contracts.

## Silence reminder handoff

v0.3.0 adds **Silence reminder** under gear settings: Off, 15 seconds, 30 seconds (default), and 1 minute. It is active from the start of actual capture and after any later silence. Either source's live RMS can reset the timer. The standalone nonmodal popup works independently of the menu bar view and does not block recording.

**Keep Recording** resets the timer, **Stop Recording** calls normal stop/save, and ignoring keeps recording. One reminder stays pending rather than creating repeated windows. Audio resuming dismisses it automatically. Off, setting changes, manual Stop, and recording failures dismiss it as well. Token checks fence callbacks from previous reminders/sessions. Timing uses a monotonic clock and ticks even when no audio buffers arrive.

13 new synthetic state/store tests bring the suite to 46. They require no wall-clock waits and no actual recording or popup. Offscreen popup/settings layout was checked; live window placement, full-screen visibility, real source detection, and listening remain pending. Background noise above -60 dBFS RMS counts as activity; the reminder is not a recording-size cap. See [ARCHITECTURE.md](ARCHITECTURE.md#silence-reminder-contract).

## Known gaps and operational caveats

- **Crash recovery is partial.** Capture can salvage readable tracks during handled interruptions, and the store can add the resulting recording to the library. A crash, failed start, or metadata write failure can leave a directory without `recording.json`; startup ignores these directories. There is no journal, automatic reimport, or recovery UI. Preserve them for manual recovery.
- **One corrupt metadata file can fail the whole library load.** The loader rejects bad JSON, mismatched IDs, and non-basename source paths. It does not quarantine a bad entry or verify all source files exist when listing. Missing audio is reported when playback/export tries to open it.
- **Long recordings use disk space.** Float32 stereo system audio is about 1.4 GB/hour plus native microphone audio. Silence is written in bounded chunks, not sparse files. There is no quota, free-space preflight, automatic retention, or rotation.
- **Playback prepares the selected mixed WAV.** It can be slow and needs extra temporary disk space; it shares WAV's roughly 4.14-hour limit. MP3 export can still work above that WAV limit. A force quit may leave a temporary preview or export staging file.
- **Capture requires an available display filter and permissions.** No video is saved, but ScreenCaptureKit receives and discards screen callbacks. Protected sources may be unavailable. Multichannel microphones beyond mono/stereo are rejected during ingestion; device format changes interrupt capture.
- **Export progress is indeterminate.** The UI has a spinner and a cancellable save dialog, but no explicit cancel/progress control once encoding begins. The exporter supports task cancellation internally.
- **Local signing only.** No Developer ID, notarization, sandbox distribution configuration, auto-update, or verified Intel/universal release. Launch-at-login behavior still needs packaged-app testing.

Do not describe these caveats as fixed until code and evidence support that claim.
