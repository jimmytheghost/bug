# Hands-on acceptance

**Status: partially verified as of 2026-09-07.** The user confirmed the v0.4.3 Delete All success path and supplied a screenshot showing 13 sessions moved with zero recordings remaining. Broader checks below remain pending. Add date, macOS/device details, and evidence when completing a check; approval of appearance does not establish recording quality.

Automated tests use synthetic samples. These checks require the user's macOS permissions and actual audio sources; do not mark them passed based on compilation alone.

- [ ] Open `~/Applications/Bug.app`. Confirm one ladybug menu bar item, no Dock icon, and a compact Worklog-style panel.
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

- [ ] Stop any active capture, quit the old Bug, and open `~/Applications/Bug.app`. Reapprove capture if needed.
- [ ] Verify visible Trash buttons on short/long titles and trimmed/microphone recordings; cancel once, then confirm deletion on a disposable recording.
- [ ] Confirm the row and totals update, exported copies outside its folder stay intact, and the source folder can be restored from macOS Trash.
- [ ] Move a disposable UUID recording folder out in Finder and restore it. Verify refresh with the panel open (within about five seconds), after reopening, and when returning from Finder.
- [ ] Check row sizes and the full folder total, including an unfinished session. Verify Trim changes duration without reducing source storage.
- [ ] During playback, remove the entry through Finder and verify refresh stops playback. Verify Trash is disabled for the entry undergoing Trim/export.

## Delete All · current behavior

- [x] **2026-09-07, user's development Mac, v0.4.3:** confirm deletion succeeds through the standalone warning. User said “Works great” and supplied a screenshot showing 13 sessions moved and zero recordings remaining.
- [ ] Cancel and reopen Settings: verify no deletion and no recurring warning.
- [ ] Confirm with disposable saved and unfinished sessions; verify recoverable source folders in Trash, exported copies outside source folders unchanged, and totals updated.
- [ ] Verify the session count includes empty/unfinished UUID folders and excludes unrelated files. Test an empty-only library and sessions added after confirmation.
- [ ] Check disabled state with no session folders, during recording, Trim, and export. Verify bulk deletion stops preview playback.
- [ ] Verify partial-failure messaging using disposable files and an injected/unwritable fixture, without risking personal recordings.

## Footer · v0.4.4

- [ ] Confirm footer padding after Delete All with the success notice visible, after dismissing the notice, with saved recordings, and in Settings. Verify the panel resizes without clipping its bottom controls.

Earlier v0.4.1 preservation of unfinished sessions and its popover-attached confirmation were superseded by v0.4.2/v0.4.3. Test the current behavior above.


## Installation and permission repair

- [ ] After the scoped reset and canonical installation, approve Bug again, restart if requested, and confirm actual capture starts.
- [ ] For the next changed build, install with `scripts/install-app.py`. Verify the reset notice, fresh permission approval, and successful capture afterward.
- [ ] Verify unchanged-identity installation preserves the grant and running-app installation is refused.
