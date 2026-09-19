---
status: approved
issue: 1
spec: spec/2026-09-19-1-devenv-plugin.md
---

# Plan: Keyboard-driven devenv plugin for Omarchy

Branch `feat/1-devenv-plugin`. Make one commit per step, and cite it in the
subject, for example `feat(cli): discovery (#1, step 3)`. If the work deviates
from this plan, update this file in the same commit as the code.

## Approved decisions

Copied from the spec so that this file stands alone.

### Scope and shape

- **Plugin id is `nixarchy.devenv`.** Its kinds are `menu` and `bar-widget`,
  with `keepLoaded: true`. It is structured like nixarchy-distrobox:
  - `Model.js` holds the logic;
  - `DevenvState.qml` is a singleton declared in `qmldir`;
  - `DevenvView.qml` holds the modes;
  - `EnvList.qml`, `CreateForm.qml`, `LogView.qml` and `ShortcutSheet.qml`
    draw;
  - `Panel.qml` is the bar host, with IPC target `nixarchy.devenv.bar`;
  - `Menu.qml` is the menu host, with layer namespace
    `nixarchy-devenv-menu`.
- **The key is `SUPER + ALT + E`**, and the bind description is "Dev
  environments".
- **`homeManagerModules.default`** has the option
  `programs.nixarchy-devenv.keybinding`: a chord matching `[A-Z0-9_ +]+`, or
  null, with default `"SUPER + ALT + E"`. It writes
  `~/.config/hypr/devenv-binds.lua`, which is loaded with
  `pcall(require, "hypr.devenv-binds")`. This is a copy of the pattern in
  nixarchy-microvm's `flake.nix:55`.
- **Default-on is nixarchy#802's job, and it covers the UI only.** devenv is
  never bundled. A missing devenv disables create, enter and up, and shows
  `nixarchy-service-enable devenv && nixarchy apply`. A missing
  `nixarchy-devenv` (a clone-only install) turns the whole panel into an
  install line.
- **Out of scope:**
  - Android, which is a follow-up issue;
  - `--from`-bound directories;
  - any change in the nixarchy repo, which is #802;
  - the leaky nixarchy runner, which #802 deletes.

### CLI `nixarchy-devenv` (`pkgs/cli.nix`)

It is built with `writeShellApplication`. Its runtime inputs are coreutils,
findutils, gnugrep, gnused and jq. `devenv`, `git` and `nix` come from PATH.

**Commands**

| Command | Behaviour |
| --- | --- |
| `templates --json` | The built-in index, then the personal templates. |
| `list --json [--root DIR]…` | Discovery. |
| `status --json DIR` | `devenv processes list` in DIR under `timeout 10`, giving `{state: running\|stopped\|unknown, processes}`. |
| `init [--allow] [--no-git] TEMPLATE [PROVIDER…]` | Scaffolds in `$PWD`. It refuses an existing `devenv.nix`, and in that case prints the preset lines. |
| `new [--allow] [--no-git] --parent DIR --name NAME TEMPLATE [PROVIDER…]` | Refuses an existing `DIR/NAME`, then runs `mkdir` and `init`. |
| `remove --tier files\|state\|folder --confirm PATH --dev N DIR` | Tiered removal. |
| `help` | Lists the templates. |

**Contract**

- `--allow` is off by default. Allowing is never implicit, and allow is never
  re-run over an existing allow.
- Exit codes:
  - 0: ok;
  - 1: usage;
  - 2: refused;
  - 3: missing dependency, with the enable line on stderr;
  - 4: the underlying command failed.
- Output is one JSON document on stdout. Errors go to stderr.
- Every successful create writes `.devenv-template`, containing the
  template id.

**Discovery**

- Walk each root with `find -P ROOT -maxdepth 3 -name devenv.nix -type f`,
  pruning `.git`, `node_modules`, `.devenv` and `.direnv`.
