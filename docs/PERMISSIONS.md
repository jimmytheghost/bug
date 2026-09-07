# Capture permissions and installation

## Current repair · 2026-09-07

The latest recurrence was **permission denied after the user enabled Bug**, not a complaint about having to approve an update. At 16:02:53, macOS `tccd` reported `Failed to match existing code requirement`: it compared the running v0.4.4 (`d58f998613fff679f7999be703d66c1e6d431542`) against the saved v0.3.0 requirement (`12d29f345e2a2bb6688f197d38a6e6d2a715ab5f`). An enabled toggle had not replaced the stale identity.

The earlier incident compared v0.3.0 against v0.1.0. The first repair reset that grant, but subsequent delivery still had the user launch ad-hoc builds from successive `dist/updates/` folders. It did not ensure the next approval started with a clean identity. Merely offering optional certificate signing and telling the user to toggle permission again was insufficient.

This pass gracefully quit Bug, reset only `ScreenCapture` for `com.jimmyweber.bug`, installed the existing v0.4.4 binary at `~/Applications/Bug.app`, unregistered repo-local archived bundles from Launch Services, registered the installed copy, and reopened it. No audio was recorded or deleted, no microphone/other-app grant was reset, and no signing identity or trust setting was changed. User reapproval and a successful capture are required to verify runtime recovery.

## Required workflow for every delivered update

1. Build into a staging directory; never overwrite or launch an active bundle:

   ```sh
   ./scripts/package-app.sh "$PWD/.build/delivery"
   ```

2. Stop any active recording and quit Bug. Install the completed package:

   ```sh
   python3 scripts/install-app.py .build/delivery/Bug.app
   open "$HOME/Applications/Bug.app"
   ```

3. When the installer says the identity changed, click Record in the installed copy and approve Bug in **System Settings → Privacy & Security → Screen & System Audio Recording**. Follow Quit & Reopen if requested. Retry Record.
4. Verify the running path and actual recording result. Do not equate an enabled toggle or a valid code signature with capture authorization.

The installer validates the source bundle ID and deep/strict signature, compares designated requirements, refuses to install while a Bug process is running, stages/verifies the copy, resets only Bug's ScreenCapture grant if the identity differs (or on first installation), preserves the old installed bundle under `~/Library/Application Support/Bug/BuildBackups/`, and installs at a single stable path. Matching identities do not trigger a reset. Repo-local `dist/**/Bug.app` copies are unregistered but retained as archives.

Do not open versioned staging/archive copies for normal use. Do not rebuild/re-sign the installed copy after approval. The single path removes ambiguity; the scoped reset before reapproval addresses the observed stale identity. It does not bypass macOS consent or guarantee that permission can never be revoked.

## If enabled permission still fails

First inspect the actual running path and a focused `tccd` log. Do not assume every failure is a stale identity. If the current grant is confirmed stale, quit Bug and explicitly repair even an unchanged installation:

```sh
python3 scripts/install-app.py "$HOME/Applications/Bug.app" --repair-permissions
open "$HOME/Applications/Bug.app"
```

Approve that copy and restart if requested. `--check` prints a read-only installation plan. Never edit the TCC database, reset all services, toggle permissions programmatically, or terminate active capture. A user response to the earlier signing-account question is not required for this workflow.

## Signing background

Ad-hoc default designated requirements are tied to the code hash, so code updates can invalidate grants. See [Apple's requirements technote](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) and [Apple DTS on ScreenCaptureKit](https://developer.apple.com/forums/thread/819406).

`BUG_SIGNING_IDENTITY` still supports an existing Apple Development or Developer ID Application certificate. No valid identity was found in this session. Stable signing can reduce reapproval, but obtaining a certificate is not a prerequisite for the scoped-reset installation workflow requested here. Even certificate-signed updates must go through the installer, and permission persistence must be verified across real updates. Never weaken the designated requirement to a bare bundle ID.
