# Hands-on acceptance

**Status: all live checks below are pending as of 2026-09-07.** Add date, macOS/device details, result, and any issue reference when completing a check. User approval of appearance is not a substitute for these checks.

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

Capture is never started automatically by app launch or by tests.