- Add entries from the allow file when `<path>/devenv.nix` exists. The file is
  `$DEVENV_HOME/allowed` if `DEVENV_HOME` is set, otherwise
  `${XDG_DATA_HOME:-~/.local/share}/devenv/allowed`.
  - Malformed lines are skipped and counted in `skipped`.
  - The file is never written.
- A missing or unreadable root goes into `warnings`.
- Entries are deduped by `realpath`, and nested projects stay separate rows.
- Output: `{rows:[…], warnings:[…], skipped:N}`. Row fields:
  - `path`;
  - `name`;
  - `allowed`;
  - `lockfile`;
  - `template`: the content of `.devenv-template`, or `"custom"`;
  - `hasProcesses`: a static grep for `processes.` or `services.`;
  - `dev`: `stat -c %d`;
  - `mtime`.

**Removal: checks run just before deleting**

It refuses (exit 2) unless all of these hold:

- `--confirm` equals DIR;
- `realpath DIR` equals DIR;
- DIR is not `/`, not `$HOME`, and not a configured root or an ancestor of
  one. The roots are passed as `--root`;
- `DIR/devenv.nix` is a regular file;
- `stat -c %d DIR` equals `--dev`;
- `status` is `stopped`, or devenv is missing. `unknown` refuses.

**Removal tiers**

- **`files`** removes `devenv.nix`, `devenv.yaml`, `devenv.lock`,
  `.devenv-template`, and `.devenv/*` except `.devenv/state`. `.envrc` goes
  only if it is byte-identical to the one we write. It then runs
  `devenv revoke` in DIR, if devenv is present.
- **`state`** is `files` plus `.devenv/state`.
- **`folder`** is `rm -rf -- DIR`.

**Revoke** is not `remove`. The plugin runs `devenv revoke` in DIR directly.

### Catalogue (`data/templates.nix`)

**Preset entries** are `{ kind = "preset"; label; group; note; lines; }`.

- `lines` holds ordinary devenv option assignments. `pkgs` and `lib`
  expressions are allowed. The lines create no dependency on nixarchy and
  never set `packages =`.
- They are spliced exactly as nixarchy's `pkgs/dev-init.nix` does:
  - the `# languages.<x>.enable = true;` placeholder is replaced via `sed r/d`;
  - the fallback inserts before the last column-zero `}`;
  - the lines are indented two spaces, keeping blank lines blank.

**Generator entries** are
`{ kind = "generator"; label; group; note; flake; rev; providers; honours = { git; allow; }; }`.

- There is one generator: `cloud`. It runs
  `nix run github:olafkfreund/cloud-projects-templates/<rev> -- <providers…>`
  in the new directory.
- `honours.git = false`, because its `init.sh:38` always runs `git init`.
- Its note mentions that the generated MCP servers need credentials the user
  must restrict.
- The providers are aws, azure, gcp, oci, kubernetes, cloudflare, hetzner
  and digitalocean, with multi-select.

**Groups**

| Group | Templates |
| --- | --- |
| Languages | node, react, typescript, python, go, rust (moved verbatim from nixarchy `data/devenv-presets.nix`), plus java (`languages.java = { enable = true; gradle.enable = true; };`), java-maven (`maven.enable`), kotlin, dotnet, php, ruby |
| Data & ML | ml, jupyter (moved verbatim) |
| Mobile | flutter (`languages.dart = { enable = true; package = pkgs.flutter; };`) |
| Cloud | cloud (the generator) |
| Yours | `~/.config/nixarchy-devenv/templates/<id>/` (see below) |

**Personal templates**

- `template.json` is `{version:1, label, group:"Yours", note}`.
- `devenv.nix` is required, and `devenv.yaml` is optional. Both are copied
  with `cp -n`.
- The id is the directory name and must match `[a-z0-9-]+`.
- On a collision with a built-in id, the built-in wins and a warning is
  emitted.
- Personal templates are never evaluated.

**Build output:** the flake produces `share/templates.json` and
`share/presets/<id>.nix` inside the CLI's store path.

### Plugin behaviour

**Settings** (manifest schema)

