# Validation · 2026-09-08

Current baseline: v0.6.0, 59 tests in 8 suites. Sections below are dated release evidence; older “pending” statements describe the state at that pass. Current acceptance status is maintained in [ACCEPTANCE.md](ACCEPTANCE.md).

## Precision Custom Trim · v0.6.0

- `swift build` passed and `scripts/test.sh` executed **59 tests in 8 suites**, all passing. The new test verifies fixed 10× drag scaling, head/tail detail-window sampling around pinned edges, and bounded overview reduction.
- The waveform analyzer remains streaming and increases only its fixed peak summary from 720 to 7,200 values. The full recording PCM is never retained. Immediate movement preserves coarse dragging; a stationary 250 ms hold enables fine mode; mouse-up exits it; head release seeks to the new start.
- Isolated synthetic full-panel renders of forced **10× HEAD** and **10× TAIL** states were visually checked at 360 points. Both pin the mint boundary to the specified edge, display the magnified waveform and state badge, retain controls and time labels, and avoid clipping. Timed mouse behavior and exact listening bounds remain hands-on checks.
- Release packaging passed at `dist/updates/v0.6.0/Bug.app`; Info.plist reports version 0.6.0/build 12 and deep/strict signature verification passed. Bug quit through its protected termination path, the installer performed the scoped ScreenCapture reset required by the changed ad-hoc identity, and the verified app reopened from `~/Applications/Bug.app`. A boundary gesture also explicitly pauses any active Custom Trim preview before editing begins.

## In-panel row deletion confirmation · v0.5.2

- The user confirmed v0.5.1 deletion works but reported that its standalone alert dismisses the Bug panel after each action, requiring another menu-bar click before deleting the next track.
- Replaced the standalone row alert with a confirmation overlay inside the existing 360-point panel. Store-owned pending state allows only one request, Cancel clears it, and Move to Trash clears it before deletion; neither action changes menu presentation.
- `swift build` passed and `scripts/test.sh` executed **58 tests in 8 suites**, all passing. The new store test covers pending presentation, duplicate suppression, Cancel, subsequent confirmation, and injected recoverable Trash.
- The real panel and confirmation overlay were rendered offscreen with a synthetic metadata-only recording. The card, warning copy, dimmed background, Cancel, and destructive action fit without clipping. Rendering does not prove the menu stays open during real clicks; that remains a hands-on check.
- Release packaging passed at `dist/updates/v0.5.2/Bug.app`; Info.plist reports version 0.5.2/build 11 and deep/strict signature verification passed. Bug quit through its protected termination path, the canonical installer performed the scoped ScreenCapture reset required by the changed ad-hoc identity, and the verified app reopened from `~/Applications/Bug.app`.

## Independent row deletion confirmation · v0.5.1

- The user supplied a screenshot and reported that v0.5.0's per-recording SwiftUI Trash alert closed with the menu and reappeared on every reopen. This matches the MenuBarExtra lifecycle failure previously seen with Delete All.
- Removed the popover-bound deletion state and routed both row Trash entry points through a standalone store-owned NSAlert. Cancel is the default keyboard action; only the current library entry can be deleted; duplicate confirmation requests are suppressed.
- `swift build` passed and `scripts/test.sh` executed **57 tests in 8 suites**, all passing. The new parameterized test covers Cancel, confirmation, current recording identity, duplicate suppression, and injected recoverable Trash without personal recordings.
- Release packaging passed at `dist/updates/v0.5.1/Bug.app`; Info.plist reports version 0.5.1/build 10 and deep/strict signature verification passed. Bug quit through its protected application termination path, the installer performed the scoped ScreenCapture reset required by the changed ad-hoc identity, and the verified app reopened from `~/Applications/Bug.app`.
- No live capture or personal recording deletion was performed. The user still needs to confirm Cancel and Move to Trash no longer recur in the real menu UI and reapprove capture permission.

## Inline Custom Trim · v0.5.0

