---
status: approved
issue: 1
author: olafkfreund
---

# Intent: Keyboard-driven devenv plugin for Omarchy that replaces nixarchy's built-in devenv handling

## Problem

On nixarchy, devenv is a command-line feature spread across three places, and
none of them is something you can see or drive from the desktop:

- `modules/services/devenv.nix` is an opt-in service. It adds the
  `devenv hook` to bash, zsh and fish, and the devenv.cachix.org cache.
- `nixarchy dev init <preset>` (`pkgs/dev-init.nix`) scaffolds a project from
  8 language presets in `data/devenv-presets.nix`: react, node,
  typescript, python, ml, jupyter, go and rust.
- Neovim gets `:DevenvShell` (`modules/home.nix`).

That leaves these gaps next to nixarchy-distrobox and nixarchy-microvm:

- **Nothing lists your environments.** devenv records every directory you
  allowed, in `$XDG_DATA_HOME/devenv/allowed`, but that file is not a usable
  list. On p620 it has 80 entries and **none of them still exists**. They look
  like `vmtest/tmp/tmp.*/go`, one per preset name, which points at nixarchy's
  own `devenv-presets` runner writing into the real trust database: it
  isolates `HOME` but inherits `XDG_DATA_HOME` (`flake.nix:918`). Nothing shows
  which projects are real, which have a lockfile, or which are running
  processes.
- **Managing an environment is manual.** Entering, editing, updating, starting
  processes (`devenv up`), garbage-collecting, revoking an allow and deleting
  are all terminal commands you have to remember, one project at a time.
- **The templates are split and incomplete.** Language presets live inside
  nixarchy, so every new template needs a nixarchy release. Cloud templates
  live in a separate repo, `olafkfreund/cloud-projects-templates`: AWS,
  Azure, GCP, OCI, Kubernetes, Cloudflare, Hetzner and DigitalOcean, used
  through `nix run … -- aws azure`. Nothing presents the two sets together.
  There is **no** Java, Kotlin, Android, Flutter, .NET, PHP or Ruby template
  anywhere.
- **devenv is off by default.** A new nixarchy user has no path from "I want
  a Java project" to a working environment without reading the manual.

## Proposed outcome

- **A new Omarchy plugin, `nixarchy.devenv`.** It is the same shape and feel
  as nixarchy-distrobox and nixarchy-microvm: a bar widget with a keyboard
  popup, and a full-screen menu on **Super+Alt+E**. It is reachable from the
  Omarchy menu under Apps.
- **It lists the devenv environments it can find.** It scans configurable
  project roots and adds devenv's allow list as a hint. Missing entries are
  hidden, not deleted from devenv's database. Each row shows its template
  ("custom" when unknown), whether it is allowed for automatic activation,
  whether a lockfile is present, and its process state ("unknown" when
  that cannot be verified).
- **From the list, with one key each:**
  - enter the environment in a terminal;
  - edit `devenv.nix`;
  - start processes detached, and stop them, with stop always available;
  - update the lock, with output streamed into the panel;
  - allow or revoke automatic activation;
  - copy the path;
  - remove the environment. The ordinary action is revoke. Removing devenv's
    files is a separate, confirmed action that preserves `.devenv/state`
    (databases live there). Destroying state, or the whole folder, is a third
    action with its own consent.
- **A user-wide `devenv gc`**, labelled as user-wide. It is not presented as
  a per-project action, because devenv's gc has no project scope.
- **A create form.** It asks for a name, a parent directory and a template
  from one grouped picker (Languages, Mobile, Cloud, Yours), plus whether to
  run `git init` and whether to allow automatic activation. The result is a
  scaffold that pins itself on its first activation. The form says so,
  including that the first activation needs the network.
- **The template catalogue lives in this repo.**
  - The existing 8 presets move here.
  - New presets are added: Java (Gradle and Maven), Kotlin, Flutter and Dart,
    .NET, PHP and Ruby. Android needs `devenv.yaml` changes (unfree SDK), so
    it is either a template with a YAML capability or a follow-up task (see
    Open questions).
  - `cloud-projects-templates` is offered as a *generator* entry, not a plain
    flake template. You can pick several providers at once. The form shows
    which of its toggles the generator cannot honour; for example, it always
    runs `git init`.
  - Personal templates come from `~/.config/nixarchy-devenv/templates/`.
  - A `nixarchy-devenv` CLI does the work (`list`, `templates`, `init`). The
    plugin calls it, and it is usable on its own.