| Setting | Default |
| --- | --- |
| `projectRoots` | `["~/Source", "~/Projects"]` |
| `refreshIntervalSec` | 60 (min 10) |
| `terminalEditor` | `""`, which means `$EDITOR`, falling back to `nvim` |
| `hideWhenEmpty` | false |

**Keys**

| Key | Action |
| --- | --- |
| enter | enter |
| e | edit |
| s | up/down |
| p | status and logs |
| g | update |
| a | allow/revoke |
| x | remove (tier chooser) |
| c | create |
| G | user-wide gc (confirmed, labelled user-wide) |
| y | copy path |
| / | filter |
| u | refresh |
| o | log |
| ? | shortcut sheet |

**Argv** (built by `Model.js`, each builder returning null on bad input; the
working directory is always set with `Process.workingDirectory`, never with
`cd`)

- **Enter:** `omarchy-launch-tui --app-id=org.omarchy.devenv-enter devenv shell`.
- **Edit:** `omarchy-launch-tui --app-id=org.omarchy.devenv-edit <editor…> devenv.nix`.
  The editor string is split on whitespace, with no shell, and each word is
  validated. Paths may contain spaces.
- **Up:** `devenv up -d`. The lock is held only until it exits.
- **Down:** `devenv processes down`. It is never blocked by the mutation lock,
  only by a concurrent Down on the same DIR.
- **Update, create and gc** stream into the log under the lock.
- **Status, logs and list** are read-only and never lock.

**Process state** is fetched only for the selected row, with `status --json`.
Every other row shows `·`, meaning not checked.

**Create form**

- name: `[A-Za-z0-9._-]+`;
- parent: a root, or an absolute or `~` path;
- template: the grouped picker;
- providers: shown only for generators;
- `git init`: on by default, and greyed out when `honours.git = false`, with
  the reason shown;
- "Allow automatic activation": off by default;
- a note: "Pins itself on first `devenv shell`; needs network once".

### Pages

- Copy nixarchy-microvm's `docs/` skeleton: `_layouts/home.html`,
  `_layouts/manual.html`, `_includes/logo.html`, `assets/style.css`,
  `assets/manual.js` and `capture.sh`.
- `_config.yml` sets `baseurl: /nixarchy-devenv`, with a `nav` over
  `usage.md` headings.
- `index.md` is the showcase; `usage.md` is the manual.
- The captures are real, of `demo-*` projects under a `mktemp -d` root.
- `docs/img` stays under 8 MB, and a check enforces it.

## Steps

### Phase A: CLI and catalogue

1. **Verify option names.** Read devenv 2.3.1's
   `src/modules/languages/{java,kotlin,dotnet,php,ruby,dart}.nix` at tag
   `v2.3.1` (`gh api repos/cachix/devenv/contents/...?ref=v2.3.1`). Record the
   exact option paths in a comment at the top of `data/templates.nix`. Drop
   any preset whose option does not exist.
   → verify by a comment block that cites the tag, with every new preset
   mapped to a real option.
2. **`data/templates.nix`.**
   - Move the 8 presets and their explanatory comments verbatim from nixarchy
     `data/devenv-presets.nix`.
   - Add the new presets, the `cloud` generator with `rev` set to
     cloud-projects-templates' current `main` SHA, and `group`/`kind` on
     every entry.
   → verify by `nix eval --json -f data/templates.nix | jq 'keys|length'` =
   16 (8 moved + 7 new + cloud).
3. **`pkgs/cli.nix`: `templates` and `init`/`new`.**
   - Port the splice logic and the refusal from `dev-init.nix`.
   - Make `--allow` opt-in and add `--no-git`.
   - Dispatch generators with `nix run <flake>/<rev> -- providers` in the
     target directory.
   - Write `.devenv-template`.
   - Personal templates: `cp -n`.
   → verify by `tests/cli.sh` cases, run with a stub `devenv` on PATH:
   - `init python` in a temp dir produces the lines in `devenv.nix`, and the
     stub records no `allow`;
   - `init --allow` records `allow`;
   - a second `init` exits 2;
   - `new` into an existing dir exits 2;
   - an unknown template exits 1;
   - no devenv exits 3.
