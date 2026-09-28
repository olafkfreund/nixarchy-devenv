---
status: draft
issue: 54
intent: intent/2026-09-28-54-project-templates.md
---

# Spec: Add Omarchy plugin and NixOS configuration templates

## Design

Add a third catalogue kind, `scaffold`, for built-in generators that create a
small file tree rather than splice option lines or run an external provider
generator. The CLI will expose these entries as ordinary templates, invoke a
packaged scaffold script in the project directory, and pass no provider
selection field to the form. The generator will derive a safe initial name
from the destination directory and leave project-specific identity values
clearly marked for editing.

The two entries are:

- `omarchy-plugin` in the `Omarchy` group. Generate a minimal plugin with
  `manifest.json`, a `BarWidget.qml` entry point, a small `Panel.qml`/model
  example where needed, `qmldir` or supporting files only when required by the
  example, `README.md`, `LICENSE`, and a Node test fixture. The manifest uses
  the current Omarchy schema and a namespaced placeholder ID derived from the
  directory. The generated devenv exposes Node, jq, and Qt's QML lint tool and
  provides a `validate` script that checks the manifest, referenced files, and
  JavaScript tests. It documents that `omarchy plugin validate` and live shell
  testing require an Omarchy installation and are not run by the hermetic
  template check.

- `nixos-config` in the `NixOS` group. Generate a minimal flake with pinned
  nixpkgs input, `hosts/example/configuration.nix`, `modules/README.md`, a
  formatter/linter-oriented devenv, `README.md`, and a `validate` script. The
  flake exposes an example `nixosConfigurations` entry for the host system
  without embedding this machine's hardware, users, host name, or secrets.
  The README explains how to copy hardware configuration, add host/module
  imports, and apply through the user's normal `nixos-rebuild --flake`
  workflow. Agenix is included as the intended system-secret integration, with
  no recipient or secret value generated.

Both scaffolds receive the existing agenix-compatible devenv secret helpers
and encrypted-only `secrets/` directory. The generated README files explain
`secret-add`, `secret-edit`, `secret-delete`, `secret-user-add`, and
`secret-rekey`, and state that credentials, age identities, recipient keys,
and machine-specific configuration are user-managed. No secret is evaluated
by Nix or copied into a generated project.

Extend `Model.js` and its tests so `scaffold` behaves like a generator for
template display and git/allow consent, but does not render a provider field.
Extend `pkgs/cli.nix`, `pkgs/cli.sh`, and `pkgs/templates-check.nix` with the
new kind and packaged scaffold assets. Keep the existing `preset` and
external `generator` contracts unchanged.

## Alternatives rejected

- Presets containing `files.*` options: those files are materialized by
  devenv activation and would not provide an immediate repository tree; they
  also make the generated project depend on a large inline Nix expression.
- A second external template repository: these starters are tightly coupled
  to this catalogue's CLI and secret scaffold and do not need an independent
  release/pinning lifecycle yet.
- Copying a real Omarchy plugin or this repository: it would create accidental
  runtime coupling, carry unrelated implementation complexity, and make the
  starter harder to understand.
- A hardware-specific NixOS host: hardware, users, boot devices, and secrets
  must remain properties of the target machine, not a generic template.
- Automatically enabling services or running `nixos-rebuild`: scaffolding
  must create files only; applying a system configuration remains an explicit
  user action.

## Risks

- Omarchy's plugin manifest and QML imports are runtime contracts that can
  change. Pin the generated example to the currently documented contract and
  keep the live `omarchy plugin validate` step documented as an external check.
- QML lint and NixOS evaluation may be unavailable or expensive on some
  systems. The catalogue must declare supported systems and the check must
  fail clearly rather than silently omit generated files.
- A generated NixOS flake can look valid while still being unsuitable for a
  machine. Use an obviously example host and documentation that requires
  hardware and state-version review before deployment.
- Scaffold files and the devenv secret helpers can drift apart. The generator
  should copy the existing shared assets from the package, and tests should
  assert the helper names and encrypted-only directory contents.

## Verification

- Node model tests cover scaffold parsing, form fields, and argv construction.
- CLI tests cover both IDs, no provider prompt/argument, generated file trees,
  git/allow consent, and refusal cleanup for failed scaffolds.
- `nix flake check --all-systems --no-build` evaluates the package and checks.
- `nix run .#templates-check omarchy-plugin nixos-config` scaffolds both in an
  isolated root, validates their secret files, evaluates devenv, runs their
  lightweight checks, and leaves the real devenv allow list unchanged.
- A manual Omarchy validation command and a manual NixOS flake evaluation are
  documented as follow-up checks requiring the user's target environment.
