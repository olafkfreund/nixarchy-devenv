---
status: approved
issue: 3
spec: spec/2026-09-21-3-android-template.md
---

# Plan: an Android template

Branch `feat/3-android-template`. One commit per step, citing the step,
for example `feat(catalogue): android preset (#3, step 1)`.

## Approved decisions (self-contained)

- **Unfree:** the project's `devenv.yaml` gets
  ```yaml
  # The Android SDK is unfree; this project's nixpkgs must allow it.
  nixpkgs:
    allow_unfree: true
  ```
  This is the post-2.0 form (`Config.nixpkgs.allow_unfree` in
  `devenv-core/src/config.rs` at v2.3.1). It is not a
  `permitted_unfree_packages` list.
- **Catalogue:** `preset` gains two optional attributes:
  - `yaml`: devenv.yaml keys, appended to the scaffold;
  - `systems`: the Nix systems the entry is offered on. An entry without it
    is offered everywhere.

  There is no third kind.
- **The Android entry:** group Mobile, label Android,
  `systems = [ "x86_64-linux" ]`, with these lines:
  ```nix
  # The emulator, system images and the NDK are off: flip them on here when
  # you want them. Each is a large download.
  android = {
    enable = true;
    emulator.enable = false;
    systemImages.enable = false;
    ndk.enable = false;
  };
  ```
  The note: "The Android SDK (platform and build tools, adb) and a JDK. Allows
  unfree packages in this project's devenv.yaml, because the SDK is unfree.
  No emulator, system images or NDK until you turn them on in devenv.nix."
- **aarch64-linux:** Android is absent from the index there: hidden, not
  offered with a note.
- **Merge rule:** `devenv init`'s `devenv.yaml` (v2.3.1, `devenv/init/devenv.yaml`)
  has no top-level `nixpkgs:`. Append a blank line and the YAML. If a
  `^nixpkgs:` line already exists, refuse (exit 4) and print the keys to add
  by hand. Never overwrite, and never produce a duplicate key.
- **Existing `devenv.nix`:** `init` keeps refusing, and prints the preset lines
  and then, under "and to devenv.yaml:", the YAML.
- **The form:** a template with `yaml` shows the hint "Allows unfree
  packages in this project's devenv.yaml" before anything is created.
- **devenv facts relied on:**
  - the module sets `licenseAccepted = true` itself;
  - nixpkgs' `emulate-app` defaults are overridden by devenv's `sdkExtraArgs`,
    so "off" really keeps the emulator and system images out of the closure;
  - `devenv info` evaluates without downloading the SDK.

## Steps

1. **`data/templates.nix`:**
   - add the `android` entry, after `flutter`;
   - header: `yaml` and `systems` in "Fields"; a paragraph under "The bar for
     a preset" saying YAML keys are plain devenv keys, appended and never
     overwriting; and the option names read at v2.3.1
     (`src/modules/integrations/android.nix`: `enable`, `emulator.enable`,
     `systemImages.enable`, `ndk.enable`).

   → verify by `nix eval --json -f data/templates.nix android.systems`
   printing `["x86_64-linux"]`.

2. **`pkgs/cli.nix`:**
   - take `stdenv` as an argument;
   - filter `ids` with
     `lib.filter (n: !(templates.${n} ? systems) || lib.elem stdenv.hostPlatform.system templates.${n}.systems)`;
   - `entry` adds `yaml = true` when `t ? yaml`;
   - `share` writes `presets/<id>.yaml` from `writeText` (verbatim, no
     indent);
   - expose `passthru.templateIds = ids`.
   - **`flake.nix` `checks`:** an eval-time assertion, evaluated even under
     `--no-build`:
     `assert system != "aarch64-linux" || !(lib.elem "android" self.packages.${system}.cli.templateIds);`
     plus the reverse for x86_64, wrapped around the existing checks
     attrset.

   → verify by `nix build .#cli` and `jq '.[] | select(.id=="android")' result/share/templates.json`
   having `"yaml": true`, `result/share/presets/android.yaml` existing, and
   `nix flake check --all-systems --no-build` passing.