4. **`pkgs/cli.nix`: `list` and `status`.**
   → verify by `tests/cli.sh` against a tmp tree covering:
   - nested projects;
   - a symlinked project, which is not followed;
   - a missing root, which lands in `warnings`;
   - an allow file with a malformed line (`skipped: 1`), a dead path (hidden)
     and a live path outside the roots (listed);
   - `DEVENV_HOME` and `XDG_DATA_HOME` honoured;
   - an allow file whose checksum is unchanged afterwards;
   - `status` with the stub printing running, stopped, and hanging (giving
     `unknown` after the timeout, which the test shortens by setting
     `NIXARCHY_DEVENV_STATUS_TIMEOUT=1`).
5. **`flake.nix`.** It provides:
   - `packages.{default,nixarchy-devenv,cli}`, with the plugin built from an
     explicit `files` list via `runCommand` copies;
   - `homeManagerModules.default`;
   - `checks.default`: the Node tests, `tests/cli.sh`, manifest `jq -e`,
     entry points present, the `qmldir` singleton line, no symlinks (package
     and repo), no pacman/yay, no hex colours, `docs/img` < 8 MB;
   - `apps.templates-check`.
   → verify by `nix flake check` and
   `nix flake check --all-systems --no-build`.
6. **`templates-check` app.** For every preset and for `cloud aws`:
   - scaffold with the real CLI and the real devenv;
   - run `devenv info`;
   - for flutter, also run `devenv shell -- flutter --version`.
   Run it under `env -i` with a temp `HOME`, `XDG_DATA_HOME`,
   `XDG_STATE_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME`, `DEVENV_HOME`
   unset, and `PATH`/`NIX_*` passed through. Before and after, assert that
   the `sha256sum` of the invoking user's real `allowed` file is unchanged.
   → verify by `nix run .#templates-check` on p620: all entries OK, and the
   checksum is unchanged.

### Phase B: UI

7. **`Model.js` and `tests/model/*.test.js`.** Copy `tests/harness.js` and
   `tests/run.js` from nixarchy-distrobox unchanged. Model.js provides:
   - parse `list`/`templates`/`status` JSON, tolerating unknown fields;
   - rows and sorting (allowed first, then mtime);
   - filtering;
   - `validateForm`: name, parent, template, providers;
   - every argv builder (enter, edit, up, down, update, allow, revoke, gc,
     new, remove, status, list, templates), each returning null on bad input;
   - `settingsFor`, using length checks, not `Array.isArray`;
   - the editor string split;
   - availability: which actions a missing devenv or CLI disables;
   - pre-checks for remove, covering the same list as the CLI, as a fast UI
     refusal.

   Test files: `parsing`, `rows`, `form`, `commands`, `settings`,
   `availability` and `remove`. Every form field and argv builder gets a
   hostile-input row (`;`, `$()`, a newline, `..`, a leading `-`, an empty
   string, very long input).
   → verify by `node tests/run.js` all passing.
8. **`manifest.json`, `qmldir`, `DevenvState.qml`.**
   - Polling: the bar polls slowly at `refreshIntervalSec`, and an open
     surface polls every 5 s. Nothing polls while every surface is closed,
     except the bar's slow poll.
   - The mutation lock covers create, update, up (startup only), allow,
     revoke, gc and remove. Down is exempt.
   - The stream log is bounded to 2,000 lines.
   - Dependency probes run on first open (`command -v` via
     `Process ["sh","-c"]` is **not** allowed; instead run
     `nixarchy-devenv help` and `devenv version` and read the exit status and
     errors).
   - The selected-row status fetch is debounced by 300 ms.
   → verify by `omarchy plugin validate` on the built package, and `qs log`
   clean after `omarchy-restart-shell`.
