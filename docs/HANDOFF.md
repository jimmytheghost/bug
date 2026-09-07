# Agent handoff

Last updated: **2026-09-07, Custom Trim checkpoint**. Current source/staged version: **0.5.0**, build **9**. Read this first, then [ARCHITECTURE.md](ARCHITECTURE.md) for implementation contracts.

## Current state

- The v0.5.0 implementation adds inline Custom Trim. Use `git log -1` for the latest committed revision.
- Private repository: [jimmytheghost/bug](https://github.com/jimmytheghost/bug). Branch `main` tracks `origin/main`. GitHub privacy was rechecked for this handoff.
- Latest artifact: `dist/updates/v0.5.0/Bug.app`. At packaging time the canonical installed v0.4.4 app was still running, so it was deliberately not terminated or replaced. Install only with `scripts/install-app.py` after the user stops any recording and quits Bug.
- Latest executed validation: **56 tests in 8 suites passed**, debug build, release packaging, and deep/strict ad-hoc signature verification. The inline Custom Trim state was rendered and visually checked at the real 360-point width.
- The user confirmed v0.4.3 Delete All works. Their screenshot showed 13 session folders moved and zero saved recordings remaining. This confirms the successful deletion flow, not every Cancel/recovery/disabled-state scenario.
- v0.5.0 keeps automatic Trim and adds Custom Trim with a full-recording waveform, draggable head/tail handles, bounded audition, Save, and Cancel. Hands-on dragging/listening/export comparison remains unverified.
- No background work, pending subagent patch, or automatic task needs collection. The user is wrapping up for the day.

The checkout is `/Users/jimmytheghost/Dropbox/_Personal Projects/bug`. The sibling `agent-dashboard` (Worklog) is a design reference only and must not be modified.

## Current product behavior

Bug is a lightweight native macOS 15+ menu bar recorder: system audio, optional microphone, live waveform, local source CAF library, playback, rename, and WAV/MP3 export. Nothing records on launch.

**Trim** immediately saves reversible metadata bounds. Default padding is 0.5 seconds; Settings offers 0/0.25/0.5/1/2 seconds. Undo survives relaunch. Playback and exports honor the same bounds. Original audio is retained, so Trim does not reclaim storage.

**Custom Trim** is available from the slider button on each recording and from its **…** menu. While preparing, the recorder card shows progress; it then replaces the live System Audio card with the complete recording waveform. Mint left/right handles select the retained region. Click/drag seeks, Play/Pause and ±5-second controls audition only the proposed range, Save writes the shared trim metadata, and Cancel preserves the previous edit. Opening an edited recording starts from its saved bounds; saving the full waveform clears the trim. The source CAF files remain unchanged, and playback/WAV/MP3 exports use the saved result.

**Silence reminder** covers initial and later silence: Off/15/30/60 seconds, default 30. Either included source counts. Keep Recording resets the interval, Stop saves, ignoring continues, and resumed audio dismisses the independent reminder panel. This is not a storage cap.

**Library** shows saved recordings and per-row sizes. The header total includes all regular files in the root, including unfinished sessions and hidden metadata. Refresh occurs on panel appearance, application activation, and every five seconds while the view task runs. A zero-recording library may show a few KB from Finder metadata. Row Trash moves the complete UUID source folder to macOS Trash after confirmation.

**Delete All** confirms the UUID session-folder count, including saved, empty, and unfinished sessions. It excludes unrelated files/symlinks and uses only the confirmed snapshot. An empty-only library can still be cleared. It is disabled during capture/Trim/export and when no session folders exist. Preview stops before deletion. Partial failures are reported and the list/totals refresh. Exports outside source folders remain untouched. Empty macOS Trash separately to reclaim disk space.

Bulk confirmation uses a standalone NSAlert owned by the store, independent of MenuBarExtra. Cancel is the default keyboard action; reentrant requests are ignored. Do not restore the old popover-attached SwiftUI bulk alert: the user reported that it disappeared and returned without deleting.

## Build identity and safe updates

The user clarified that permission failed **after enabling it**. Logs confirmed the saved v0.3.0 identity was still used for running v0.4.4. Our old workflow (launch each versioned staging build, ask the user to reapprove) left stale grants behind.

Current installation is `~/Applications/Bug.app` (v0.4.4, unchanged binary). Bug was gracefully quit, its ScreenCapture grant reset, and the app installed/reopened there. Archived repo bundles were unregistered from Launch Services but retained. Runtime recovery awaits the user's reapproval/result; do not infer success from installation alone.

**Every delivered update must use `python3 scripts/install-app.py <staged Bug.app>`.** It requires Bug to be quit, stages/verifies the bundle, resets only Bug ScreenCapture when the designated requirement changes, backs up the old app, and installs at the canonical path. Reopen that copy and let the user approve it. Never launch directly from staged version folders. Read [PERMISSIONS.md](PERMISSIONS.md) for diagnostics and explicit same-build repair.

The user accepts normal reapproval on updates. A signing certificate is optional, not a prerequisite for this repair. No certificate/trust changes were made. Never reset unrelated grants, alter the privacy database, or terminate an active capture.

## Next session

1. After the user stops any capture and quits the running app, install `dist/updates/v0.5.0/Bug.app` with `python3 scripts/install-app.py dist/updates/v0.5.0/Bug.app`; do not launch the staged copy.
2. Use [ACCEPTANCE.md](ACCEPTANCE.md) for hands-on Custom Trim dragging, bounded audition, persistence, and WAV/MP3 boundary comparison. Remaining checks also include real capture/listening, reminder behavior, permission persistence, footer resizing, and broader cleanup recovery/Cancel scenarios.
3. Prioritize known gaps only with the user. Low-space warnings, automatic retention, and crash recovery are candidates, not implemented features.
4. Commit and push **every completed pass**, as explicitly requested. Verify a clean checkpoint before new changes. Update affected canon and validation; preserve private visibility and unrelated work.

## Resume commands

Run from the repository root on macOS:

```sh
git status --short --branch
git remote -v
swift build
# Required on a fresh clone before the MP3 test; no global installation.
./scripts/prepare-encoder.sh
./scripts/test.sh
./scripts/package-app.sh "$PWD/.build/handoff-package"
codesign --verify --deep --strict .build/handoff-package/Bug.app
```

`scripts/test.sh` must print a test count. Plain `swift test` previously built tests but silently executed none because the generated runner lacked the CLT Testing framework search path. MP3 tests require `Resources/Encoder/libmp3lame.dylib` and fail explicitly when it is missing. The `.build/` directory, `dist/`, encoder dylib, and encoder source archive are ignored by Git. The upstream license and app icon are committed.

Packaging builds the host architecture. The encoder script supports `ARCHS="arm64 x86_64"`, but that alone does not create a universal app executable. Rebuild the encoder if moving a cached checkout between architectures. Packaging only checks whether the dylib exists; rerun preparation if companion source/license artifacts are missing. Network access is used only to acquire the pinned build dependency, not at app runtime.

### Offscreen layout preview

The render helper now injects an isolated temporary library and preference suite; it does not read personal recordings or record audio. Use `--trim-fixture`, `--trimmed-fixture`, `--settings`, `--deleted-fixture`, or `--silence-reminder` for synthetic layout states. Fixture metadata is only for layout and has no playable source files.

On the original Apple Silicon host:

```sh
mkdir -p .build/qa
swiftc -parse-as-library -target arm64-apple-macosx15.0 \
  Sources/Bug/AudioExporter.swift Sources/Bug/AudioTrimmer.swift Sources/Bug/ExportMP3Encoder.swift \
  Sources/Bug/CaptureEngine.swift Sources/Bug/CapturePCMWriter.swift \
  Sources/Bug/RecordingLibrary.swift Sources/Bug/RecorderStore.swift \
  Sources/Bug/SilenceMonitor.swift Sources/Bug/SilenceReminderPresenter.swift \
  Sources/Bug/CustomTrimEditor.swift Sources/Bug/BugMenuView.swift scripts/render-preview.swift \
  -o .build/qa/render-preview
.build/qa/render-preview .build/qa/bug-panel.png --trim-fixture
# Use --custom-trim for the isolated inline editor fixture.
```

AppKit hosting is intentional: a pure SwiftUI `ImageRenderer` rendered native switches as unsupported placeholders. This preview checks layout only, not clicks or menu bar behavior.

## Known gaps and operational caveats

- **Crash recovery is partial.** Capture can salvage readable tracks during handled interruptions, and the store can add the resulting recording to the library. A crash, failed start, or metadata write failure can leave a directory without `recording.json`; startup ignores these directories. There is no journal, automatic reimport, or recovery UI. They remain available for manual recovery until the user confirms Delete All, which intentionally includes unfinished UUID folders.
- **One corrupt metadata file can fail the whole library load.** The loader rejects bad JSON, mismatched IDs, and non-basename source paths. It does not quarantine a bad entry or verify all source files exist when listing. Missing audio is reported when playback/export tries to open it.
- **Long recordings use disk space.** Float32 stereo system audio is about 1.4 GB/hour plus native microphone audio. Silence is written in bounded chunks, not sparse files. There is no quota, free-space preflight, automatic retention, or rotation.
- **Playback prepares the selected mixed WAV.** It can be slow and needs extra temporary disk space; it shares WAV's roughly 4.14-hour limit. MP3 export can still work above that WAV limit. A force quit may leave a temporary preview or export staging file.
- **Custom Trim also prepares an untrimmed mixed WAV for audition.** Its waveform analysis remains fixed at 720 peaks, but editor preparation needs temporary disk space and shares the same roughly 4.14-hour WAV limit. Save/Cancel removes the preview during normal operation.
- **Capture requires an available display filter and permissions.** No video is saved, but ScreenCaptureKit receives and discards screen callbacks. Protected sources may be unavailable. Multichannel microphones beyond mono/stereo are rejected during ingestion; device format changes interrupt capture.
- **Export progress is indeterminate.** The UI has a spinner and a cancellable save dialog, but no explicit cancel/progress control once encoding begins. The exporter supports task cancellation internally.
- **Local signing only.** No Developer ID, notarization, sandbox distribution configuration, auto-update, or verified Intel/universal release. Launch-at-login behavior still needs packaged-app testing.

Do not describe these caveats as fixed until code and evidence support that claim.