- **nixarchy ships it on by default** (tracked in olafkfreund/nixarchy#802).
  - It is installed, and enabled once, with the key and the menu row.
  - `nixarchy dev …` keeps working and dispatches to the new CLI, keeping
    today's preset names, help and exit codes.
  - Neovim's `:DevenvShell` stays.
  - nixarchy's own dev-init, presets and preset runner are removed, so
    there is one owner.
  - A user can turn it off with one line.
- **A GitHub Pages showcase at olafkfreund.github.io/nixarchy-devenv.** It
  is built like the nixarchy and nixarchy-microvm sites and uses real
  captures.

## Affected users and systems

- nixarchy desktop users on p620, razer and anything else that imports
  `nixosModules.nixarchy`. They gain a default-on plugin and key, and the
  `nixarchy dev init` presets change owner.
- The nixarchy repo: `modules/services/devenv.nix`, `modules/apps.nix` (the
  `nixarchy dev` dispatch), `modules/home.nix` (plugins, keybinding, menu),
  `pkgs/dev-init.nix`, `data/devenv-presets.nix`, the `devenv-presets` runner
  in `flake.nix`, and `docs/manual/per-project-environments.md`.
- cloud-projects-templates, which becomes a consumer-facing template source.
  It is read only: nothing in that repo changes for this task.
- Existing devenv projects. The plugin reads them and deletes nothing
  unless you ask it to.

## Constraints

- **Must follow the sibling plugin rules** (see AGENTS.md):
  - no symlinks in the repo;
  - `Color.*` tokens only;
  - no pacman or yay;
  - argv arrays only, never `sh -c`;
  - all logic in `Model.js`, with Node tests;
  - one mutation at a time through a singleton;
  - keep-loaded surfaces that do not poll while closed;
  - an explicit `files` list in `flake.nix`;
  - must pass `omarchy plugin validate` on a fresh clone.
- **Presets stay pure devenv option lines**, under the bar that
  `data/devenv-presets.nix` documents today:
  - no nixarchy vocabulary and no custom Nix;
  - no `packages =`, because `devenv init` already sets it;
  - every preset is scaffolded and evaluated by a runner before release.
- **The plugin never evaluates Nix at runtime.** It reads a template index
  built into the package, and runs devenv and nix only when you ask for an
  action.
- **devenv's consent model stays interactive.** `devenv allow` runs only
  because the user asked for it: through the create form's "Allow automatic
  activation" toggle or an explicit allow action. The migrated initializer
  loses today's unconditional `devenv allow` (`pkgs/dev-init.nix:152`), and
  an existing allow or profile choice is never rewritten.
- **Destruction is bounded where it runs, not only in the UI.** The CLI
  re-checks the target before it deletes anything: canonical path, no
  symlink escape, not `$HOME`, `/` or a project root or its ancestor, and
  unchanged since it was confirmed. The confirmation names the full path. It
  refuses while processes are running or their state is unknown.
  `.devenv/state` and project source are never removed without their own
  consent.
- **The template runner is hermetic.** It isolates `HOME`, `XDG_*` and
  `DEVENV_*`, and it verifies the real allow list is unchanged afterwards.
- **Both install paths work.** The Nix path supplies the plugin, the CLI and
  the catalogue together. `omarchy plugin add` clones without building, so
  the plugin detects a missing CLI or devenv and says what to install instead
  of failing silently.
- **nixarchy's side is its own intent, spec and plan** in the nixarchy repo
  (#802). It starts after this spec is approved. This task changes nothing in
  nixarchy.
- **devenv comes from PATH**, using the user's or the service's package. It
  is never bundled, so it does not add its closure to machines that never
  asked for it.

## Open questions

1. **Should "on by default" also turn on `services.devenv`?** That service
   adds the shell hook, the cache and devenv's own Nix, which is why it is
   opt-in today. Codex recommends default-on UI only: the UI detects a
   missing devenv and offers the one-line enable, and the closure is measured
   before deciding more. Without devenv the plugin can list environments but
   cannot create or enter one.
2. **Project roots to scan.** The proposed default is `~/Source` and
   `~/Projects`, up to depth 3, without following symlinks. It is a setting
   either way.
3. **Enter = explicit `devenv shell` in a new terminal?** This is
   recommended because it works without the hook. The alternative is `cd`
   plus the hook.
4. **Android: in this task, or split out?** It needs a YAML capability
   (`nixpkgs.allowUnfree` in `devenv.yaml`) plus decisions on the SDK
   licence, emulator and architecture.
5. **Split into several tasks?** Codex suggests separate issues for:
   - CLI, catalogue and discovery;
   - the UI;
   - destructive removal;
   - mobile and cloud-generator templates;
   - nixarchy integration (#802);
   - Pages and captures, after the behaviour settles.
   The alternative is one task with phased plan steps.
6. **Fix the leaking runner in nixarchy now?** The `devenv-presets` runner
   writing into the real allow list is an existing bug. It could be a small
   fix in nixarchy today (its own issue), independent of this move.
7. **Directories bound with `--from` (devenv 2.2+)**, which have no local
   `devenv.nix`. Should they be listed, or explicitly out of scope for v1?