9. **`DevenvView.qml`, `EnvList.qml`, `LogView.qml`, `ShortcutSheet.qml`,
   `Panel.qml`, `Menu.qml`.**
   - Start from distrobox's counterparts, rename, and swap the columns: name,
     path (elided), template, allowed glyph, lockfile glyph, process state.
   - Keys as listed in Approved decisions.
   - Use `Color.*`/`Style.*`/`Border.*` only.
   - `open()` resets the view and focuses via `Qt.callLater`.
   - IPC `open`/`toggle`, with the arguments `{create:true}` and
     `{path:"…"}`, which selects that row.
   → verify live (AGENTS.md "Verifying live" 1–5): the menu and popup open,
   the list shows the p620 projects under `~/Source`, the filter works, `?`
   shows the sheet, and `hyprctl layers -j` shows `nixarchy-devenv-menu`.
10. **`CreateForm.qml`.**
    - The grouped template picker.
    - A provider multi-select for generators.
    - The git toggle greyed out with its reason when `honours.git` is false.
    - The allow toggle, off by default.
    - The first-activation note.
    - Output streams to the log.
    → verify live by creating `t1` (python) and `t2` (cloud, aws) under
    `mktemp -d`, a root added in settings. Both appear in the list with
    their template id, and `t1` is not allowed. `t1`'s `devenv shell`
    succeeds from Enter.