3. **`pkgs/cli.sh`:**
   - in `cmd_init`'s `preset)` branch, after `splice_preset`:
     ```bash
     if [ -f "$share/presets/$tpl.yaml" ]; then
       if grep -q '^nixpkgs:' devenv.yaml 2>/dev/null; then
         { echo "nixarchy-devenv: devenv.yaml already has a nixpkgs: key. Add these under it by hand:"; echo; sed 's/^/  /' "$share/presets/$tpl.yaml"; } >&2
         exit 4
       fi
       { echo; cat "$share/presets/$tpl.yaml"; } >>devenv.yaml
     fi
     ```
   - the existing-`devenv.nix` refusal also prints the YAML block when it
     exists;
   - `cmd_help` appends ` (devenv.yaml)` to the label of YAML presets.
   - Tests:
     - `tests/stub/devenv` `init` also writes the real init's `devenv.yaml`
       (the `inputs.nixpkgs` block and the commented top-level
       `# allow_unfree: true`);
     - `tests/cli.sh` adds these cases:
       - `init android` → `grep -c '^nixpkgs:' devenv.yaml` is 1, and
         `allow_unfree: true` is present;
       - a stub run whose `devenv.yaml` already has `nixpkgs:` (via a stub
         env switch) → exit 4, `allow_unfree` on stderr, and no second key;
       - `init android` over an existing `devenv.nix` → exit 2, with both
         `android = {` and `allow_unfree` on stderr;
       - `templates --json` → android has `yaml == true`, and python has no
         `yaml`.

   → verify by `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
   passing, with shellcheck clean.

4. **The form's consent line** *(revised during implementation)*.
   `CreateForm.qml:426` shows the chosen template's `note` on the template
   row, never a hint. So a `formFields` hint would never be drawn, and if
   forced it would repeat the note, which already says "Allows unfree
   packages in this project's devenv.yaml". Instead:
   - `pkgs/cli.nix` refuses to build a catalogue where a template with `yaml`
     has a note that does not mention `devenv.yaml` (`lib.assertMsg`,
     evaluated). The consent text is then guaranteed for every future YAML
     preset, not just this one.
   - `Model.js` does not change: nothing in the UI reads a `yaml` flag.

   → verify by `nix build .#cli` passing, and failing with the message when
   android's note has "devenv.yaml" removed (a mutation, not committed).

5. **Docs:**
   - `docs/usage.md` template list: Android, the unfree note, and how to turn
     on the emulator (`android.emulator.enable = true;` and
     `systemImages.enable`);
   - README: the same line;
   - `docs/index.md`: the Mobile row gets Android, and "sixteen stacks"
     becomes "seventeen stacks";
   - AGENTS.md: the preset rule gains "optionally `yaml` keys (appended to
     `devenv.yaml`) and `systems`".

   → verify by reading it back, and `nix flake check`.

6. **Real devenv:**
   - `nix run .#templates-check android` passes;
   - negative control, not committed: a local build whose
     `share/presets/android.yaml` is emptied must fail `devenv info` on the
     unfree SDK.

   → verify by both outcomes, recorded in the PR.

7. **Live on razer** (AGENTS.md "Verifying live"):
   - record `shell.json`'s checksum, the allow file's state, the plugin list,
     theme, DND and workspace;
   - build on razer from `git archive` (`nix copy` is refused there);
   - install the copy and the CLI, enable, and restart;
   - on an empty workspace, open the form (`toggle nixarchy.devenv
     '{"create":true}'`), pick Android, and screenshot the unfree hint;
   - create `t1` under a `mktemp -d` root inside `~/Projects`;
   - enter it and run: `adb --version`, `sdkmanager --list_installed`, and
     `du -sh` of the SDK closure (`nix path-info -Sh` on `$ANDROID_HOME`).
     Also confirm that `$ANDROID_HOME/emulator` and `system-images` are absent.
     *Revised on razer:* `command -v emulator` is **not** empty. It finds
     `tools/emulator`, the 615 KB legacy launcher from SDK Tools 26.1.1,
     which devenv always installs (`tools.version`, with no off switch). Run,
     it fails ("Could not launch …/emulator/qemu/…"), so the real emulator is
     absent. The absent directories are the check. Measured: the SDK is
     1.8 GiB and the profile is 2.9 GiB, both now stated in `docs/usage.md`.
   - remove `t1` from the plugin;
   - restore everything recorded, and diff it.

   → verify by each command's output in the PR, and razer restored.

8. **PR:** links all three artifacts, says `Closes #3`, and gives the results
   of steps 6 and 7.

## Tests

| Command | Expected |
| --- | --- |
| `node tests/run.js` | all pass (Model.js unchanged; see step 4) |
| `nix build .#cli` | passes; fails if a yaml template's note omits devenv.yaml |
| `bash tests/cli.sh …` | all pass, including append, refuse, print and index cases |
| `nix flake check` | passes |
| `nix flake check --all-systems --no-build` | evaluates; the aarch64 index lacks android |
| `nix run .#templates-check android` | ok |
| negative control | `devenv info` fails without the yaml |
| razer | adb works, no emulator, closure size recorded |

## Rollback

Revert the step commits. Projects already created keep their files: plain
devenv.nix lines and a devenv.yaml `nixpkgs:` block, readable and editable
without this tool. To stop allowing unfree packages in such a project, delete
the block.
