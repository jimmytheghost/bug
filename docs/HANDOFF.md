# Agent handoff

Last updated: **2026-09-07**. Version **0.1.0**. This is the current-state entry point; [ARCHITECTURE.md](ARCHITECTURE.md) is the implementation canon.

## Where we left off

Bug's first implementation is complete and committed as `f468070` (`Build Bug native menu bar audio recorder`). It was pushed to the private [jimmytheghost/bug](https://github.com/jimmytheghost/bug) repository. The default branch is `main`, tracking `origin/main`. Subsequent documentation commits preserve this implementation baseline; use `git log` for the latest revision.

The user confirmed system audio with an optional microphone, a small local library with WAV/MP3 export, and macOS personal use first. They approved the appearance and requested private GitHub hosting and complete handoff documentation. They have not reported results from a real recording session.

The local checkout used for development is `/Users/jimmytheghost/Dropbox/_Personal Projects/bug`. The design reference is the sibling `/Users/jimmytheghost/Dropbox/_Personal Projects/agent-dashboard` (Worklog). That app was inspected, not modified. Bug has no runtime dependency on that checkout.

The local artifact is `dist/Bug.app` (approximately 3.1 MB); bundle ID `com.jimmyweber.bug`. It was launched during development. **Do not assume it is still running or matches the latest build:** inspect current state, and never terminate a potentially active recording to refresh a build. No installer, GitHub release, CI workflow, or remote build service is configured.

## Verified baseline

- Apple Silicon, macOS 26.6.2, Swift 6.3.3 Command Line Tools.
- Debug build, release bundle, and ad-hoc signature verification passed.
- 21 executed Swift Testing tests in 3 suites passed, including real MP3 encode/decode using synthetic audio.
- Offscreen AppKit/SwiftUI layout inspected; desktop automation timed out.
- No live user audio was captured. Real capture, permissions, FaceTime, device changes, sleep, and launch at login remain unverified.

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

The render helper uses the real `RecorderStore`, so it reads the local library and preferences and may create the library directory. It does not record audio. Use an empty development account/library for shareable previews; never publish a render containing personal recording names.

On the original Apple Silicon host:

```sh
mkdir -p .build/qa
swiftc -parse-as-library -target arm64-apple-macosx15.0 \
  Sources/Bug/AudioExporter.swift Sources/Bug/ExportMP3Encoder.swift \
  Sources/Bug/CaptureEngine.swift Sources/Bug/CapturePCMWriter.swift \
  Sources/Bug/RecordingLibrary.swift Sources/Bug/RecorderStore.swift \
  Sources/Bug/BugMenuView.swift scripts/render-preview.swift \
  -o .build/qa/render-preview
.build/qa/render-preview .build/qa/bug-panel.png
```

AppKit hosting is intentional: a pure SwiftUI `ImageRenderer` rendered native switches as unsupported placeholders. This preview checks layout only, not clicks or menu bar behavior.

## Next actions

1. Run the live acceptance checklist with a deliberate test source and the user's permissions. Record the observed outcomes; do not infer them from the synthetic suite.
2. Investigate any real capture or export failures before adding features. Preserve source files when troubleshooting.
3. Prioritize the known gaps below with the user. They are observations and follow-up candidates, not approved scope expansion.
4. Update the affected canon and validation record, commit, and push completed changes. Preserve the repository's private visibility.

## Known gaps and operational caveats

- **Crash recovery is partial.** Capture can salvage readable tracks during handled interruptions, and the store can add the resulting recording to the library. A crash, failed start, or metadata write failure can leave a directory without `recording.json`; startup ignores these directories. There is no journal, automatic reimport, or recovery UI. Preserve them for manual recovery.
- **One corrupt metadata file can fail the whole library load.** The loader rejects bad JSON, mismatched IDs, and non-basename source paths. It does not quarantine a bad entry or verify all source files exist when listing. Missing audio is reported when playback/export tries to open it.
- **Long recordings use disk space.** Float32 stereo system audio is about 1.4 GB/hour plus native microphone audio. Silence is written in bounded chunks, not sparse files. There is no quota, free-space preflight, automatic retention, or rotation.
- **Playback prepares the full mixed WAV.** It can be slow and needs extra temporary disk space; it shares WAV's roughly 4.14-hour limit. MP3 export can still work above that WAV limit. A force quit may leave a temporary preview or export staging file.
- **Capture requires an available display filter and permissions.** No video is saved, but ScreenCaptureKit receives and discards screen callbacks. Protected sources may be unavailable. Multichannel microphones beyond mono/stereo are rejected during ingestion; device format changes interrupt capture.
- **Export progress is indeterminate.** The UI has a spinner and a cancellable save dialog, but no explicit cancel/progress control once encoding begins. The exporter supports task cancellation internally.
- **Local signing only.** No Developer ID, notarization, sandbox distribution configuration, auto-update, or verified Intel/universal release. Launch-at-login behavior still needs packaged-app testing.

Do not describe these caveats as fixed until code and evidence support that claim.
