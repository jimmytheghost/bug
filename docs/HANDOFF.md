# Agent handoff

Last updated: **2026-10-20, public source preparation**. Current source version: **0.6.1**, build **13**. Read this first, then [ARCHITECTURE.md](ARCHITECTURE.md) for implementation contracts.

## Current state

- v0.6.1 replaces the popover-bound rename alert with a store-backed in-panel editor. Save/Cancel clear the pending editor without closing the Bug panel, and Save reloads the library. Use `git log -1` for the latest committed revision.
- Private repository: [jimmytheghost/bug](https://github.com/jimmytheghost/bug). Branch `main` tracks `origin/main`. GitHub privacy was rechecked for this handoff.
- Latest validation artifact is `.build/public-prep-package/Bug.app` (v0.6.1/build 13, with bundled MIT license). It was not installed or launched. Deliver updates only through `scripts/install-app.py`; the canonical installed copy remains untouched.
- Latest executed validation, **2026-10-20**: debug build, **60 tests in 8 suites**, isolated release packaging/signature and license-inventory checks passed. Earlier rename/Custom Trim renders remain historical evidence. No live audio or personal recording was used.
- The user confirmed v0.4.3 Delete All works. Their screenshot showed 13 session folders moved and zero saved recordings remaining. This confirms the successful deletion flow, not every Cancel/recovery/disabled-state scenario.
- The user confirmed v0.5.1 row deletion succeeds and no longer recurs, but the standalone alert dismisses the menu-bar panel. v0.5.2 replaces that alert with a store-backed overlay inside the existing panel. Cancel and Move to Trash clear the pending request before returning to the still-open recording list. Hands-on confirmation remains pending.
- README now includes recorder and Custom Trim images rendered from the current views at 360 points, using isolated fixtures. See [image provenance](images/README.md); these do not verify live recording or interactive behavior.
- Public-facing README now presents general system-audio recording for samples, internet radio, music, browser audio, livestreams, and calls, with independent backup recording as an additional use, with source-build instructions, MIT licensing, and existing limits. See [RELEASE.md](RELEASE.md) for publication readiness. Repository visibility remains private; no binary release was published.

The sibling `agent-dashboard` (Worklog) is a design reference only and must not be modified.

## Current product behavior

Bug is a lightweight native macOS 15+ menu bar recorder: system audio, optional microphone, live waveform, local source CAF library, playback, rename, and WAV/MP3 export. Nothing records on launch. Use it to capture samples, internet radio, music, browser audio, livestreams, calls, and other available computer audio. It can also keep an independent copy if another app’s recorder fails; individual source-app compatibility remains unverified.

**Trim** immediately saves reversible metadata bounds. Default padding is 0.5 seconds; Settings offers 0/0.25/0.5/1/2 seconds. Undo survives relaunch. Playback and exports honor the same bounds. Original audio is retained, so Trim does not reclaim storage.

**Custom Trim** is available from the slider button on each recording and from its **…** menu. While preparing, the recorder card shows progress; it then replaces the live System Audio card with the complete recording waveform. Mint left/right handles select the retained region. Click/drag seeks, Play/Pause and ±5-second controls audition only the proposed range, Save writes the shared trim metadata, and Cancel preserves the previous edit. Opening an edited recording starts from its saved bounds; saving the full waveform clears the trim. The source CAF files remain unchanged, and playback/WAV/MP3 exports use the saved result.

For precision on long recordings, hold either handle still for about 0.25 seconds. A fixed 10× window appears: HEAD pins the active start to the far left and TAIL pins the active stop to the far right. Continue holding while dragging; the waveform moves beneath the fixed boundary. Release returns to the full overview. Immediate movement remains a coarse drag. Head release seeks preview to the new start, and preview/export remain clamped to the selected bounds.

**Silence reminder** covers initial and later silence: Off/15/30/60 seconds, default 30. Either included source counts. Keep Recording resets the interval, Stop saves, ignoring continues, and resumed audio dismisses the independent reminder panel. This is not a storage cap.

**Library** shows saved recordings and per-row sizes. The header total includes all regular files in the root, including unfinished sessions and hidden metadata. Refresh occurs on panel appearance, application activation, and every five seconds while the view task runs. A zero-recording library may show a few KB from Finder metadata. Row Trash moves the complete UUID source folder to macOS Trash after confirmation.

Per-recording Trash uses an in-panel confirmation overlay backed by `pendingRecordingDeletion` in the store. This avoids both failure modes seen in user testing: popover-attached SwiftUI alerts could recur, while a standalone alert necessarily closed the panel. Cancel is the default keyboard action, repeated requests are ignored, and confirmation clears pending state before moving the folder. Delete All remains a standalone AppKit alert because it is an infrequent whole-library action.

**Delete All** confirms the UUID session-folder count, including saved, empty, and unfinished sessions. It excludes unrelated files/symlinks and uses only the confirmed snapshot. An empty-only library can still be cleared. It is disabled during capture/Trim/export and when no session folders exist. Preview stops before deletion. Partial failures are reported and the list/totals refresh. Exports outside source folders remain untouched. Empty macOS Trash separately to reclaim disk space.

## Build identity and safe updates

The user clarified that permission failed **after enabling it**. Logs confirmed the saved v0.3.0 identity was still used for running v0.4.4. Our old workflow (launch each versioned staging build, ask the user to reapprove) left stale grants behind.

The canonical installation is `~/Applications/Bug.app` v0.6.1 build 13. It was installed through the canonical installer and reopened from that path. The installer reset Bug's ScreenCapture approval because the ad-hoc identity changed; the user must approve capture again and restart if macOS requests it. Installation alone does not prove runtime authorization.

**Every delivered update must use `python3 scripts/install-app.py <staged Bug.app>`.** It requires Bug to be quit, stages/verifies the bundle, resets only Bug ScreenCapture when the designated requirement changes, backs up the old app, and installs at the canonical path. Reopen that copy and let the user approve it. Never launch directly from staged version folders. Read [PERMISSIONS.md](PERMISSIONS.md) for diagnostics and explicit same-build repair.

The user accepts normal reapproval on updates. A signing certificate is optional, not a prerequisite for this repair. No certificate/trust changes were made. Never reset unrelated grants, alter the privacy database, or terminate an active capture.

## Next session

Public sharing preparation is documented in [RELEASE.md](RELEASE.md). Obtain explicit publication authorization before changing visibility or publishing a release.

1. Ask the user to verify that Rename Save/Cancel closes only the editor, leaves the panel open, and immediately updates the library.
2. Use [ACCEPTANCE.md](ACCEPTANCE.md) for remaining Custom Trim persistence and WAV/MP3 boundary comparison. Remaining checks also include real capture/listening, reminder behavior, permission persistence, footer resizing, and broader cleanup recovery scenarios.
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

The render helper now injects an isolated temporary library and preference suite; it does not read personal recordings or record audio. Use `--trim-fixture`, `--trimmed-fixture`, `--rename-confirmation`, `--delete-confirmation`, `--settings`, `--deleted-fixture`, or `--silence-reminder` for synthetic layout states. Fixture metadata is only for layout and has no playable source files.

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
- **Custom Trim also prepares an untrimmed mixed WAV for audition.** Its waveform analysis remains bounded at 7,200 detail peaks (at most 720 in the overview), but editor preparation needs temporary disk space and shares the same roughly 4.14-hour WAV limit. Save/Cancel removes the preview during normal operation.
- **Capture requires an available display filter and permissions.** No video is saved, but ScreenCaptureKit receives and discards screen callbacks. Protected sources may be unavailable. Multichannel microphones beyond mono/stereo are rejected during ingestion; device format changes interrupt capture.
- **Export progress is indeterminate.** The UI has a spinner and a cancellable save dialog, but no explicit cancel/progress control once encoding begins. The exporter supports task cancellation internally.
- **Local signing only.** No Developer ID, notarization, sandbox distribution configuration, auto-update, or verified Intel/universal release. Launch-at-login behavior still needs packaged-app testing.

Do not describe these caveats as fixed until code and evidence support that claim.
