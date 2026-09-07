# Hands-on acceptance

**Status: the checklist remains pending as of 2026-09-07. The user reported a forgotten recording producing over 1 GB of silence, but has not supplied the individual results below.** Add date, macOS/device details, result, and any issue reference when completing a check. User approval of appearance is not a substitute for these checks.

Automated tests use synthetic samples. These checks require the user's macOS permissions and actual audio sources; do not mark them passed based on compilation alone.

- [ ] Open `dist/Bug.app`. Confirm one ladybug menu bar item, no Dock icon, and a compact Worklog-style panel.
- [ ] Deny system recording permission once. Confirm a useful error and working permission settings link. Grant permission and reopen Bug if macOS requests it.
- [ ] Play known non-protected audio. Record with microphone off. Confirm waveform and timer, close/reopen the panel, stop, and confirm a new library entry.
- [ ] Play the entry. Export WAV and MP3 and listen to both; compare beginning, middle, end, stereo channels, and duration.
- [ ] Record with microphone enabled and headphones. Speak while system audio plays; confirm both sources are present and aligned.
- [ ] Record microphone speech while the system is silent; then system audio while microphone is silent. Confirm silence does not remove or shift the other source.
- [ ] Rename a recording and relaunch Bug. Confirm metadata and playback persist.
- [ ] Cancel export. Confirm no loss of the library entry or existing destination. Try an unwritable destination and confirm a visible error.
- [ ] Move a test recording to Trash. Confirm exported copies remain and source files are recoverable from Trash.
- [ ] Exercise long recordings, device changes, sleep/wake, permission revocation, and disk-full behavior. Confirm failures are visible and partial source files remain available.
- [ ] Confirm Quit is unavailable during capture and export; stop before quitting.
- [ ] Enable/disable Start on computer startup in the packaged app and verify macOS Login Items state.

## Trim · v0.2.0

- [ ] After Stop, confirm the new recording has a **Trim** button. Click it and check that it becomes **Undo**, with a shorter displayed duration and no preview approval dialog.
- [ ] Record 8 seconds of silence, a known clip, then 10 seconds of silence. Trim with the default padding and confirm about 0.5 seconds remains at each end. Listen to the quiet beginning/fade and any internal pauses.
- [ ] Preview and export both formats after Trim; confirm the boundaries match. Undo and confirm full-length playback/export returns, while earlier exported files stay unchanged.
- [ ] Quit/reopen after Trim; confirm the edit and Undo persist. Rename and confirm the trim stays applied.
- [ ] Change Trim padding, Undo, and Trim again. Check that existing edits do not change just from changing the setting.
- [ ] Check all-silent, short, continuously audible, very quiet, and noisy recordings. No-op results should be clear; use Undo if detection cuts too much.
- [ ] Include microphone speech before/after system audio and confirm it remains in the trimmed result. Test long-file processing and a metadata write failure without risking real recordings.

## Silence reminder · v0.3.0

- [ ] With default settings, start capture and leave the source silent. Close the menu bar panel, switch to another app, and confirm a standalone reminder appears after about 30 seconds.
- [ ] Check 15 seconds and 1 minute. Confirm Off never prompts, including after relaunch.
- [ ] Click Keep Recording; confirm capture continues uninterrupted and a new full silent interval is needed for another reminder.
- [ ] Ignore the reminder for several intervals. Confirm recording continues and no duplicate windows appear.
- [ ] Click Stop Recording in the popup. Confirm the recording is finalized and available in the library with the same behavior as ordinary Stop.
- [ ] Play system audio, then become silent; confirm later silence prompts. Include the microphone, speak while the system is silent, and confirm that also resets the clock.
- [ ] Start audio while the reminder is visible. Confirm it dismisses automatically and reappears only after a new silent interval.
- [ ] Change the delay while recording and while a reminder is visible; confirm a fresh interval. Select Off and confirm immediate dismissal.
- [ ] Test manual Stop, a new session, permission failure, and capture interruption; old popup actions must not affect a new recording.
- [ ] Check reminder visibility and button focus on another Space and over a full-screen app. Confirm recording remains responsive while the popup is open.

Capture is never started automatically by app launch or by tests.

## Library storage · v0.4.0

- [ ] Stop any active capture, quit the old Bug, and open `dist/updates/v0.4.0/Bug.app`. Reapprove capture if needed.
- [ ] Verify visible Trash buttons on short/long titles and trimmed/microphone recordings; cancel once, then confirm deletion on a disposable recording.
- [ ] Confirm the row and totals update, exported copies outside its folder stay intact, and the source folder can be restored from macOS Trash.
- [ ] Move a disposable UUID recording folder out in Finder and restore it. Verify refresh with the panel open (within about five seconds), after reopening, and when returning from Finder.
- [ ] Check row sizes and the full folder total, including an unfinished session. Verify Trim changes duration without reducing source storage.
- [ ] During playback, remove the entry through Finder and verify refresh stops playback. Verify Trash is disabled for the entry undergoing Trim/export.

## Delete All · v0.4.1

- [ ] With disposable recordings, click Settings → Delete All. Verify the count and warning, then Cancel and confirm nothing changes.
- [ ] Confirm Delete All. Verify list/totals update, sources are recoverable from Trash, and exports outside the source folders and unfinished sessions remain.
- [ ] Check disabled state for empty library, recording, Trim, and export. Verify bulk deletion stops preview playback.

## Session cleanup · v0.4.2

- [ ] Verify Delete All counts both finalized and empty/unfinished UUID session folders; unrelated files are excluded.
- [ ] Confirm cleanup on disposable saved and unfinished sessions, including an empty-only library. Verify Trash recovery and preservation of sessions added after confirmation. This supersedes v0.4.1's unfinished-session preservation behavior.

## Independent confirmation · v0.4.3

- [ ] Open the latest staged build after quitting the old copy. Click Settings → Delete All; verify a standalone warning remains usable when the menu panel closes.
- [ ] Cancel and reopen Settings: no deletion and no recurring warning. Repeat and confirm using disposable sessions: verify Trash movement and updated counts, then reopen and confirm the old warning does not return.