- `swift build` passed and `scripts/test.sh` executed **56 tests in 8 suites**, all passing. Four new synthetic tests cover handle clamping/current-bound initialization, fixed-size waveform analysis across system and microphone tracks, saved manual metadata bounds, cancellation, persistence, and unchanged source bytes.
- The full Custom Trim state was generated from isolated synthetic audio and rendered offscreen at the real 360-point panel width. The rendered editor replaces the recorder card and shows title, retained duration, Cancel, ±5-second controls, Play, Save, mint handles, full waveform, playhead, and three time labels without clipping. This validates layout, not mouse dragging or listening.
- Release packaging passed at `dist/updates/v0.5.0/Bug.app`; Info.plist reports version 0.5.0/build 9 and deep/strict signature verification passed. The running installed app was not terminated or replaced, so canonical installation and permission reapproval remain pending.
- No live audio was captured and no personal recording was opened, edited, exported, or deleted. Hands-on bounds, audition, saved playback/WAV/MP3 equivalence, and relaunch behavior remain in [ACCEPTANCE.md](ACCEPTANCE.md).

## Footer spacing · v0.4.4

- User confirmed v0.4.3 deletion succeeds; screenshot showed 13 sessions moved, zero recordings, and a cramped footer.
- Debug build, 52 tests in 7 suites, and staged release/signature verification passed.
- Inspected an offscreen render matching the empty-library/success-notice state using `--deleted-fixture`: footer bottom padding is visible and empty-state text wraps fully. Real MenuBarExtra resizing remains a hands-on check.
- Packaged at `dist/updates/v0.4.4/Bug.app`; no running copy or personal files were changed.

## Independent bulk confirmation · v0.4.3

- User reported the previous SwiftUI confirmation disappearing with the menu and returning on reopen. Native UI behavior was not reproduced independently; replaced the popover-bound alert with standalone NSAlert ownership.
- Debug build and **52 tests in 7 suites passed**. New parameterized test checks Cancel, confirm, duplicate suppression, and disposable Trash results without a menu view.
- Staged release and signature verification passed at `dist/updates/v0.4.3/Bug.app`. No real recording was deleted or captured. The user subsequently confirmed the successful Delete All interaction; see the v0.4.4 evidence above. Cancel/recovery and capture permissions remain manual checks.

## Session cleanup · v0.4.2

- Read-only directory/metadata inspection found 6 saved recording folders and 7 empty unfinished folders. No personal audio contents were read or deleted.
- Debug build, 51 tests in 7 suites, and staged release/signature verification passed. New test covers an empty-only library, enabled Delete All, and actual Trash of a disposable session.
- Bundle staged at `dist/updates/v0.4.2/Bug.app`; interactive confirmation and capture permission checks remain pending.

## Delete All · v0.4.1

- Debug build and **50 tests in 7 suites passed**. The new parameterized bulk-deletion test runs both success and injected partial failure, using actual macOS Trash on disposable synthetic folders. It verifies confirmed scope, later additions surviving, unfinished-session preservation, totals refresh, and error reporting.
- The first run exposed an order-dependent preexisting storage traversal failure. Removing skipDescendants on a symlink fixed it; the complete suite then passed.
- Offscreen Settings render inspected with Delete All visible. Actual confirmation Cancel/confirm and disabled-state interaction remain hands-on checks.
- Release packaging and strict/deep signature verification passed at `dist/updates/v0.4.1/Bug.app`. No running app was replaced, no personal recordings were touched, and capture permission persistence remains unverified.

## Library storage · v0.4.0

- Debug build and **49 executed tests in 7 suites passed** on the existing Apple Silicon host.
- Three new tests cover combined system/microphone/metadata sizes, unfinished sessions, skipped symlinks, Finder-style removal/restoration and source size changes, and actual macOS Trash/restore with exported-copy preservation. Only disposable synthetic fixture files were touched; no user recording was read or deleted.
- Offscreen render of the real row was inspected: duration/size, count/total, Trim, Trash, and menu fit the 360-point panel. Native confirmation interaction and automatic refresh timing in the real menu bar remain manual acceptance.
- Release package staged at `dist/updates/v0.4.0/Bug.app`; installed/running `dist/Bug.app` was preserved. Signature verification passes with the ad-hoc warning. This does not verify capture authorization or stable permission persistence.
- No live audio was recorded. Bulk cleanup, automatic retention, and disk-space warnings remain unimplemented.

## Permission recovery and packaging follow-up

