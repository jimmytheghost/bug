# Public GitHub Project Pages

Version 0.2

Use this process when Jimmy asks for a repository's public-facing README or wants a personal tool prepared for public sharing. This concerns the repository landing page and, when useful, GitHub Releases. A hosted GitHub Pages website is a separate request.

Jimmy adopted this approach after [Tipoff](https://github.com/jimmytheghost/tipoff): a personal tool shared in its current state so other people can take it, fork it, and have their agents adapt it. Explain what exists, how to use it, and where it stops. Keep the page useful without presenting a product store, a support service, or a promised release schedule.

Read `VOICE.md` and `WEBSITE-COPY-AND-LAYOUT.md` alongside this guide when available. Jimmy's current instructions and the target project's canon take precedence. Do not change either core document as a side effect of applying this process.

## Start with the actual project

Inspect the target README, AGENTS.md, source entry points, packaging/build scripts, tests, screenshots, existing license, repository visibility, and releases. Establish the actual platform requirements, tested environments, installation/update behavior, data dependencies, and personal customizations.

Document bugs already known from the project’s existing notes, issues, validation records, or the current conversation. Describe the affected behavior and any already-known workaround; link an existing issue when useful. This sharing process does not call for a new bug sweep, code audit for defects, expanded to-do list, or unsolicited fixes. Run only the validation relevant to the work already in scope. If those checks reveal a problem, report it accurately without turning publication into a separate repair project. Do not claim the project is bug-free when no known bugs are documented.

Keep existing work and established project conventions. A request to improve a README does not itself authorize publishing a private repository, changing its license, creating a hosted site, or shipping a binary. Use authorization already provided in the session; do not ask again when Jimmy has explicitly requested the publication. Otherwise finish the reviewable work before the specific remaining decision is needed.

## Write the landing page

Adapt [the README template](../templates/GITHUB-README.md). Its order is a useful default, not a requirement to fill every section.

1. **Project name and plain description.** Say what the tool does in one sentence. Add the reason it was built only when Jimmy supplied it. Use first person only for grounded facts or approved wording.
2. **Shared-as-is framing.** State that people can use, fork, and adapt it, including with their agents. Avoid promises of support, maintenance, availability, or a product roadmap. Use the template's short paragraph rather than inventing a brand personality.
3. **An actual screenshot or useful example.** Show the current interface/output when one is available. Keep images legible on GitHub; a 360-pixel display width suited Tipoff's narrow popover, not every project. Never pass off a mockup as a working result.
4. **What works today.** A compact list of observable behavior. Mention important omissions and deliberate personal choices. Do not describe planned features as implemented.
5. **Try it / build it.** Give verified prerequisites and commands. Distinguish downloadable binaries from source builds, tested from untested platforms, and real downloads from hypothetical releases. Include how to quit/replace an existing app when relevant.
6. **Where it is at.** Document existing known bugs and explain the limits that affect use: brittle sources, required accounts, local settings, missing features, platform coverage, or signing/notarization status. Keep this factual and proportionate to the project.
7. **Make it yours.** Point to AGENTS.md, the few files an agent would actually change, and meaningful validation commands. Let readers adapt the project without requiring Jimmy's involvement.
8. **License and third-party material.** Name the actual license and link to it. Separate code permissions from third-party data, names, artwork, and marks when relevant.

Keep deeper architecture, source behavior, and validation history in linked project docs when they would crowd out the landing page. Use descriptive headings, ordinary prose, and parallel lists where they help scanning. Avoid slogans, testimonials, badges without useful meaning, sales copy, download counts, fake user quotes, decorative feature grids, and invented personal anecdotes.

The desired reader experience is: understand the tool, see its current state, try it or build it, understand its limits, and find where to change it.

## Prepare only what sharing needs

- Before first public publication, review tracked files and reachable Git history for credentials, raw visitor metadata, private paths/context, customer data, and accidentally committed runtime files. Inspect images and release contents too. For an already-public repository, scale review to the changes and any evidence of exposure. Use available scanning tools or a focused inspection; describe the actual coverage without claiming a scan proves the absence of every secret.
- Keep caches, local configuration, signing keys, credentials, and generated builds out of source control. Add relevant ignore rules. Do not publish private toolkit context or copy unrelated projects into the public repository just to give agents background.
- If a credential is found, stop publication of that material, report it without repeating the value, and address revocation/history cleanup as appropriate. Do not silently rewrite shared history. Existing author identity is not automatically a secret or a reason to rewrite commits.
- Preserve an existing license. For a new unlicensed personal tool Jimmy asks to share for reuse and adaptation, MIT is the default working choice used by this template; state that choice in delivery. Do not apply it when ownership or licensing is unclear, silently replace another project's licensing, or claim rights over third-party material. Include the selected license with distributed code/binaries when required by its terms.
- Keep AGENTS.md accurate for the project, its visibility, its design/behavior invariants, and its real validation commands. Do not leave a contradictory instruction to keep an explicitly published repository private. Do not impose Tipoff's commit/push workflow on another project unless its instructions or Jimmy's request support it.
- Run the checks relevant to changed code or packaging and record actual results, including the executed test count. Documentation-only work normally needs content/link/diff checks, not an app rebuild or a new test suite.

Do not add installers, telemetry, signing infrastructure, automatic updates, CI matrices, security programs, or release bureaucracy solely to make a personal repository look professional. Add such work only when the actual project or Jimmy's request calls for it.

## Optional downloadable release

A release helps when a useful build already exists and publication is within scope. Source-only sharing is a complete outcome too; remove download sections and links if no artifact is being published.

Use [the release-notes template](../templates/GITHUB-RELEASE.md) only when publishing a release. Before linking a download:

- Build from a known committed revision, with a matching version/tag. Keep documentation-only follow-up commits distinct from runtime changes.
- Package only intended distributable files, including required license/notice files. Exclude credentials, caches, user files, and development output.
- Extract the archive and check its contents, architecture/platform claims, and signature where applicable. Provide a checksum when useful. A signature check is not proof of notarization, Gatekeeper acceptance, or support on untested systems.
- State exact signing/notarization or installation limitations without claiming a store-quality distribution process. Do not add commands that disable OS protections as the default installation path.
- Draft the release and inspect its notes/assets before publishing when that helps make the final result reviewable. Do not leave the README pointing to an unpublished draft.

Tipoff's Apple Silicon ZIP, ad-hoc signing, checksums, and macOS instructions were specific to Tipoff. Adapt the distribution format to the project; do not require those details for a CLI, web app, or source-only library.

## Finish and verify

Replace or remove every template placeholder and inapplicable example. Check local links, image paths, code blocks, copied commands, release links, and Git diff whitespace. Keep build commands safe to copy; use the project's actual package manager and scripts.

When publication is authorized, commit/push using the project's workflow, verify the intended visibility, and publish any prepared release. Use anonymous access to verify the repository and asset URL when the result should be public. Check that local and remote heads agree and that unrelated work remains intact. If a step fails, report the specific unfinished part rather than calling the project published or synced.

Finish with the repository link, the release link if one exists, a short description of what changed, and actual validation results. Do not describe a private toolkit update as permission to make the toolkit itself public.

## Reference, not boilerplate

The accepted example is [Tipoff's README at the public-sharing revision](https://github.com/jimmytheghost/tipoff/blob/2ff1f6e21b98d3034a93a510a45b7e841126cdfe/README.md), plus its [v0.2.0 release](https://github.com/jimmytheghost/tipoff/releases/tag/v0.2.0). Those public links are optional references; this guide and the templates contain the process without requiring live access to Tipoff.

Reuse the structure and candor. Do not copy Tipoff's Nuggets preference, sports data sources, mint styling, operating-system requirements, test counts, signing status, personal story, or deferred features into another project.

## Import into another project

Copy this file to `core/GITHUB-PROJECT-PAGES.md`, add a conditional reference in the project's AGENTS.md, and record the source revision in TOOLKIT_IMPORTS.md when that record exists. Use `templates/GITHUB-README.md` to draft the project's README.md and `templates/GITHUB-RELEASE.md` only when needed. Keep project-specific details in the target project and leave upstream toolkit files unchanged unless Jimmy requests an update.
