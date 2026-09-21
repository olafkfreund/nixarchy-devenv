---
status: draft
issue: 3
intent: intent/2026-09-21-3-android-template.md
---

# Spec: an Android template

## Design

A preset gains two optional attributes:

- **`yaml`:** plain `devenv.yaml` keys, merged into the scaffold that
  `devenv init` writes;
- **`systems`:** the Nix systems the entry is offered on.

The rest of the pipeline stays one path: the index, the splice, and
`templates-check`. Android is the first entry to use either attribute.

### devenv's behaviour this relies on (v2.3.1, read from source)

- `devenv init` writes `devenv.yaml` from `devenv/init/devenv.yaml`. It has
  `inputs.nixpkgs` and **no top-level `nixpkgs:` key**, only a commented
  `# allow_unfree: true` in the pre-2.0 top-level form. The current form is
  `nixpkgs:` → `allow_unfree: true` (`Config.nixpkgs`, `Nixpkgs.allow_unfree`
  in `devenv-core/src/config.rs`).
- The `android` module is `src/modules/integrations/android.nix`. It turns on
  `languages.java` (a JDK), sets `ANDROID_HOME`, and puts the SDK,
  `platform-tools` and an `emulateApp` wrapper in `packages`. Its defaults are
  platforms 32/34/36, build tools 34.0.0, the ABIs `arm64-v8a` and `x86_64`,
  and `emulator`, `systemImages` and `ndk` all **on**.
- nixpkgs' `emulate-app.nix` defaults `includeEmulator` and
  `includeSystemImages` to true, but `// sdkExtraArgs` lets devenv's own
  settings win. So `emulator.enable = false` and `systemImages.enable = false`
  keep them out of the closure, even though the wrapper is always in
  `packages`.
- The module passes `licenseAccepted = true` itself, so no licence key is
  needed.

### `data/templates.nix`

```nix
android = {
  kind = "preset";
  group = "Mobile";
  label = "Android";
  systems = [ "x86_64-linux" ];
  lines = ''
    # The emulator, system images and the NDK are off: flip them on here when
    # you want them. Each is a large download.
    android = {
      enable = true;
      emulator.enable = false;
      systemImages.enable = false;
      ndk.enable = false;
    };
  '';
  yaml = ''
    # The Android SDK is unfree; this project's nixpkgs must allow it.
    nixpkgs:
      allow_unfree: true
  '';
  note = "The Android SDK (platform and build tools, adb) and a JDK. Allows unfree packages in this project's devenv.yaml, because the SDK is unfree. No emulator, system images or NDK until you turn them on in devenv.nix.";
};
```

The header gains:
- `yaml` and `systems` in "Fields";
- a "yaml" paragraph in "The bar for a preset": plain devenv keys, merged,
  never overwriting;
- the option names read at v2.3.1, as for the other presets.

### `pkgs/cli.nix`

- `ids` is filtered by `systems`, taking `stdenv.hostPlatform.system` (with
  `stdenv` added to the arguments). An entry without `systems` is offered
  everywhere. Hidden on aarch64 means absent from the index, from
  `share/presets` and from `templates-check`.
- For a preset with `yaml`, write `share/presets/<id>.yaml` (verbatim, since
  YAML indentation is significant), and add `yaml: true` to its index entry.

### `pkgs/cli.sh`

- **`init`, preset path:** after `splice_preset`, if
  `$share/presets/$tpl.yaml` exists:
  - if `devenv.yaml` already has a top-level `^nixpkgs:` line, refuse (exit 4)
    and print the keys to add by hand. A future `devenv init` that writes one
    must not end up with two;
  - otherwise append a blank line and the file to `devenv.yaml`.
- **`init` in a directory with a `devenv.nix`** (the existing refuse-and-print
  contract) also prints the YAML keys under "and to devenv.yaml:".
- **`new`** goes through `init`, so its existing clean-up of a partial
  directory covers the refusal.
- **`help`** marks YAML presets in the listing.

### `Model.js` and the form

- `parseTemplates` keeps `yaml: t.yaml === true`.
- `formFields` gives a `yaml` template this hint under the template row:
  "Allows unfree packages in this project's devenv.yaml". This is consent
  made visible: the project's nixpkgs configuration changes, and the form
  says so before the user creates anything.

### Tests

- **`tests/stub/devenv` `init`** also writes the real init's `devenv.yaml`
  (inputs, and the commented top-level `allow_unfree`), so the merge is
  exercised against the real shape.
- **`tests/cli.sh`:**
  - `init android` appends the block, and `devenv.yaml` then has exactly one
    `^nixpkgs:`;
  - a `devenv.yaml` that already has `nixpkgs:` exits 4, with the keys on
    stderr;
  - `init android` over an existing `devenv.nix` prints both the lines and the
    YAML;
  - `templates --json` has `yaml: true` for android, and not for python;
  - a template with a `systems` restriction is absent when the system does
    not match. This is a Nix-level check in `flake.nix` `checks`: evaluate the
    cli for aarch64-linux and assert that `android` is not in its index.
- **`tests/model/`:** `parseTemplates` keeps `yaml` (and rejects non-true
  values), and `formFields` hints for a YAML template.

### Docs

- `docs/usage.md` and the README: Android in the template list, the unfree
  note, and how to turn on the emulator.
- `docs/index.md`: the Mobile row, and "sixteen stacks" becomes seventeen
  (on x86_64).

## Alternatives rejected

- **A third template kind** (for example `project`). It would fork the
  index, splice and check paths for one field (decision 2).
- **`permitted_unfree_packages`.** It would have to list every SDK component
  by nixpkgs name, and it breaks silently when devenv adds one (decision 1).
- **Overwriting `devenv.yaml` with our own copy.** It would drop whatever
  devenv's init writes in future versions. Appending keeps devenv's scaffold
  intact.
- **A YAML merge tool (yq).** It is a new runtime dependency for one block.
  The top-level key check plus an append is exact for a file we just watched
  `devenv init` write.
- **Offering Android on aarch64 with a note.** Rejected by decision 4.
- **Pinning `platforms.version` to one platform.** devenv's default (three
  platforms) is what its documentation shows, and a preset should read like
  devenv's own examples. It can be narrowed later if the download proves too
  big.

## Risks

- **The closure is still large.** Three platforms, build tools and a JDK run
  to several hundred MB on the first `devenv shell`. The note says what is
  downloaded; verification measures it.
- **`templates-check` needs network and time.** `devenv info` evaluates
  without building the SDK (the version lists come from nixpkgs' own
  `repo.json`), so it stays a check of evaluation, not of the download.
- **A future devenv init adds `nixpkgs:`.** The refusal path covers it, with
  a clear message instead of a duplicate key.
- **aarch64:** the entry is absent from the index there, so the plugin and the
  CLI never offer it. Evaluating the index for aarch64 in `flake check`
  proves this.
- **Hosts:** x86_64-linux gains a template; aarch64-linux does not change.

## Verification

1. `node tests/run.js` and `bash tests/cli.sh …` pass, new cases included.
2. `nix flake check`, plus `--all-systems --no-build` (with the aarch64 index
   assertion).
3. `nix run .#templates-check android` passes. Also as a negative control:
   with the `yaml` append disabled, `devenv info` fails on the unfree SDK, to
   prove the key is what makes it work.
4. On razer, with the live procedure in AGENTS.md:
   - create an Android project from the form, whose hint shows;
   - enter it;
   - check `adb --version` and `sdkmanager --list_installed`, and that
     `emulator` is **not** on PATH;
   - record the closure size;
   - remove the project from the plugin, and restore razer.