- The screenshot showed permission enabled while capture failed. Read-only `tccd` logs explicitly reported mismatched code requirements: the saved v0.1.0 hash versus the running v0.3.0 hash. This confirms a signing-identity mismatch, not an inference from the toggle alone.
- `tccutil reset ScreenCapture com.jimmyweber.bug` succeeded. No other app/service grant was reset; recordings and the installed app were untouched. User restart/reapproval and actual capture remain pending.
- `security find-identity -v -p codesigning` found **zero valid identities**. Certificate signing and permission persistence across two builds cannot be claimed as tested.
- Shell syntax check, `swift build`, and **46 tests in 6 suites** passed.
- Default packaging to isolated `.build/package-signing-check/Bug.app` passed, emitted the ad-hoc warning, and passed deep/strict signature verification. It did not replace or launch `dist/Bug.app`.
- Recovery and stable-signing instructions are in [PERMISSIONS.md](PERMISSIONS.md).

## Historical release · v0.3.0 Silence reminder

- The user reported an accidentally forgotten recording producing over 1 GB of silence. This is the motivation for the reminder; it does not establish live signal quality or all earlier acceptance results.
- `swift build` and release packaging passed. v0.3.0 Info.plist and `codesign --verify --deep --strict` passed. The previous bundle was preserved under ignored `dist/previous/`, with no termination of the running app. Quit/reopen is required to load the new code.
- `scripts/test.sh`: **46 executed tests in 6 suites passed**, including all 33 prior tests and 13 new reminder state/store tests.
- New tests use an injected clock, fake capture with tiny synthetic CAF files, and a fake presenter. They cover 15/30/60-second deadlines, initial/no-buffer and later silence, Off/idle, quiet and invalid levels, ignored reminders, Keep resetting the clock, automatic dismissal on resumed audio, live setting changes, preference persistence, stale actions after restart, normal Stop/save exactly once, and start/stop error cleanup.
- The store reminder tests instantiate no menu bar view, verifying that timer/action routing does not depend on the popover being open. They do not verify actual macOS popup visibility.
- Isolated offscreen renders of the actual popup content and gear settings were visually inspected. No live audio was captured by these tests and no real reminder was shown to the user during verification.
- Documentation links and diff formatting checked. Real source/microphone detection, popup button interaction, visibility over other apps/Spaces/full-screen, and remaining recording acceptance require the checklist in [ACCEPTANCE.md](ACCEPTANCE.md).

## Previous release · v0.2.0 Trim

- `swift build` passed on the same Apple Silicon/macOS/Swift host documented below.
- `scripts/test.sh`: **33 executed tests in 4 suites passed**, including 12 Trim tests and all 21 existing tests.
- Verified the 8-second silent head / 10-second silent tail example, 0.5-second padding, internal-pause preservation, stereo channels, quiet audio, phase-cancelling sources, microphone resampling, no-op/silent/short tracks, and adjustable/clamped padding.
- Verified trimmed WAV samples/duration and actual MP3 decode duration; source bytes stay unchanged. Invalid bounds/cancellation preserve an existing destination. Metadata read/write tests cover legacy recordings, saved Trim across relaunch, Undo, stale rename requests, repeated Trim, missing sources, and write failures for both Trim and Undo.
- Offscreen isolated-fixture layout checks covered the **Trim** button, **Undo**/trimmed duration, and padding settings. They did not exercise live UI clicks or capture real audio.
- v0.2.0 release packaging, Info.plist, bundled encoder notices, and `codesign --verify --deep --strict` passed. Updated `dist/Bug.app` is approximately 3.3 MB.
- The prior running app was not terminated. Its bundle was preserved under ignored `dist/previous/` before the new bundle was moved into place. Quit and reopen to use v0.2.0; no active recording was deliberately interrupted.
- Documentation links and diff formatting checked. Real-device and live-listening Trim acceptance remains pending in [ACCEPTANCE.md](ACCEPTANCE.md).

## Original release evidence · v0.1.0

Host: Apple Silicon, macOS 26.6.2, Swift 6.3.3 Command Line Tools. App deployment target: macOS 15.

Implementation baseline: `f468070`. This is a historical evidence record, not a claim that tests were rerun for later documentation-only commits. See [HANDOFF.md](HANDOFF.md) for current status and [ARCHITECTURE.md](ARCHITECTURE.md) for implementation contracts.