11. **The rest of the actions, wired up:** edit, up/down, status/logs,
    update, allow/revoke, gc (confirm dialog text: "Deletes old devenv shell
    generations for your user, across all projects"), and copy.
    → verify live on a `t3` preset carrying `processes.hello.exec = "sleep 600";`
    (written by hand after create):
    - up, and status shows running;
    - down, and the status shows stopped;
    - down is still possible while an update streams in `t1`;
    - allow, then revoke, and `allowed` flips;
    - edit opens the editor on `devenv.nix`.
12. **`devenv-binds.lua` and `share/omarchy-menu.jsonc`.**
    - The binds file is `o.bind("SUPER + ALT + E", "Dev environments", "omarchy-shell shell toggle nixarchy.devenv '{}'")`.
    - The menu row is `apps.devenv`, with aliases devenv, environments,
      projects and dev shell.
    - Activate the Home Manager module on p620 through a local
      `home-manager` test profile, or copy the file by hand as the no-Nix
      path documents.
    → verify that Super+Alt+E toggles the menu, and `hyprctl binds -j` shows
    one E bind with that description.

### Phase C: Removal (its own review point)

13. **The removal CLI and UI.**
    - `remove` in `pkgs/cli.nix` implements the checks and tiers above.
    - The tier chooser in `DevenvView`:
      - Revoke, the default highlight;
      - Remove devenv files (keeps `.devenv/state`);
      - Remove files and state;
      - Delete folder, which requires typing the name.
      The dialog shows the full canonical path.
    - Removal is refused while a process runs or its state is unknown, with
      the reason shown.
    → verify with `tests/cli.sh` removal cases in a tmp tree. Each is a
    refusal with exit 2 and nothing deleted:
    - a symlinked DIR;
    - DIR = `$HOME`;
    - DIR = a root;
    - DIR = a root's parent;
    - `--confirm` mismatch;
    - `--dev` mismatch;
    - no `devenv.nix`;
    - status running;
    - status unknown.

    And the success cases:
    - `files` leaves `.devenv/state/x` and the project source, and removes
      `.envrc` only when it is byte-identical;
    - `state` removes `.devenv/state`;
    - `folder` removes DIR;
    - the stub records `revoke`.

    Then verify live by removing `t1` with each tier in turn, from recreated
    copies.

### Phase D: Docs and Pages

14. **`README.md`, `docs/usage.md`, `AGENTS.md`.** The README and usage cover:
    - requirements (devenv; the CLI when not installed via Nix);
    - install on NixOS/nixarchy (flake input + `homeManagerModules`) and
      without Nix;
    - the bar popup and the menu;
    - everyday tasks;
    - templates, including personal templates;
    - removal tiers;
    - settings;
    - troubleshooting.

    AGENTS.md: drop the "design stage" banner, and fix anything that drifted
    during implementation.
    → verify by a fresh-clone `omarchy plugin validate`, plus a fresh clone
    with no CLI on PATH that opens and shows the install line.
15. **Pages site.**
    - Copy the microvm skeleton and write `_config.yml`.
    - `index.md`: a hero video, a feature grid, and a template gallery by
      group.
    - `usage.md` is served as the manual.
    - `docs/capture.sh` supports `--setup`, `--shot` and `--teardown` over a
      `mktemp -d` root of `demo-*` projects. It saves and restores
      `shell.json` and `omarchy-menu.jsonc`.
    → verify:
    - `jekyll build` builds locally, via `nix shell nixpkgs#jekyll`;
    - after the merge, https://olafkfreund.github.io/nixarchy-devenv/ renders;
    - `du -sh docs/img` is under 8 MB.
16. **Captures.** Follow AGENTS.md "Retaking the captures". The stills are:
    - the menu;
    - the popup;
    - the create form;
    - the provider picker;
    - the removal tier dialog;
    - the log;
    - the Omarchy menu row.

    Plus one WebM/MP4 of create → enter. Look at every still and at a frame
    sheet of the video.
    → verify that teardown leaves the project list, `shell.json` and
    `omarchy-menu.jsonc` identical to the pre-capture snapshot.
17. **PR.** Open the PR from `feat/1-devenv-plugin`. It closes #1, links
    intent/spec/plan, and lists the follow-ups:
    - Android;
    - `--from` environments;
    - nixarchy#802.

## Tests

| Command | Expected |
| --- | --- |
| `node tests/run.js` | all pass, 0 failures |
| `nix flake check` | passes: Node tests, `tests/cli.sh`, manifest/entry points/singleton, no symlinks, no pacman/yay, no hex colours, `docs/img` < 8 MB |
| `nix flake check --all-systems --no-build` | aarch64 evaluates |
| `nix run .#templates-check` | every preset and `cloud aws` pass `devenv info`, and the real `allowed` checksum is unchanged. Needs network, run on p620 |
| `omarchy plugin validate "$(readlink -f result)"` and on a fresh clone | valid |
| Live checks in steps 9–13 and 16 | as stated there |

## Rollback

- **Nothing outside this repo changes in this task**, and nixarchy keeps its
  own devenv handling until #802 lands.
- **To undo on a desktop:**
  - run `omarchy plugin disable nixarchy.devenv`;
  - remove `~/.config/omarchy/plugins/nixarchy.devenv` and
    `~/.config/hypr/devenv-binds.lua`, or drop the Home Manager module
    import;
  - delete the `apps.devenv` row if it was pasted in.
- **Projects created with the plugin are ordinary devenv projects**, with one
  extra `.devenv-template` file. They keep working without it.
- **Repo:** revert the merge commit. Pages falls back to the previous build,
  or none.

## Deviations

- **Steps 1–2** went into one commit (`d568753`) instead of two.
- **Step 3: the CLI script is `pkgs/cli.sh`**, which `pkgs/cli.nix` reads with
  `builtins.readFile` after prepending `share=<store path>`. It is a plain
  file so that shellcheck and `tests/cli.sh` see the real script.
- **Step 3: `tests/stub/{devenv,nix}`** record their calls and stand in for
  devenv and nix. `tests/cli.sh` runs on a minimal PATH built from symlinked
  tools, so it can never reach the user's real devenv, nix or network. (Found
  the hard way: an early run inherited PATH, and executed the real cloud
  generator in a temp directory.)
- **Step 3: project names must start with a letter, digit or `_`.** A name
  like `-x` would read as an option to later commands.
- **Step 3: `--no-git` for a generator whose `honours_git` is false exits 1**,
  rather than silently running `git init`.
- **Step 5: `flake.nix` grows with the files it packages.** Step 5 ships the
  CLI package plus the `cli` and `repo` checks. The plugin package and its
  manifest, singleton and colour checks arrive in step 8, with the manifest.
  The Node test check arrives in step 7. `homeManagerModules` arrives in
  step 12, with `devenv-binds.lua`. Declaring them earlier would fail
  `nix flake check` on files that do not exist yet.
