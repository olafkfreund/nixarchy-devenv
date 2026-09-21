---
status: draft
issue: 3
author: olafkfreund
---

# Intent: an Android template

Closes #3.

## Problem

The catalogue's Mobile group has one entry, Flutter. There is no Android
template, although devenv has an `android` module. Android does not fit the
catalogue as it stands:

- **The SDK is unfree**, and a project's nixpkgs is configured by its own
  `devenv.yaml`, not by the host. A NixOS host with `allowUnfree = true` still
  cannot build a project's Android SDK unless that project's `devenv.yaml`
  says `nixpkgs.allow_unfree: true` (or `permitted_unfree_packages`).
- **A preset is "devenv option lines only"** (`data/templates.nix` header, and
  AGENTS.md). It has no way to write `devenv.yaml` keys, so an Android preset
  would scaffold a project that fails its first `devenv shell`.
- **devenv's defaults are heavy.** `android.emulator.enable`,
  `systemImages.enable` and `ndk.enable` are all on by default. Taken as is,
  the template would download an emulator, system images and the NDK for
  someone who only wanted to build an app.

Facts read from devenv v2.3.1:

- The module is `src/modules/integrations/android.nix`, so the options are
  `android.*`, not `languages.android`.
- It passes `licenseAccepted = true` to nixpkgs' androidenv itself, so SDK
  licence acceptance needs no switch of ours. The `devenv.yaml` key
  `nixpkgs.android_sdk.accept_license` also exists.
- Its version lists come from `repo.json` inside nixpkgs. So `devenv info`
  evaluates the module without downloading the SDK, and `templates-check` can
  prove the template evaluates without a multi-gigabyte download.
- The optional `android-nixpkgs` input switches the SDK source.

Personal templates can already carry a `devenv.yaml` (`pkgs/cli.sh`,
`init`: copied with `cp -n`, and an existing one is kept). Built-in templates
cannot.

## Proposed outcome

- `nixarchy-devenv new … android` and the create form's Mobile group give a
  project that enters with `devenv shell` on the first try. It has Android's
  platform and build tools, and `adb` on PATH.
- The project's `devenv.yaml` carries the unfree setting the SDK needs. The
  template's note says so plainly, because it changes what the project's
  nixpkgs will build.
- By default the project does not pull the emulator, system images or NDK.
  The note says how to turn them on.
- `templates-check` passes for it without downloading the SDK.
- `docs/usage.md`, the README and the site's template table list it.

## Affected users and systems

- Anyone creating a project from the catalogue. Existing presets and projects
  do not change.
- `data/templates.nix` (the entry, and a catalogue capability for YAML keys),
  `pkgs/cli.nix` (building the YAML beside the preset lines), `pkgs/cli.sh`
  (`init` writing or refusing YAML keys), `pkgs/templates-check.nix`,
  `Model.js` (if the form shows the unfree note), the tests, and the docs.
- Hosts: x86_64-linux. aarch64-linux needs checking: androidenv's emulator
  and some SDK parts are x86_64-only.

## Constraints

- **A preset stays readable by someone without nixarchy.** Whatever writes
  `devenv.yaml` writes plain devenv keys, nothing of ours.
- **Never overwrite a user's `devenv.yaml`.** `devenv init` writes one, so our
  keys are merged into the scaffold. They are never written over a file
  someone has edited. `init` in an existing project keeps its refuse-and-print
  contract, printing the YAML keys as well as the lines.
- **Consent.** Enabling unfree packages for a project is a visible choice. It
  must not happen silently. The note and the form say it.
- **`templates-check` stays hermetic** and must pass before release. It must
  not need the SDK download.
- **Option names come from devenv's source**, cited in the catalogue header as
  for the other presets.

## Open questions

1. **Unfree scope.** Use `nixpkgs.allow_unfree: true` (simple, and covers
   every SDK component), or a `permitted_unfree_packages` list (narrower,
   but it has to name every component and breaks when devenv adds one)?
   Proposal: `allow_unfree`, stated in the note.
2. **Catalogue shape.** An optional `yaml` attribute on `preset`, or a third
   kind? Proposal: an optional `yaml` attribute, so the rest of the pipeline
   (index, splice, `templates-check`) stays one path.
3. **The default SDK contents.** Proposal: platform tools and build tools on,
   and the emulator, system images and NDK off. Or should the emulator be on,
   because many people want one?
4. **aarch64-linux.** Offer the template there with a note, or hide it?
