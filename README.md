# Bug

A small native macOS menu bar app for catching audio. Designed as a companion to Worklog (`agent-dashboard` in the sibling local checkout): compact panel, mint accents, system typography, and no Dock icon.

## Project status and handoff

Version **0.1.0**, personal-use macOS build. Source is in the private [jimmytheghost/bug repository](https://github.com/jimmytheghost/bug), on `main`. The initial implementation is committed as `f468070`. Build outputs and generated encoder binaries are not committed; build locally using the commands below.

**Start here, future agents:** read [AGENTS.md](AGENTS.md), then [the handoff](docs/HANDOFF.md) and [canonical architecture](docs/ARCHITECTURE.md). The [plan](docs/PLAN.md) records scope and remaining work; [validation](docs/VALIDATION.md) records evidence; [acceptance](docs/ACCEPTANCE.md) lists unverified hands-on checks.

The initial implementation passed 21 synthetic tests and release/signature checks. Live recording, permission flows, and real-device behavior have not been verified. User feedback was positive, but did not explicitly confirm those tests.

## What it does

- Records capturable system audio, with an optional microphone.
- Shows a live waveform and elapsed time while recording, including when the panel is closed.
- Saves stopped recordings to a local library with playback, rename, and Move to Trash.
- Exports 48 kHz / 24-bit stereo WAV or 320 kbps stereo MP3.
- Offers launch at login. No accounts, uploads, or background web service.

## Build and run

Requires macOS 15 or newer and Xcode Command Line Tools with Swift Testing and a macOS 15+ SDK. Development was verified with Swift 6.3.3; the package uses Swift 5 language mode and a 5.9 manifest.

The first package build downloads the pinned LAME 3.100 source, verifies its SHA-256, and builds an MP3 encoder locally. Later builds reuse it. Nothing is installed globally.

```sh
swift build
./scripts/prepare-encoder.sh
./scripts/test.sh
./scripts/package-app.sh
open dist/Bug.app
```

Use the packaged app for recording: its bundle supplies macOS microphone usage text and the MP3 encoder. `swift run Bug` is only suitable for interface development; permission identity and MP3 encoding require the bundle. The app is ad-hoc signed for local use. Developer ID signing, notarization, and updates are future distribution work.

## Record

Click the ladybug in the menu bar, optionally enable **Include microphone**, then click **Record**. On first use, allow Bug in macOS **Privacy & Security → Screen & System Audio Recording**, and allow the microphone if requested. macOS may require restarting Bug after permission changes. Click **Stop recording** to finalize the recording and add it to the library.

Use the recording's **…** menu to export WAV or MP3, rename it, or move its source files to Trash. The play button previews the combined audio; it prepares a temporary WAV first, so long recordings may take time. Original recordings stay in the library after export.

Recordings live in `~/Library/Application Support/Bug/Recordings/`. The **Library folder** button opens this directory. Each session has lossless source CAF tracks and JSON metadata. WAV/MP3 are created only on export. Audio is written incrementally; uncompressed stereo sources use roughly 1.4 GB per hour, plus microphone audio. The library does not automatically delete recordings. Interrupted sessions without finalized JSON metadata remain on disk but are not automatically imported into the library; see [known gaps](docs/HANDOFF.md#known-gaps-and-operational-caveats).

## Capture and format details

ScreenCaptureKit uses a display filter to obtain system audio. Bug does not save screen video. Audio capture is subject to macOS permissions and source restrictions; protected content may not be available. Headphones help prevent microphone capture from duplicating speaker playback. Changes to audio devices or system sleep may interrupt a recording; Bug reports failures and preserves source files where possible.

Tracks use a shared host-clock timeline with silence padding. Export converts them to 48 kHz stereo and applies constant attenuation only if needed to prevent summed sample clipping. It does not boost quiet audio. Export uses bounded buffers and atomically replaces the selected destination only after encoding succeeds. WAV has the standard 4 GiB file-size limit (about 4.14 hours at this export format); use MP3 for longer recordings. Library playback also prepares a WAV and shares that limit. MP3 is lossy and adds standard encoder delay/padding.

## Repository

- `Sources/Bug/`: SwiftUI interface, app state, library, audio capture, and export.
- `Tests/BugTests/`: synthetic audio and library tests; no recording of live user audio.
- `Resources/`: app metadata/icon and locally built encoder artifacts.
- `scripts/package-app.sh`: release bundle with encoder, license, and corresponding source.
- `scripts/prepare-encoder.sh`: reproducible local encoder build.
- `scripts/test.sh`: test runner, including the standalone CLT framework workaround.
- `scripts/render-preview.swift`: developer-only offscreen layout renderer; see [handoff commands](docs/HANDOFF.md#offscreen-layout-preview).
- `AGENTS.md`: agent instructions and documentation reading order.
- `docs/HANDOFF.md`: current state, known gaps, and next actions.
- `docs/ARCHITECTURE.md`: canonical module contracts, data format, and design decisions.
- `docs/PLAN.md`: confirmed scope, completed implementation, and open milestones.
- `docs/VALIDATION.md`: dated test/build evidence and verification limits.
- `docs/ACCEPTANCE.md`: hands-on recording checklist.

To regenerate the icon:

```sh
mkdir -p .build/icon
swift scripts/generate-icon.swift .build/icon
iconutil -c icns .build/icon/Bug.iconset -o Resources/Bug.icns
```

See `THIRD_PARTY_NOTICES.md` for encoder attribution.

`scripts/test.sh` exposes the bundled Swift Testing framework to SwiftPM's generated test runner when using standalone Command Line Tools. A plain `swift test` can compile tests but discover none in that environment; require an explicit test count in the output.
