# Capture permissions and signing

## Confirmed incident · 2026-09-07

The user enabled Bug under **Screen & System Audio Recording**, but v0.3.0 repeatedly returned a permission error. macOS `tccd` logs explicitly reported `Failed to match existing code requirement` for `com.jimmyweber.bug`. The saved requirement was the v0.1.0 cdhash (`2534b0c9…`); the current build required `12d29f34…`.

The release packages used ad-hoc signing (`codesign --sign -`). Its default designated requirement is tied to that version's code hash, so rebuilding can invalidate a previous permission even though System Settings still displays an enabled entry. This is documented by [Apple's code-signing requirements technote](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) and confirmed by [Apple DTS for ScreenCaptureKit](https://developer.apple.com/forums/thread/819406).

`security find-identity -v -p codesigning` found zero valid signing identities on the development Mac. Do not claim the recurring issue is permanently fixed until a stable identity has been configured and tested across updates.

## Restore the current build

1. Stop any active capture and quit Bug. Close the old permission prompt if it is still open.
2. Reset only Bug's screen capture grant, if it has not already been reset for this attempt:

   ```sh
   tccutil reset ScreenCapture com.jimmyweber.bug
   ```

3. Open the intended `dist/Bug.app`, click Record, and approve that copy in **System Settings → Privacy & Security → Screen & System Audio Recording**.
4. Follow macOS's Quit & Reopen instruction if offered, or quit/reopen Bug once after changing permission. Try Record again.

During this incident, the scoped reset above succeeded. The running app was not terminated and the installed bundle was not replaced; user restart/reapproval and a successful recording remain pending. The reset affects Bug only, not other apps or its saved recordings. Do not reset all TCC services, edit the privacy database, or grant permissions programmatically. Microphone permission is separate and was not reset.

Avoid launching archived versions under `dist/previous/` or running the unbundled executable while diagnosing this. Confirm the running bundle path and version instead of assuming the menu bar icon identifies a particular copy.

## Stable signing for future builds

Packaging now supports an existing certificate identity:

```sh
security find-identity -v -p codesigning
BUG_SIGNING_IDENTITY='Apple Development: Your Name (IDENTIFIER)' ./scripts/package-app.sh
```

Replace the example with the exact identity name or fingerprint from the first command. Use the same identity for successive builds. The script signs the encoder and the app with that identity and verifies the bundle. If an explicitly selected identity is unavailable, signing fails rather than silently falling back to ad-hoc signing.

Without `BUG_SIGNING_IDENTITY`, packaging still uses ad-hoc signing and prints a notice about reapproval after updates. A transition from ad-hoc to certificate signing itself needs a fresh permission grant. No certificate was created/imported, no Keychain trust was changed, and no Apple account was accessed during this repair. Do not weaken the designated requirement to a bare bundle identifier to work around privacy checks.

A configured certificate must be verified with an actual initial approval, a second signed build, and a recording attempt after updating. Code signature verification alone does not prove permission persistence. This is independent of distribution notarization.