## Passed

- Debug build and release packaging.
- `scripts/test.sh`: **21 executed tests in 3 suites**, all passed.
- Capture tests: timestamp alignment, leading/trailing silence, gaps/overlaps, native microphone format, integer PCM conversion, real RMS, invalid samples/timestamps, recoverable interruptions, disk-write failure, and idle-stop behavior.
- Export tests: 24-bit WAV header, stereo and mono mixing, 44.1 → 48 kHz conversion, constant peak attenuation, longer microphone tail, actual 320 kbps MP3 encoding and AVFoundation decoding, atomic replacement, cancellation/failure preservation, and source-path protection.
- Library tests: metadata round trip, chronological ordering, rename persistence, unfinished-session filtering, and path validation.
- `codesign --verify --deep --strict dist/Bug.app`; Info.plist validation.
- Bundled encoder, license, source archive, and build recipe present. No global encoder dependency. Package approximately 3.1 MB.
- Packaged app launched successfully; process remained running without starting capture.

## Not yet verified

Desktop automation timed out reading Bug's menu bar UI. An offscreen SwiftUI/AppKit render was used for layout inspection; this does not verify interactive behavior.

Live ScreenCaptureKit capture, macOS permission prompts, microphone/system sound alignment with real devices, long-running sessions, FaceTime, sleep/device changes, and login-item behavior require the hands-on checks in [ACCEPTANCE.md](ACCEPTANCE.md). No live user audio was captured during development. User feedback did not explicitly confirm those checks. Intel, a universal app, and a separate macOS 15 host have not been tested.

## Test runner note

Plain `swift test` initially compiled the suite but executed zero tests because SwiftPM's generated runner could not import the standalone CLT Testing framework. `scripts/test.sh` supplies framework search paths to the generated runner as well as the test target. The explicit 21-test result above is from this corrected runner.

The corrected runner exposed a test-side buffer-lifetime crash. Capture tests now retain their `AVAudioPCMBuffer` and use `withExtendedLifetime` around unsafe channel reads; the full 21-test suite passed afterward. Keep these lifetimes explicit when adding pointer-based assertions.

## Documentation and repository check · 2026-09-07

GitHub reported `jimmytheghost/bug` as PRIVATE, with `main` synchronized to the initial implementation before documentation edits. README, agent instructions, plan, acceptance status, and encoder packaging notes were reconciled against source. Added canonical architecture and a current handoff. Repository-local Markdown links, code fences, and the documentation diff were checked. This review did not launch the app, record audio, or rerun the audio suite.

## End-of-day documentation audit

Reconciled README, handoff, architecture references, permissions, plan, and acceptance with v0.4.4 source/build 8 and implementation commit `180cf79`. Replaced accumulated handoff history with current behavior, corrected superseded deletion checks, marked the user-confirmed Delete All result, and preserved historical validation evidence. Updated build commands to use staging directories. GitHub reported the repository PRIVATE.

Checked repository-local Markdown file links, paired code fences, version metadata, and diff formatting. This documentation-only pass did not rebuild, launch an app, record audio, reset permissions, or access/delete personal recordings. The 52-test result is from the preceding implementation pass.


## Recurring permission denial after approval · canonical install repair

- At 16:02:53 on 2026-09-07, focused `tccd` logs explicitly compared saved v0.3.0 hash `12d29f34…` with running v0.4.4 `d58f9986…` and reported mismatched code requirements. The user had already enabled the toggle. This reproduces the stale-grant mechanism from the earlier v0.1.0 → v0.3.0 incident.
- Gracefully quit Bug via its application quit action, reset only Bug ScreenCapture, installed unchanged v0.4.4 at `~/Applications/Bug.app`, unregistered repo-local archives, and reopened the canonical copy. Installer source/staging deep/strict signature verification passed.
- Python syntax check and read-only installer check passed. Rechecking the installed identity correctly reported no reset needed. An installation attempt while Bug was running was refused before mutation.
- No live audio was captured, no user recordings were deleted, and no certificate/trust setting was changed. Runtime recovery and the next update's reapproval remain awaiting user verification. This pass changes delivery tooling/docs, not the 52-test app baseline.
