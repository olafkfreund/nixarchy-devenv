# AGENTS.md

Instructions for any AI agent working in this repository: Claude Code, Codex, Copilot,
Gemini or others. `CLAUDE.md` and `.github/copilot-instructions.md` point here. This
file is the single source. When anything disagrees with it, this file wins.

> **Status:** design stage. The files in the Layout table are the target described by
> `intent/`, `spec/` and `plan/`. Nothing is implemented until `plan/` is
> `status: approved`. Keep this file in step with the approved plan.

## What this repository is

`nixarchy.devenv` is an [Omarchy](https://omarchy.org/) shell plugin written in
Quickshell QML. It manages [devenv](https://devenv.sh/) environments through two
surfaces:

- **a bar widget**, whose popup sits under the glyph (`Panel.qml`);
- **a full-screen keyboard menu** (`Menu.qml`), on `SUPER + ALT + E`.

It lists every devenv environment on the machine and can:

- create a new project from a template (language presets, mobile, cloud, or yours);
- enter an environment in a terminal, and edit its `devenv.nix`;
- start and stop its processes;
- update its lock, and run gc;
- allow it, revoke it, or delete it.

Update, create and process output stream into the panel.

The repository also owns the **template catalogue** (`data/templates.nix`) and the
**`nixarchy-devenv` CLI** that the plugin calls. nixarchy's `nixarchy dev …`
dispatches to that CLI. nixarchy keeps only the shell hook and the cache
(`modules/services/devenv.nix` there).

`flake.nix` packages the plugin, the CLI and a Home Manager module for NixOS and
nixarchy. The user guide is [`docs/usage.md`](docs/usage.md). The design is in
`intent/`, `spec/` and `plan/`.

## Layout

| Path | Owns |
| --- | --- |
| `Model.js` | All logic: parsing CLI JSON, rows, validation, and every command's argv. Pure `.pragma library` with no QML, tested under Node. |
| `qmldir` | Declares `DevenvState` a singleton, so the bar and the menu share one instance. |
| `DevenvState.qml` | Data, polling, the operation lock, the stream log, and every `Process`. |
| `DevenvView.qml` | Interaction: modes (list / form / log), cursor, filter, confirmations, keys. Shared by both surfaces. |
| `EnvList.qml`, `CreateForm.qml`, `LogView.qml`, `ShortcutSheet.qml` | Drawing pieces used by the view. |
| `Panel.qml` | The bar widget host: glyph, `KeyboardPanel` popup, and IPC target `nixarchy.devenv.bar`. |
| `Menu.qml` | The full-screen menu host (manifest kind `menu`). |
| `manifest.json` | Plugin id `nixarchy.devenv`, kinds `menu` + `bar-widget`, `keepLoaded: true`, settings schema. |
| `data/templates.nix` | The template catalogue: `preset` entries (devenv option lines) and `flake` entries (template sources such as cloud-projects-templates). |
| `pkgs/cli.nix` | The `nixarchy-devenv` CLI (`list --json`, `templates --json`, `init`). It moved here from nixarchy's `pkgs/dev-init.nix`. |
| `devenv-binds.lua` | The key, loaded from `~/.config/hypr/bindings.lua` with `pcall(require, "hypr.devenv-binds")`. |
| `flake.nix` | The package (an explicit `files` list, copied as real files), the CLI, `homeModules.default`, `checks`, and the `templates-check` runner. |
| `share/omarchy-menu.jsonc` | The Omarchy menu row for users who are not on nixarchy. |
| `tests/` | Node tests for `Model.js` (`tests/run.js`). |
| `docs/` | The GitHub Pages site (`docs/index.md`, `docs/usage.md`) and `capture.sh`. |
| `intent/`, `spec/`, `plan/` | Design artifacts for each task. See Workflow. |

## Commands

```bash
node tests/run.js                              # Model tests
nix flake check                                # tests + manifest, entry points, no symlinks, no pacman/yay, no hex colours
nix flake check --all-systems --no-build       # aarch64 evaluates
nix run .#templates-check                      # scaffold every preset with a real devenv and evaluate it (needs network)
nix build                                      # the plugin folder, exactly as nixarchy links it
omarchy plugin validate "$(readlink -f result)"
```

To see the repo the way `omarchy plugin add` would, validate a fresh clone rather than
the working tree. The `result` link that `nix build` leaves behind is a symlink, so
validating `.` fails once you have built:

```bash
d=$(mktemp -d) && git clone -q . "$d/p" && rm -rf "$d/p/.git" && omarchy plugin validate "$d/p"
```

## Verifying live (on a nixarchy desktop)

1. **Install a copy.** A symlinked checkout does not reload on `rescanPlugins`.
   ```bash
   rm -rf ~/.config/omarchy/plugins/nixarchy.devenv
   cp -rL result ~/.config/omarchy/plugins/nixarchy.devenv
   chmod -R u+w ~/.config/omarchy/plugins/nixarchy.devenv
   ```
   Then enable it once: `omarchy plugin enable nixarchy.devenv`.
2. **Restart the shell** with `omarchy-restart-shell`, then wait until
   `omarchy-shell shell ping` answers.
3. **Check the log for errors.** Get the instance from `qs list --all`, then run
   `qs log -i <instance>`.
4. **Open each surface:**
   - the menu: `omarchy-shell shell toggle nixarchy.devenv '{}'`, or
     `'{"create":true}'` to open straight into the form;
   - the popup: `omarchy shell nixarchy.devenv.bar open`.
5. **Confirm what is up** with `hyprctl layers -j`. The menu's namespace is
   `nixarchy-devenv-menu`.
6. **Test environments:** create them under a `mktemp -d` root, name them `t1`,
   `t2` and so on, and delete them from the plugin when done. Never point a
   delete test at a real project.

## Retaking the captures

Real captures only, and never of anything but the plugin, `demo-*` environments
under a throwaway root, and the wallpaper. Follow the procedure in
nixarchy-distrobox's AGENTS.md ("Retaking the captures"), with these changes:

- `docs/capture.sh --setup` creates the `demo-*` projects and adds that root to
  `projectRoots` for the session.
- `--teardown` removes them and restores `shell.json`.
- Check `hyprctl layers -j` for `omarchy-keyboard-panel` or `nixarchy-devenv-menu`
  before every `wtype`.
- `docs/img/` must stay under 8 MB. It ships inside every `omarchy plugin add`
  clone.

## Rules

Each rule records a real failure or a hard constraint. The first group comes from
the sibling plugins (distrobox, microvm, podman):

- **No symlinks anywhere in the repository.** `omarchy plugin add` clones this repo
  *as* the plugin folder, and `omarchy-plugin-validate` refuses any symlink inside
  it. That is why `CLAUDE.md` imports `AGENTS.md` instead of linking to it.
- **No hardcoded colours.** Use `Color.*`, `Style.*` and `Border.*` tokens, so themes
  switch cleanly. `nix flake check` fails on `"#rrggbb"`.
- **No `pacman` or `yay`**, not even in comments. nixarchy fails the rebuild on them.
- **A new runtime file goes in the `files` list in `flake.nix`**, or it is not in
  the package.
- **Run external commands by name from `PATH`.** Never wrap or bundle them. A
  missing command fails silently inside a QML `Process`, so document it as a
  requirement. `devenv` especially: it bundles its own Nix, and a machine that
  never asked for it must not get that closure through this plugin.
- **Argv arrays only, never `sh -c`.** Every command is built in `Model.js` as an
  array, and returns `null` on invalid input.
- **One mutation at a time, via the singleton.** Create, update, up/down, gc, allow,
  revoke and delete are refused while another mutation runs, from either surface.
  Listing never locks.
- **Lists read through a QObject `var` property are Qt sequence wrappers, not JS
  arrays.** Check `length`, not `Array.isArray`.
- **The surfaces are keep-loaded.** `open()` resets the view and then focuses
  whatever belongs to the *final* mode, via `Qt.callLater`. It never touches the
  stream or the log.
- **Nothing polls while every surface is closed.** The bar's slow poll for the
  glyph is the only exception.
- **Logic goes in `Model.js`, with a Node test.** Keep QML to drawing and wiring.
- **A user-visible change updates `docs/usage.md` and the README in the same PR.**

These rules are specific to devenv:

- **A preset is exactly a set of devenv option lines.** No nixarchy vocabulary, no
  `let`, no imports, and no `packages =`: `devenv init` already writes
  `packages`, and a second one is
  `error: attribute 'packages' already defined`. Take option names from devenv's
  `src/modules`, not from memory. `templates-check` must pass for every preset
  before release. It is not pure, so `nix flake check` cannot run it for you.
- **The plugin never evaluates Nix to draw.** Templates come from the JSON index
  built into the package. The environment list comes from `nixarchy-devenv list
  --json`, which reads devenv's `allowed` file and the configured roots. It does
  not run devenv.
- **Consent stays with the user.** `devenv allow` runs only from the create form's
  allow toggle or the explicit allow action. Never pre-seed it, and never allow a
  directory as a side effect.
- **Delete is two-tier and bounded.** The default removes only devenv's files
  (`devenv.nix`, `devenv.yaml`, `devenv.lock`, `.devenv/`, `.envrc` when devenv
  wrote it) and revokes the allow. Removing the folder needs the name typed. Every
  delete path is checked in `Model.js` to be a listed environment, not `$HOME`,
  `/`, or a project root. Each of those refusals has a Node test.
- **Create never overwrites.** It refuses an existing `devenv.nix`, as
  `nixarchy dev init` does today, and prints the preset lines for pasting by hand.
- **Form fields are allowlisted.** Project names and parent paths are validated in
  `Model.validateForm`. Any new field needs its own rule and a hostile-input test
  row.

## Workflow

Any task that is tracked as an issue, or that touches more than one file, goes
through three artifacts named with the slug `YYYY-MM-DD-<issue>-<slug>`. Typos,
lock bumps and one-line config changes are exempt.

1. `intent/<slug>.md` (why), committed as `status: draft`. Stop for the owner's
   review.
2. After approval, `spec/<slug>.md` (what). Stop.
3. After approval, `plan/<slug>.md` (how, self-contained). Stop.
4. Implement only once the plan is `status: approved`.

- Never approve an artifact yourself.
- Record each approval as its own commit, for example
  `docs(plan): approve <slug> (#N)`.
- Make one commit per plan step, and cite the step.
- If the work deviates from the plan, update `plan/` in the same commit as the
  code.
- The PR links all three artifacts and closes the issue. Review compares the diff
  to `plan/`.

Branches are named `feat|fix|docs/<issue>-<slug>`. Commit subjects use Conventional
Commits (`feat:`, `fix:`, `docs:`, `build:`, `ci:`, `refactor:`), each with the
issue number.

## Known follow-ups

- nixarchy integration, default-on (olafkfreund/nixarchy#802). This has its own
  intent, spec and plan in that repo.
- Rich project templates (AGENTS.md, skills, MCP) for non-cloud stacks, in the style
  of cloud-projects-templates.
