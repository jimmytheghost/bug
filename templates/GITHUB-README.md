<!-- Template for a personal project's public GitHub landing page.
Read ../core/GITHUB-PROJECT-PAGES.md before using it. Replace {{FIELDS}}, adapt
commands to the real project, and remove optional/inapplicable sections and
these editor comments before publishing. Never invent an origin story,
screenshot, test result, download, license decision, or platform claim. -->

# {{PROJECT_NAME}}

{{One plain sentence describing the working tool and the problem it solves.}}

<!-- Optional: one or two sentences explaining why Jimmy built it, grounded in
what he actually said. Omit when that background has not been supplied. -->

This is a personal tool I’m sharing as it stands. If it’s useful, take it. If you want something different, fork it and have your agents, or yourself, make it work the way you want. There’s no promise of ongoing support or a release schedule. You don’t need to wait on me to change your copy.

<!-- Optional: use a current screenshot/output, a descriptive alt label, and a
width appropriate to the image. Omit this block if there is no useful image. -->
<img src="{{RELATIVE_SCREENSHOT_PATH}}" alt="{{WHAT_THE_IMAGE_ACTUALLY_SHOWS}}" width="{{DISPLAY_WIDTH}}">

## What it does today

- {{Implemented behavior a person can observe.}}
- {{Another implemented behavior.}}
- {{Relevant personal customization or useful scope detail.}}

{{Important current omissions, in a short factual sentence if needed.}}

<!-- Optional: retain Try it only for a real runnable service, package, or build.
When sharing source only, remove it and lead with Build it yourself instead. -->
## Try it

Requires {{REAL_PREREQUISITES}}. {{Which platforms/architectures were tested, and which were not.}}

[{{DOWNLOAD_OR_USAGE_LABEL}}]({{REAL_PUBLISHED_URL}})

{{Verified installation and launch steps. Mention update/replacement behavior when relevant.}}

{{Signing/notarization, required accounts, or other material installation limits, only if applicable.}}

## Build it yourself

{{Build prerequisites and tested toolchain. Do not imply other versions are unsupported unless known.}}

```sh
git clone {{ACTUAL_REPOSITORY_CLONE_URL}}
cd {{CHECKOUT_DIRECTORY}}
{{ACTUAL_BUILD_COMMAND}}
{{ACTUAL_RUN_OR_INSTALL_COMMAND}}
```

{{Any necessary explanation for those commands. Keep optional/privileged actions separate and clearly labeled.}}

## Where it’s at

{{Current scope and deliberate personal choices. Explain meaningful rough edges without selling a roadmap.}}

{{External services, brittle interfaces, availability/accuracy limits, or other constraints that affect real use. Omit anything irrelevant.}}

{{What is stored locally, what network requests/accounts are needed, and whether the app has telemetry, based on the actual code.}}

<!-- Optional: link deeper docs rather than filling the landing page with internals. -->
[{{SOURCE_OR_ARCHITECTURE_DOCUMENT_LABEL}}]({{REAL_RELATIVE_DOCUMENT_PATH}})

<!-- Optional: include bugs already known from the existing project context.
Do not start a new bug sweep or task list to fill this section. Omit it when no
known bugs have been supplied/documented; do not replace it with a bug-free claim. -->
## Known bugs

- {{Existing known bug: affected behavior, already-known workaround if any, and existing issue link if useful.}}

## Make it yours

Start with [AGENTS.md](AGENTS.md). It describes the existing behavior and validation commands so you or your agents can get oriented.

- `{{REAL_SOURCE_PATH}}`: {{What someone would change here.}}
- `{{ANOTHER_REAL_PATH}}`: {{What it does.}}
- `{{REAL_TEST_OR_CHECK_PATH}}`: {{How to validate meaningful changes.}}

```sh
{{ACTUAL_VALIDATION_COMMAND}}
```

{{Optional links to real architecture notes, validation evidence, or possible next steps.}}

## License

The code is [{{ACTUAL_LICENSE_NAME}}]({{ACTUAL_LICENSE_PATH}}). {{Accurate plain-language summary of its permissions and as-is terms.}}

{{Third-party data, assets, marks, notices, and affiliation statement only where relevant. Do not grant rights the project does not own.}}
