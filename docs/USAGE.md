# Using Bug

## Record

Click the ladybug in the menu bar, optionally enable **Include microphone**, then click **Record**. On first use, allow Bug in macOS **Privacy & Security → Screen & System Audio Recording**, and allow the microphone if requested. macOS may require restarting Bug after permission changes. Click **Stop recording** to finalize the recording and add it to the library.

Use the visible **trash can** beside a recording to move its source folder to macOS Trash after confirmation. You can also use the **…** menu to export WAV or MP3, rename it, or move it to Trash. The play button previews the combined audio; it prepares a temporary WAV first, so long recordings may take time. Original recordings stay in the library after export.

Recordings live in `~/Library/Application Support/Bug/Recordings/`. The **Library folder** button opens this directory. Each session has lossless source CAF tracks and JSON metadata. WAV/MP3 are created only on export. Audio is written incrementally; uncompressed stereo sources use roughly 1.4 GB per hour, plus microphone audio. The library does not automatically delete recordings. Interrupted sessions without finalized JSON metadata remain on disk but are not automatically imported into the library; see [known gaps](HANDOFF.md#known-gaps-and-operational-caveats).

## Library storage

Each row shows duration and file size; hover over the title for the recording date. The library heading shows the recording count and total file sizes in the Library folder. This includes metadata and unfinished sessions, so the total may exceed the sizes of the playable entries. Sizes are logical file bytes, not an estimate of reclaimable disk space.

The list refreshes when the panel appears, when Bug becomes active, and every five seconds while the panel is present. Recordings moved out through Finder disappear on refresh; restoring their original UUID folders brings them back. Only Bug recordings with valid metadata appear as rows, not arbitrary audio dropped into the folder. A corrupt metadata file still causes a load error.

Trash is recoverable, and exported copies outside the source folder stay untouched. **Empty macOS Trash to reclaim disk space.** There is no automatic deletion. Trim keeps the original sources for Undo and therefore does not reduce library storage. **Delete All** in Settings opens an independent macOS warning dialog for confirmation before moving the displayed snapshot of session folders, including empty and unfinished sessions, to Trash. It is disabled during recording, Trim, or export and when there are no session folders. Failures are reported and remaining entries stay visible. Low-disk warnings remain future work.

The canonical installed app is `~/Applications/Bug.app`. All updates must use `scripts/install-app.py`, which clears Bug’s stale screen-capture grant when the build identity changes. Then approve the installed copy and restart if macOS asks. Staging folders are archives, not launch targets. See [installation and recovery instructions](PERMISSIONS.md).

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

For manual control, click the slider button on a recording or choose **Custom Trim…** from its **…** menu. Bug replaces the live recorder card with the entire recording waveform. Drag the mint left and right handles to choose what to keep. For fine control, press and hold either handle for about 0.25 seconds: Bug zooms to 10× while pinning the head to the far left or the tail to the far right. Keep holding and drag so the waveform moves beneath that fixed edge, then release to return to the overview. The left edge is the exact playback/export start and the right edge is the exact stop. Click or drag elsewhere to seek, use Play and the five-second skip controls to preview, then choose **Save** or **Cancel**. Opening Custom Trim on an already trimmed recording starts from its saved bounds. Saving replaces those bounds; selecting the full recording clears the trim. Playback and later WAV/MP3 exports use the saved selection, while Undo still restores the complete source.

Detection uses a conservative fixed -60 dBFS threshold across both channels of each source. Quiet fades below that threshold may be treated as silence; background noise above it may prevent a trim. It detects audio boundaries, not the start/end of a specific song: other audible material before or after a song is retained. Always use Undo if the result is not what you want.

## Capture and format details

ScreenCaptureKit uses a display filter to obtain system audio. Bug does not save screen video. Audio capture is subject to macOS permissions and source restrictions; protected content may not be available. Headphones help prevent microphone capture from duplicating speaker playback. Changes to audio devices or system sleep may interrupt a recording; Bug reports failures and preserves source files where possible.

Tracks use a shared host-clock timeline with silence padding. Export converts them to 48 kHz stereo and applies constant attenuation only if needed to prevent summed sample clipping. It does not boost quiet audio. Export uses bounded buffers and atomically replaces the selected destination only after encoding succeeds. WAV has the standard 4 GiB file-size limit (about 4.14 hours at this export format); use MP3 for longer recordings. Library playback also prepares a WAV and shares that limit. MP3 is lossy and adds standard encoder delay/padding.

