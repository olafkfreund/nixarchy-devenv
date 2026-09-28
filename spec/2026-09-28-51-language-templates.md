---
status: approved
issue: 51
intent: intent/2026-09-28-51-language-templates.md
---

# Spec: Rust, Python, Go, and C++ templates

## Design

Add four `preset` entries to `data/templates.nix`, using devenv's language
modules rather than hand-built package lists:

- `rust`: `languages.rust.enable = true`, using the nixpkgs channel so the
  default compiler, Cargo, Clippy, rustfmt, and rust-analyzer stay coherent.
- `python`: Python with `venv.enable` and `uv.enable`, but without automatic
  `uv sync`, because a newly scaffolded project has no `pyproject.toml` yet.
- `go`: `languages.go.enable = true` with the default gopls and Delve support.
- `cpp`: `languages.cplusplus.enable = true` with its default C++ language
  server. It does not choose CMake or Meson; users can add the build system
  that matches their project.

All four entries opt into the shared built-in encrypted-secret scaffold from
#55. That scaffold is implemented once in the plugin CLI/package layer and
adds agenix-compatible `secrets.nix`, an encrypted-only `secrets/` directory,
and devenv scripts for adding, editing, deleting, running, rekeying, and
adding recipients. It must not duplicate the generated top-level `packages`
assignment; helper dependencies belong on the individual devenv scripts.

The templates remain presets and do not create framework-specific source files.
Notes name the toolchain and the user-owned extension points. Update the
catalogue, CLI tests, README, usage guide, and real-devenv template checks.

## Alternatives rejected

- **Install large hand-picked package lists:** rejected because devenv language
  modules already provide the coherent compiler, language server, and core
  tooling, and a second top-level `packages` assignment conflicts with
  `devenv init`.
- **Make one polyglot template:** rejected because the template ID is the user
  interface and each language has different defaults and workflows.
- **Choose CMake or Meson for C++:** rejected because neither is universal and
  selecting one would add a project-structure decision users did not request.
- **Make Python run `uv sync` automatically:** rejected because the scaffold
  has no dependency manifest on first creation.
- **Copy secret helper logic into each language entry:** rejected because it
  would drift and make recipient/deletion safety inconsistent.

## Risks

- Devenv module option names or default tool composition can change; the real
  template check must catch evaluation failures.
- The shared secret scaffold changes every preset's generated project and needs
  focused refusal tests for names, paths, recipients, and plaintext files.
- C++ users may expect a build system immediately; the note must state that the
  template intentionally supplies the toolchain only.
- Python `uv` creates a virtualenv but does not install application dependencies
  until the project adds a manifest.

## Verification

- `node --test 'tests/model/*.test.js'`
- Stub CLI tests assert all four entries and their preset metadata.
- `nix flake check --all-systems --no-build`
- `nix run .#templates-check rust python go cpp`
- Inspect each generated `devenv.nix` and secret scaffold; no credentials or
  plaintext secret values are present.
