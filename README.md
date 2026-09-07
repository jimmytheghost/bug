# Bug

A small native macOS menu bar app for catching audio. Designed as a companion to Worklog (`agent-dashboard` in the sibling local checkout): compact panel, mint accents, system typography, and no Dock icon.

## Project status and handoff

Version **0.3.0**, personal-use macOS build. Source is in the private [jimmytheghost/bug repository](https://github.com/jimmytheghost/bug), on `main`. The initial implementation is committed as `f468070`. Build outputs and generated encoder binaries are not committed; build locally using the commands below.

**Start here, future agents:** read [AGENTS.md](AGENTS.md), then [the handoff](docs/HANDOFF.md) and [canonical architecture](docs/ARCHITECTURE.md). The [plan](docs/PLAN.md) records scope and remaining work; [validation](docs/VALIDATION.md) records evidence; [acceptance](docs/ACCEPTANCE.md) lists unverified hands-on checks.

The current implementation passed 46 synthetic tests, including Trim and silence reminders, and release/signature checks. The user reported a forgotten recording that produced over 1 GB of silence. Live signal quality, permission flows, and the new reminder's real-device behavior still need acceptance testing.

## What it does

- Records capturable system audio, with an optional microphone.
- Shows a live waveform and elapsed time while recording, including when the panel is closed.
- Saves stopped recordings to a local library with playback, rename, and Move to Trash.
- Exports 48 kHz / 24-bit stereo WAV or 320 kbps stereo MP3.
- Offers optional **Trim** with immediate application, persistent Undo, and 0.5-second head/tail padding by default.
- Offers a configurable silence reminder before the source starts and during later silent stretches.
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

## Silence reminder

In the gear settings, **Silence reminder** offers **Off**, **15 seconds**, **30 seconds** (default), and **1 minute**. The preference is saved across launches. Monitoring starts once capture is running, after any permission prompts, and checks for silence both at the beginning and later in the recording.

When the interval passes without detected audio, Bug opens a separate **Still waiting for audio?** popup, even if the menu bar panel is closed:

- **Keep Recording** closes the reminder and restarts the full silence interval.
- **Stop Recording** uses the normal Stop/save flow to preserve what was captured.
- Ignoring the reminder continues recording; duplicate reminders do not pile up.

Either system audio or an enabled microphone counts as activity. If audio resumes, the stale reminder closes automatically and Bug watches for the next silent stretch. Changing the delay while recording starts a fresh interval; selecting Off dismisses a pending reminder. The setting does not mute the source, trim audio, or impose a maximum recording size. Background noise above the detector's -60 dBFS RMS threshold also counts as activity.

## Trim

After stopping, click **Trim** beside the saved recording. It removes leading and trailing silence while keeping up to **0.5 seconds at each end**, and leaves pauses inside the recording intact. The duration updates immediately after analysis, and the button becomes **Undo**. Trim is also in the recording's **…** menu, so older recordings can be processed later.

Playback and subsequent WAV/MP3 exports use the trim. Original CAF files stay unchanged; **Undo** restores the full recording, including after relaunch. Previously exported files do not change. An entirely silent track or one with no removable silence stays unchanged.

In Settings, **Trim padding** offers none, 0.25, 0.5, 1, or 2 seconds at each end. It affects the next Trim operation; Undo first to reapply a different padding to an already trimmed recording. Padding is limited to available audio and never inserts new silence.

Detection uses a conservative fixed -60 dBFS threshold across both channels of each source. Quiet fades below that threshold may be treated as silence; background noise above it may prevent a trim. It detects audio boundaries, not the start/end of a specific song: other audible material before or after a song is retained. Always use Undo if the result is not what you want.

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
