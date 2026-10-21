# Bug

Native SwiftUI macOS 15+ menu bar audio recorder, part of the Worklog suite.

- Keep the app lightweight, local, and free of a web runtime or background service.
- Match Worklog's 360-point popover, mint accent, system typography, and subtle rounded cards.
- Capture only on explicit Record. Never simulate live audio or a successful export.
- Keep capture buffers bounded and write audio incrementally to disk.
- Preserve source recordings when export fails or is cancelled. Trim is a reversible metadata edit; never destructively cut the source CAF files. Playback and both exports must honor the same saved bounds.
- For code changes, check `swift build`, `scripts/test.sh`, and `scripts/package-app.sh` after integration. Require an explicit executed test count; plain `swift test` can miss Swift Testing under standalone CLT.
- Avoid recording actual user audio during automated verification. Use the fake capture/presenter and injected monotonic clock for reminder tests. A silence reminder never auto-stops an ignored recording; preserve the agreed Keep/Stop behavior.
- Do not modify the sibling agent-dashboard repository.

## Start here

1. Read [README.md](README.md) for setup and product behavior.
2. Read [docs/HANDOFF.md](docs/HANDOFF.md) for the current state and next work.
3. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for canonical implementation contracts.
4. Read [docs/PLAN.md](docs/PLAN.md), [docs/VALIDATION.md](docs/VALIDATION.md), and [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) before claiming completion or testing live capture.

For permission failures and packaging changes, also read [docs/PERMISSIONS.md](docs/PERMISSIONS.md). Deliver all updates through `scripts/install-app.py` to `~/Applications/Bug.app`; never tell the user to launch a versioned staging copy. The installer resets only Bug ScreenCapture when the designated requirement changes, before user reapproval. Preserve the installed bundle while the user reauthorizes it; validate packaging in a separate output directory. An enabled privacy toggle does not prove the current code identity is authorized.

Keep HANDOFF focused on current behavior and one latest artifact path; place superseded behavior in dated VALIDATION history rather than appending conflicting “latest” sections.

These documents are the repo's canon. Keep implementation facts synchronized with code; record actual validation separately from planned checks. Do not treat user praise as evidence of passed live tests. No previous subagent remains an active dependency; the completed work is in the repo.

## Delivery workflow

The repository is **private** at `https://github.com/jimmytheghost/bug`; preserve that visibility. `origin` points there and `main` tracks `origin/main`. After completing changes, run relevant validation, update affected docs, commit, and push the current branch before reporting completion. Preserve unrelated work and report push failures. Do not commit recordings, generated build output, encoder binaries, or credentials. Documentation-only changes need content/link/diff checks, not a fresh audio test or app launch.

## Documentation maintenance

- README: user setup, features, and navigation.
- HANDOFF: current status, unresolved gaps, and next steps.
- ARCHITECTURE: stable source map, contracts, persistence, and design choices.
- PLAN: scope, completed milestones, and remaining milestones.
- VALIDATION: dated evidence with environment and explicit test counts.
- ACCEPTANCE: hands-on checkboxes; check only with observed results and record date/environment.
- THIRD_PARTY_NOTICES: encoder version, source hash, license, and packaging obligations. Preserve upstream license text verbatim.
- PERMISSIONS: signing identity, scoped recovery, and confirmed permission incidents.

## Public sharing preparation

For public-facing README or release preparation, follow [core/GITHUB-PROJECT-PAGES.md](core/GITHUB-PROJECT-PAGES.md). Import provenance is in [TOOLKIT_IMPORTS.md](TOOLKIT_IMPORTS.md). This repo remains private until the user explicitly authorizes publication; preparation alone does not change visibility or publish a binary. Current publication status and known limits are in [docs/RELEASE.md](docs/RELEASE.md). Bug code uses MIT; preserve LAME’s separate license and bundled source obligations.
