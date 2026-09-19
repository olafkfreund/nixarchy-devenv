---
status: draft
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
  9 language presets in `data/devenv-presets.nix`. The presets are react,
  node, typescript, python, ml, jupyter, go and rust.
- Neovim gets `:DevenvShell` (`modules/home.nix`).

That leaves these gaps next to nixarchy-distrobox and nixarchy-microvm:

- **Nothing lists your environments.** devenv already records every directory
  you allowed, in `~/.local/share/devenv/allowed`. That file has 80 entries on
  p620, and most of them point at temp directories that no longer exist.
  Nothing reads it, and nothing shows which projects are real, locked or
  running processes.
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
- **It lists every devenv environment on the machine.** The list comes from
  devenv's own allow list plus configurable project roots. Stale entries are
  dropped. Each row shows its template, allow state, lock state and whether
  processes are running.
- **From the list, with one key each:**
  - enter the environment in a terminal;
  - edit `devenv.nix`;
  - start and stop processes;
  - update the lock, with output streamed into the panel;
  - gc;
  - allow or revoke;
  - copy the path;
  - delete. By default delete removes only devenv's files. Removing the whole
    folder needs an explicit, typed confirmation.
- **A create form.** It asks for a name, a parent directory and a template
  from one grouped picker (Languages, Mobile, Cloud, Yours), plus whether to
  run `git init` and whether to allow the directory. The result is a working,
  pinned project.
- **The template catalogue lives in this repo.**
  - The existing 9 presets move here.
  - New presets are added: Java (Gradle and Maven), Kotlin, Android, Flutter
    and Dart, .NET, PHP and Ruby.
  - `cloud-projects-templates` is offered as a template source, and you can
    pick several providers at once.
  - Personal templates come from `~/.config/nixarchy-devenv/templates/`.
  - A `nixarchy-devenv` CLI does the work (`list`, `templates`, `init`). The
    plugin calls it, and it is usable on its own.
- **nixarchy ships it on by default** (tracked in olafkfreund/nixarchy#802).
  - It is installed, and enabled once, with the key and the menu row.
  - `nixarchy dev …` keeps working and dispatches to the new CLI.
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
  because the user asked for it: through the create form toggle or an
  explicit allow action. Nothing pre-seeds consent.
- **Delete never removes project source by default.** Deleting the folder
  needs a typed confirmation, and paths outside the listed environment are
  refused.
- **nixarchy's side is its own intent, spec and plan** in the nixarchy repo
  (#802). It starts after this spec is approved. This task changes nothing in
  nixarchy.
- **devenv comes from PATH**, using the user's or the service's package. It
  is never bundled, so it does not add its closure to machines that never
  asked for it.

## Open questions

1. **Should "on by default" also turn on `services.devenv`?** That service
   adds the shell hook and the cache, and it pulls in devenv's own Nix, which
   is why it is opt-in today. Without it the plugin can list environments but
   cannot create or enter one.
2. **Project roots to scan.** The proposed default is `~/Source` and
   `~/Projects`, up to depth 3. It is a setting either way.
3. **Where "enter" lands.** The options are a new terminal in the project
   directory, which activates the hook, or `devenv shell` explicitly. The
   second also works without the hook.
4. **Android.** devenv's `android.*` module pulls in a large SDK. Should the
   preset set only `android.enable` with the defaults, or also pin platform
   and emulator versions?
