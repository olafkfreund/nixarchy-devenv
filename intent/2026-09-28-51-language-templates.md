---
status: approved
issue: 51
author: olafkfreund
---

# Intent: Rust, Python, Go, and C++ templates

## Problem

The plugin has individual Rust, Python, and Go presets, but no complete
language-focused starter environments for the requested ecosystems and no C++
template. The existing presets provide only the basic devenv language options;
they do not consistently expose the formatter, linter, language server,
debugger, test, and build tooling a project needs on day one.

## Proposed outcome

The create form offers separate Rust, Python, Go, and C++ templates with useful
toolchains and ecosystem-native development tools. Each template remains a
small, readable starting point that users can extend in their own
`devenv.nix`, evaluates with a real devenv, and documents its version/tool
choices.

Every generated project also has the shared encrypted-secret workflow required
by #55: agenix or SOPS-backed storage, runtime-only secret exposure, and safe
helpers for adding, editing, deleting, and rekeying secrets and recipients.

## Affected users and systems

- Users creating language projects from the plugin menu or CLI.
- `data/templates.nix`, template packaging, and the template checker.
- Shared project secret scaffolding and its external generator if presets cannot
  carry the required files safely.
- README, `docs/usage.md`, CLI tests, and real-devenv checks.

## Constraints

- Use devenv's language modules and current upstream option names.
- Prefer native ecosystem tools and nixpkgs packages; avoid installing every
  framework or build system into one template.
- Do not define a second top-level `packages` assignment in a preset after
  `devenv init`.
- Never place plaintext credentials in a template or evaluate secrets in Nix.
- Preserve explicit user consent for activation and secret access.
- New fields or generator behavior need hostile-input and refusal tests.

## Open questions

- Which formatter, linter, language-server, debugger, and test tools form the
  smallest useful baseline for each language?
- Can these remain presets while receiving the shared encrypted-secret files, or
  should they use a common generator scaffold like the cloud templates?
- Should C++ use CMake, Meson, or only the compiler/toolchain as its baseline?
