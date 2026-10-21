# Public source publication

Published with explicit user authorization on **2026-10-20** for source version **0.6.1**, build **13**. The repository is **public** at [jimmytheghost/bug](https://github.com/jimmytheghost/bug). No tag, GitHub Release, binary download, or website was published. The release list was empty during preparation.

## Prepared

- README leads with general computer-audio recording: samples, internet radio, music, browser audio, livestreams, calls, and other available sources. Independent backup recording when another app’s recorder fails is an additional use. Individual source compatibility remains unverified. Bug must be started beforehand; audio stops arriving from an app while that app is crashed.
- Source-build and canonical-install instructions, shared-as-is framing, adaptation pointers, existing known bugs, storage costs, and signing/acceptance limits are visible to readers. Detailed controls moved to [USAGE.md](USAGE.md).
- Bug’s original code now uses [MIT](../LICENSE), the toolkit’s default for a previously unlicensed personal tool shared for reuse. Packaging includes that license. LAME retains its upstream license, pinned source archive, and rebuild recipe. Apple system-symbol artwork and vendor marks retain their respective rights.
- Portable project-page guidance/templates were imported with [revision provenance](../TOOLKIT_IMPORTS.md). Private toolkit writing material was not copied.

## Publication review coverage

Reviewed the tracked source tree and all **17 reachable commits / 201 unique file blobs** before this preparation commit, including file inventories and a focused credential-pattern scan. No credential-pattern matches, recordings, generated encoder binaries, encoder archives, or build output were found in that history. The scan covered common GitHub/AWS token shapes, private-key headers, and quoted password/API-key/client-secret/access-token assignments; it does not prove the absence of every secret.

Older `docs/HANDOFF.md` blobs contain the author’s local checkout path. The current handoff removes that path; history and normal author metadata were retained. The path identifies a local personal-project folder, with no credential or recording content. No history rewrite was performed.

The tracked images include the generated mint ladybug icon and two README interface renders: the idle recorder and Custom Trim. The latter uses synthetic audio in an isolated temporary library. These are renders of the current app views, labeled accordingly, rather than live-capture evidence. Images were visually inspected and contain no personal audio or library information. See [image provenance and regeneration](images/README.md).

The isolated package inventory contains only the executable, Info.plist, icon, encoder dylib, MIT license, encoder license/source/recipe/notice, and signature resources. Source archive SHA-256 matches the pinned value in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). This package was inspected locally and is not a published download.

## Validation and remaining limits

See the **2026-10-20** entry in [VALIDATION.md](VALIDATION.md) for executed checks. Debug build, 60 synthetic tests in 8 suites, release packaging, and deep/strict signature verification passed on Apple Silicon/macOS 26.6.2/Swift 6.3.3. The signature is ad hoc; this does not establish notarization, Gatekeeper acceptance, live capture authorization, or other-platform support.

Existing acceptance gaps remain in [ACCEPTANCE.md](ACCEPTANCE.md). They include real capture/listening, individual call-app behavior, microphone alignment, permission persistence, long sessions, and remaining interface interactions. Existing crash-recovery and corrupt-metadata limits are documented in the README and [handoff](HANDOFF.md#known-gaps-and-operational-caveats). No new bug sweep or unrelated fixes were added to this preparation.

## Publication status

The user explicitly authorized public publication on 2026-10-20. GitHub visibility was changed to PUBLIC, and unauthenticated requests returned HTTP 200 for repository metadata, the repository page, README source, and both README images. Repository instructions and current status docs now reflect public visibility. The source toolkit remains private.

A downloadable app is a separate distribution decision. Before publishing one, build from the intended committed revision, choose a matching tag, inspect the archive and notices, state the actual architecture/signing limits, and validate real install/capture behavior without treating synthetic tests as live acceptance. Keep using the canonical installer for delivered updates. This pass preserves the installed app and its permission identity.
