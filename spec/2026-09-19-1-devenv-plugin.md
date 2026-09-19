---
status: approved
issue: 1
intent: intent/2026-09-19-1-devenv-plugin.md
---

# Spec: Keyboard-driven devenv plugin for Omarchy

## Decisions on the intent's open questions

The intent was approved with its open questions unanswered. Each one gets
the recommended default below. Any of them can be changed at spec review.

| # | Question | Decision |
| --- | --- | --- |
| 1 | Default-on turns on `services.devenv` too? | **No.** nixarchy#802 turns on the UI only. The plugin detects a missing `devenv` and shows the one-line enable (`nixarchy-service-enable devenv && nixarchy apply`). The closure size is measured in #802 before anything more is decided. |
| 2 | Project roots | `projectRoots` setting, default `["~/Source", "~/Projects"]`. Depth 3, symlinks not followed. |
| 3 | What Enter runs | An explicit `devenv shell` in a new terminal, so it works without the shell hook. |
| 4 | Android | **Split out** to a follow-up issue. It needs a `devenv.yaml` capability, so v1 does not ship it. |
| 5 | Several tasks, or one? | **One task (#1), phased plan steps**, in this order: CLI and catalogue, then UI, then removal, then Pages. Each phase is its own commit set, and removal is reviewed as its own step. |
| 6 | nixarchy runner leak | Fixed in nixarchy#802, where the runner is deleted anyway. This repo's `templates-check` is hermetic from the start. #802's spec also covers cleaning the 80 stale entries, which only the user may do, with `devenv revoke` or by editing the file. |
| 7 | `--from`-bound directories | Out of scope for v1, and listed as a follow-up in AGENTS.md. |

## Design

Three parts ship from one flake: a CLI that does everything, a catalogue it
reads, and a QML plugin that draws the CLI's JSON and calls it by argv. The
plugin never touches the filesystem or devenv directly, except to launch a
terminal.

### 1. CLI: `nixarchy-devenv` (`pkgs/cli.nix`)

This is a `writeShellApplication` that grows out of nixarchy's
`pkgs/dev-init.nix`. Its runtime inputs are coreutils, findutils, gnugrep,
gnused and jq. `devenv`, `git` and `nix` come from PATH and are never
bundled; see the AGENTS.md rule.

| Command | Does | Output |
| --- | --- | --- |
| `templates --json` | Prints the built-in index, then `~/.config/nixarchy-devenv/templates/*/template.json`. | JSON array |
| `list --json [--root DIR]…` | Discovery (below) | JSON array |
| `status --json DIR` | Runs `devenv processes list` in DIR, bounded by a 10 s timeout. | `{state: running\|stopped\|unknown, processes:[…]}` |
| `init [--allow] [--no-git] TEMPLATE [PROVIDER…]` | Scaffolds into the current directory. The contract of `nixarchy dev init` is kept: it refuses an existing `devenv.nix` and prints the lines. | text |
| `new [--allow] [--no-git] --parent DIR --name NAME TEMPLATE [PROVIDER…]` | The GUI path. It refuses an existing `DIR/NAME`, then runs `mkdir` followed by `init`. | text, streamed |
| `remove --tier files\|state\|folder --confirm PATH DIR` | Tiered removal with executor-side checks (below). | text, and an exit code per refusal |
| `help` | Lists the templates. This is the old `nixarchy dev init` output. | text |

- **`--allow` is off by default.** Today's unconditional `devenv allow`
  (`nixarchy/pkgs/dev-init.nix:152`) goes away. This is a behaviour change for
  `nixarchy dev init`, and #802 documents it.
- **Exit codes:**
  - 0: ok;
  - 1: usage;
  - 2: refused (existing file, safety check);
  - 3: missing dependency (`devenv`, `git`, `nix`), with the enable line on
    stderr;
  - 4: the command it ran failed.
- **JSON is always one document on stdout.** Errors go to stderr.

**Discovery (`list`)**
- The roots are walked with `find -P ROOT -maxdepth 3 -name devenv.nix -type f`,
  pruning `.git`, `node_modules`, `.devenv` and `.direnv`.
- Entries from `$XDG_DATA_HOME/devenv/allowed` (falling back to
  `~/.local/share/devenv/allowed`, and honouring `DEVENV_HOME` if set) are
  added when `<path>/devenv.nix` exists. Malformed lines are skipped and
  counted in the `skipped` field. The file is never written.
- A root that is missing or unreadable is reported in `warnings`, not treated
  as empty-and-fine.
- Entries are deduped by `realpath`. A nested project is listed on its own
  row.
- Row fields:
  - `path`;
  - `name` (the basename);
  - `allowed` (a boolean, from the allow file);
  - `lockfile` (a boolean: `devenv.lock` present);
  - `template` (from `.devenv-template` if we wrote one at create time,
    otherwise `"custom"`);
  - `hasProcesses` (a static grep for `processes.` / `services.` in
    `devenv.nix`, only to decide whether up/down are offered);
  - `mtime`.

**Removal (`remove`)**
- `--confirm` must equal the canonical DIR, and the UI passes the full path
  the user saw. Then, just before any deletion, the CLI requires all of the
  following, and refuses otherwise:
  - `realpath DIR == DIR`, so there is no symlink component;
  - DIR is not `/`, not `$HOME`, and not a configured root or an ancestor of
    one;
  - `DIR/devenv.nix` exists and is a regular file;
  - `devenv processes list` reports no running processes, or devenv is
    missing. `unknown` counts as running, so the command refuses;
  - DIR is on the same device it was on when listed (`stat -c %d`, passed by
    the UI as `--dev`).
- **Tier `files`** removes `devenv.nix`, `devenv.yaml`, `devenv.lock`,
  `.devenv-template`, and `.devenv/` except `.devenv/state`. `.envrc` goes
  only if it is byte-identical to the one we wrote. It then runs
  `devenv revoke` in DIR.
- **Tier `state`** is tier `files` plus `.devenv/state`.
- **Tier `folder`** removes DIR entirely, after all the checks above. The UI
  demands the name typed.
- **Revoke on its own is not `remove`.** It is `devenv revoke`, run in DIR by
  the plugin directly, and it is the ordinary "take this off my list" action.
  A revoked environment disappears from the list unless it is under a root.

### 2. Catalogue: `data/templates.nix`

Each entry is one of two kinds:

- **`kind = "preset"`**: `{ label, group, note, lines }`, with `lines`
  spliced exactly as `dev-init.nix` does today (the placeholder replacement,
  and the closing-brace fallback). The bar is carried over with the codex
  correction. Lines are ordinary devenv option assignments and may use
  `pkgs`/`lib` expressions (the existing `ml` and `jupyter` presets do).
  They create no dependency on nixarchy and set no `packages =`.
- **`kind = "generator"`**: `{ label, group, note, run, providers,
  honours = { git = bool; allow = bool; }, rev }`. There is one entry in v1,
  `cloud`, which runs
  `nix run github:olafkfreund/cloud-projects-templates/<rev> -- <providers…>`
  inside the new directory. It is pinned by `rev` in the catalogue, and a
  bump is its own commit. `honours.git = false`, because `init.sh:38`
  always runs `git init`. The form greys out that toggle and says why. Its
  note states that some of the generated MCP servers need credentials the
  user must restrict.

Groups and the v1 presets:

| Group | Presets |
| --- | --- |
| Languages | node, react, typescript, python, go, rust (moved), plus java (JDK + Gradle), java-maven, kotlin, dotnet, php, ruby |
| Data & ML | ml, jupyter (moved) |
| Mobile | flutter (`languages.dart = { enable = true; package = pkgs.flutter; };`). devenv has no flutter module, but `dart.nix` takes a `package`. `templates-check` must show that `flutter` is on PATH. Android is a follow-up. |
| Cloud | cloud (the generator; the provider picker offers aws, azure, gcp, oci, kubernetes, cloudflare, hetzner and digitalocean, with multi-select) |
| Yours | `~/.config/nixarchy-devenv/templates/<id>/` |

- **Every new preset's option names are read from devenv's
  `src/modules/languages/*.nix`.** Upstream main (checked 2026-09-19) has
  java (`jdk.package`, `maven.enable`, `gradle.enable`, `lsp`), kotlin, dotnet,
  php, ruby and dart. They are re-read at devenv 2.3.1 in the plan, and any
  that are missing are dropped, not guessed.
- **Personal templates, v1 format:** `template.json` is
  `{ "version": 1, "label": "…", "group": "Yours", "note": "…" }`. Next to it
  is a `devenv.nix`, plus an optional `devenv.yaml`, copied with `cp -n`. The
  id is the directory name and must match `[a-z0-9-]+`. On a collision with a
  built-in id, the built-in wins and a warning appears in the `templates`
  output. The template is never evaluated to list it.
- The flake builds `share/templates.json` (the index) and one `<id>.nix` per
  preset into the CLI's store path. The plugin only ever sees the CLI's JSON.

### 3. Plugin (QML)

It has the same structure as nixarchy-distrobox (see AGENTS.md "Layout"),
with id `nixarchy.devenv`.

**Settings:**

| Setting | Default |
| --- | --- |
| `projectRoots` | `["~/Source", "~/Projects"]` |
| `refreshIntervalSec` | 60 |
| `terminalEditor` | `""`, which means `$EDITOR`, falling back to `nvim` |
| `hideWhenEmpty` | false |

**Keys**, following distrobox where it has an equivalent:

| Key | Action |
| --- | --- |
| enter | Enter |
| e | edit `devenv.nix` |
| s | up/down, toggled |
| p | status and logs of the selected environment |
| g | update |
| a | allow/revoke |
| x | remove, which opens the tier chooser |
| c | create |
| G | user-wide gc, confirmed |
| y | copy the path |
| / | filter |
| u | refresh |
| o | the running log |
| ? | the shortcut sheet |

**Argv (built in `Model.js`, returning null on bad input):**
- Enter:
  `omarchy-launch-tui --app-id=org.omarchy.devenv-enter devenv shell`, with
  the working directory set to the project. `Process.workingDirectory` is
  used, not `cd` in a string. This matches `enterArgv` in
  distrobox's Model.js:534.
- Edit: `omarchy-launch-tui … <editor argv> devenv.nix`. An `$EDITOR` value
  containing arguments is split on whitespace only (no shell) and
  validated. Paths with spaces are allowed, because nothing here goes
  through `eval`. This differs from distrobox.
- Up: `devenv up -d`. The lock is held only until it exits.
- Down: `devenv processes down`. It is **never** refused because of the
  mutation lock. Only another concurrent Down on the same directory is.
- Update, create and gc stream into the log view under the lock. Status and
  logs are read-only and never lock.

**Process state:** it is shown only for the selected row, fetched on
selection through `status --json` with a timeout. Everything else shows `·`,
meaning not checked. Nothing claims "running" without the fetch.

**Missing dependencies:** the plugin probes for `nixarchy-devenv` and `devenv`
on the first open. If the CLI is missing, the whole panel shows the install
line (the clone-install case). If devenv is missing, the list still works,
and create, enter and up are disabled with the enable line.

**Create form fields:**
- name, validated as `[A-Za-z0-9._-]+`;
- parent, one of the roots or a typed path, validated as absolute or
  starting with `~`;
- template, the grouped picker;
- providers, shown only for generators;
- `git init`, default on;
- "Allow automatic activation", default off;
- a note: "Pins itself on first `devenv shell`; needs network once".

### 4. Home Manager module and binds

`homeManagerModules.default` follows the shape of microvm's `flake.nix:55`.
It has one option, `programs.nixarchy-devenv.keybinding`: a chord matching
`[A-Z0-9_ +]+`, or null, with default `"SUPER + ALT + E"`. The module writes
`~/.config/hypr/devenv-binds.lua` from the shipped file. The bind's
description is "Dev environments", which is what Super+K lists.

`share/omarchy-menu.jsonc` has an `apps.devenv` row for non-nixarchy users.
nixarchy puts it in its menu defaults in #802.

### 5. Pages

The `docs/` site is copied from nixarchy-microvm: `_layouts/home.html`,
`manual.html`, `_includes/logo.html`, `assets/style.css`, `manual.js` and
`capture.sh`. `_config.yml` sets `baseurl: /nixarchy-devenv` and the `nav`.
The pages are `index.md` (the showcase: hero video, feature grid, template
gallery by group, install) and `usage.md` (the manual). The captures are real,
of `demo-*` projects under a `mktemp -d` root that `capture.sh --setup`
creates. `docs/img` stays under 8 MB, and a check enforces it.

## Alternatives rejected

- **The plugin reads the filesystem and allow file directly from QML.**
  Rejected: the removal checks must live in the executor (Codex finding 2),
  and one CLI keeps the logic testable and usable from a terminal.
- **The allow list as the main source.** Rejected: 0 of 80 entries exist on
  p620, and it only records consent, not projects.
- **Showing process state for every row.** Rejected: it would take one
  `devenv processes list` per row on every poll, and anything less honest
  than a real fetch is a guess.
- **Cloud templates via `nix flake init -t`.** Rejected: that path gives
  a single provider only, and misses the multi-provider merge that `init.sh`
  does.
- **Evaluating personal templates to list them.** Rejected: it would run
  user Nix just to draw a list.
- **Bundling devenv with the plugin.** Rejected: that is the closure the
  service is opt-in to avoid.

## Risks

- **New preset option names are wrong**, and the scaffold fails on first
  shell. Mitigation: `templates-check` scaffolds and runs `devenv info` for
  every preset on p620 before release. The runner needs network and is not
  in `nix flake check`.
- **The cloud generator changes its CLI upstream.** It is pinned by `rev`,
  and `templates-check` runs it for one provider.
- **Removal kills data.** The mitigation is the whole of design section 1
  "Removal": filesystem tests in a temp directory for every refusal and every
  tier, including a symlinked DIR, `$HOME`, a root, a root's parent, a DIR
  that changed device, running processes, and `.devenv/state` surviving the
  `files` tier.
- **`devenv processes list` is slow or hangs**, for example on a project that
  has never been evaluated. It runs with a 10 s timeout, and the result is
  `unknown`, which blocks removal.
- **Moving `nixarchy dev init` changes its default** (no automatic allow).
  This is visible to existing users, and #802 documents it in the manual and
  release notes.
- **Hosts.** p620 is the dev and capture host. razer follows in #802. There is
  no NixOS change in this repo.

## Verification

- `node tests/run.js`: Model tests pass, including a hostile-input row for
  every form field and argv builder.
- `nix flake check` and `nix flake check --all-systems --no-build`: the
  sibling checks, plus `tests/cli.sh`, which exercises discovery, JSON shape
  and the removal refusals and tiers in a sandbox tmpdir, with a stub
  `devenv` on PATH.
- `nix run .#templates-check` (network): every preset and the cloud
  generator (aws) scaffold, and `devenv info` succeeds. `HOME`, `XDG_*` and
  `DEVENV_*` are isolated, and a checksum of the real `allowed` file is
  unchanged afterwards.
- `omarchy plugin validate` on a fresh clone passes. The fresh clone, with
  no CLI on PATH, opens and shows the install line.
- Live on p620, following AGENTS.md "Verifying live":
  - create a `t1` python project and a `t2` cloud(aws) project under a temp
    root;
  - enter, edit, up/down on a project with `processes.*`, and update;
  - allow/revoke, and remove each tier;
  - `hyprctl layers -j` shows `nixarchy-devenv-menu`, and Super+Alt+E opens
    it;
  - `qs log` is clean.
- Pages: the site builds on GitHub Pages at olafkfreund.github.io/nixarchy-devenv
  with real captures, and `docs/img` is under 8 MB.
