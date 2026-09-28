---
title: The manual
layout: manual
permalink: /usage/
---

# Using nixarchy.devenv

This page covers everything the plugin does and how to set it up. For what
it is and why, see the [home page]({{ '/' | relative_url }}).

## What it is

A devenv project is a folder with a `devenv.nix`: a per-project environment of
languages, tools, services and processes, pinned by a `devenv.lock`. This
plugin puts every such folder on your machine in one list, on the bar and
behind **Super+Alt+E**, and does what you would otherwise type:

| You press | It runs |
| --- | --- |
| <kbd>enter</kbd> | `devenv shell`, in a new terminal, in the project |
| <kbd>e</kbd> | your editor on `devenv.nix` |
| <kbd>s</kbd> | `devenv up -d`, or `devenv processes down` |
| <kbd>g</kbd> | `devenv update` |
| <kbd>a</kbd> | `devenv allow`, or `devenv revoke` |
| <kbd>x</kbd> | revoke, or remove, in four steps |
| <kbd>c</kbd> | a new project from a template |

## Requirements

- **devenv.** On nixarchy: `nixarchy-service-enable devenv && nixarchy apply`,
  which also adds the shell hook and the devenv binary cache. Elsewhere, see
  <https://devenv.sh/getting-started/>. Without devenv the list still shows,
  and the panel says what is off.
- **The `nixarchy-devenv` command.** It comes with the plugin on nixarchy and
  in the flake. A plugin added with `omarchy plugin add` does not have it, and
  the panel tells you so.
- **nix with flakes**, only for the cloud templates.
- **git**, for "git init" in the form.
- **`wl-copy`**, for copying a path.

## Install on NixOS (nixarchy)

On nixarchy the plugin comes on by default, with its key and its row in the
Omarchy menu, and nixarchy's manual shows the one line that turns it off
([olafkfreund/nixarchy#802](https://github.com/olafkfreund/nixarchy/issues/802)).

On any other NixOS or Home Manager setup, add the flake:

```nix
inputs.nixarchy-devenv.url = "github:olafkfreund/nixarchy-devenv";
```

and use its three outputs:

- `packages.<system>.cli` is the `nixarchy-devenv` command. Put it in
  `environment.systemPackages` or `home.packages`.
- `packages.<system>.plugin` is the plugin folder. On nixarchy it goes in
  `programs.nixarchy.plugins.devenv.src`. Enable it once with
  `omarchy plugin enable nixarchy.devenv`.
- `homeManagerModules.default` writes the key. `programs.nixarchy-devenv.keybinding`
  takes a chord in Omarchy's `o.bind` syntax (default `SUPER + ALT + E`), or
  `null` for no key.

`~/.config/hypr/bindings.lua` loads the key file with:

```lua
pcall(require, "hypr.devenv-binds")
```

Use `pcall` rather than a bare `require`: `bindings.lua` is yours and outlives
the file, and a missing module in a bare `require` takes the whole config down.

## Install without Nix

```console
$ omarchy plugin add https://github.com/olafkfreund/nixarchy-devenv
$ omarchy plugin enable nixarchy.devenv
```

Then install the command some other way, for example
`nix profile install github:olafkfreund/nixarchy-devenv#cli`, and copy
`devenv-binds.lua` from `~/.config/omarchy/plugins/nixarchy.devenv/` to
`~/.config/hypr/`.

## The bar popup

Add the **Dev environments** widget to the bar from Setup > Plugins. Its glyph
is the Nix snowflake. It is dim when there is nothing to list and lit while a
job runs. A click opens the popup under it, and a middle-click refreshes.

Each row is one project:

- a filled dot if it is allowed to activate on `cd`, a hollow one if not;
- its name;
- its folder, its template (or `custom`), and "no lockfile yet" until its
  first `devenv shell`;
- for the row under the cursor, whether its processes are running. That is
  fetched when the cursor lands on the row, and never guessed.

The buttons on each row are the same actions as the keys.

## The full-screen menu

**Super+Alt+E**, or `omarchy-shell shell toggle nixarchy.devenv '{}'`. It shows
the same list, form and log as the popup, drawn larger, over whatever you were
doing. `{"create":true}` opens straight into the form, and
`{"path":"/home/me/Source/app"}` opens with the cursor on that project.

### Add it to the Omarchy menu

On nixarchy it is already under Apps. Elsewhere, paste the row from
`share/omarchy-menu.jsonc` into
`~/.config/omarchy/extensions/omarchy-menu.jsonc`.

### Keys

| Keys | |
| --- | --- |
| <kbd>j</kbd> <kbd>k</kbd> <kbd>↑</kbd> <kbd>↓</kbd> | move; up from the first row goes to the filter |
| <kbd>/</kbd> | filter by name, folder or template |
| <kbd>enter</kbd> | enter: `devenv shell` in a terminal |
| <kbd>e</kbd> | edit `devenv.nix` (not for bound environments) |
| <kbd>s</kbd> | start or stop processes |
| <kbd>p</kbd> | check the processes again |
| <kbd>g</kbd> | update the lock |
| <kbd>a</kbd> | allow or revoke |
| <kbd>x</kbd> | remove |
| <kbd>y</kbd> | copy the path |
| <kbd>c</kbd> | new project |
| <kbd>G</kbd> | `devenv gc`, for every project |
| <kbd>o</kbd> | the log of the last create or update |
| <kbd>u</kbd> | refresh |
| <kbd>?</kbd> | all of this, inside the panel |
| <kbd>esc</kbd> | leave the filter, then close |

## Everyday tasks

### Start a new project

Press <kbd>c</kbd>. Give it a name, and pick where it goes (the first project
root by default). Choose a template: <kbd>space</kbd> opens the list, and
typing filters it. The note under the template says what you get. Then press
<kbd>enter</kbd>. The log streams into the panel, and the project appears in
the list.

- **git init** is on unless you turn it off, and it does nothing inside an
  existing repository. The cloud template always runs it, so the switch is
  greyed out there.
- **Allow automatic activation** is off by default. Turn it on and the
  environment activates when you `cd` in. Leave it off and you use
  <kbd>enter</kbd> or `devenv shell`.
- **The first `devenv shell`** in a new project fetches its inputs. It needs
  the network once, takes a while, and writes `devenv.lock`. Commit
  `devenv.nix`, `devenv.yaml` and `devenv.lock`: the lock is what makes the
  project reproducible.

### Android

The Android template gives the Android SDK (platform and build tools, `adb`)
and a JDK. The SDK is unfree, and a project's nixpkgs is configured by its own
`devenv.yaml`, not by your system, so the template adds this to it:

```yaml
nixpkgs:
  allow_unfree: true
```

The note under the template says so before you create anything. The first
`devenv shell` downloads about 2 GB: the SDK is 1.8 GB (platforms 32, 34 and
36, build tools 34.0.0), and the whole environment with its JDK is 2.9 GB
(measured with devenv 2.3.1). The emulator, system images and NDK are off,
because each adds more. `emulator` is still on your PATH: it is the legacy
launcher from the old SDK Tools package, which devenv always installs, and
without the emulator itself it only reports that it cannot start. Turn them on
in `devenv.nix`:

```nix
android = {
  enable = true;
  emulator.enable = true;
  systemImages.enable = true;
};
```

It is offered on x86_64 only.

### Language presets and secrets

The Rust, Python, Go and C++ presets use devenv's language modules. Python
enables uv and a virtualenv but does not run `uv sync` until the project has a
dependency manifest. C++ supplies the compiler and language server; choose
CMake, Meson or another build system for the project.

The **Frontend web** and **Backend web** presets provide a small Node,
TypeScript, Prettier and ESLint baseline. They intentionally do not choose a
framework: add Vite, Next, Astro or Svelte for browser work, or Express,
Fastify, Nest or another service framework for backend work. The `format` and
`lint` commands are available inside `devenv shell` once source files exist.

Every built-in preset creates an agenix-compatible `secrets.nix` and an
encrypted-only `secrets/` directory. Cloud generators provide the same files
through their external generator contract. From `devenv shell`:

```console
$ printf %s "$TOKEN" | secret-add API_TOKEN
$ secret-edit API_TOKEN
$ secret-delete API_TOKEN
$ secret-list
$ secret-run --only API_TOKEN -- terraform plan
$ secret-user-add 'ssh-ed25519 AAAA… teammate' teammate
$ secret-rekey
```

Add recipients to `secrets.nix` before storing the first secret. Commit
`secrets.nix` and `secrets/*.age`; never commit plaintext values or pass them
through shell history, logs, Terraform files or process arguments.

The policy is agenix for repository files and runtime-only command injection. A
future template may declare SOPS or devenv SecretSpec when it has a concrete
provider-backed environment contract; no template creates an empty provider
configuration just to claim SecretSpec support.

### AI projects

Choose **Local AI** for a Python/uv project with Ollama, llama.cpp, `nvtop`,
PCI and OpenCL diagnostics. It provides clients and diagnostics only: it does
not enable a service, download model weights, or configure NixOS GPU drivers.
Install Python model libraries in the project with uv, and do machine-level GPU
setup separately.

Choose **AI providers** for hosted API work. It provides Python/uv, `curl` and
`jq`; add only the SDKs the project uses, for example `uv add openai` or
`uv add anthropic google-genai`. Keep API keys in the generated agenix secret
files and expose them only for the command that needs them:

```console
$ printf %s "$OPENAI_API_KEY" | secret-add OPENAI_API_KEY
$ secret-run --only OPENAI_API_KEY -- python your_client.py
```

Neither template creates credentials, provider configuration, automatic
activation, or a hosted/local model service.

### Omarchy and NixOS projects

**Omarchy plugin** creates a small bar-widget starter with `manifest.json`, a
`BarWidget.qml` entry point, JavaScript tests, a Lua binding example, and
`scripts/validate`. Run that validator for the manifest and Node checks. With
Omarchy installed, also run `omarchy plugin validate .` and test the plugin in
the live shell; those checks cannot run hermetically in a generic devenv.
Replace the placeholder plugin ID, author, description, and implementation
before publishing.

From a terminal, the equivalent command is:

```console
$ nixarchy-devenv new --parent ~/Source --name my-plugin omarchy-plugin
```

**NixOS configuration** creates a flake with an example host under
`hosts/example/`, a `modules/` starting point, agenix wired as a flake input,
and `scripts/validate`. The example is marked `boot.isContainer = true` so it
can evaluate without pretending to know your disk or hardware. Before using it
on a machine, replace the host identity, system, state version, hardware
configuration, users, and modules. Review the result, then explicitly apply it
with your normal command, such as:

```console
$ sudo nixos-rebuild switch --flake .#example
```

Create one from a terminal with:

```console
$ nixarchy-devenv new --parent ~/Source --name nixos-config nixos-config
```

Neither starter copies this machine's hardware, users, credentials, or private
keys. Both include the shared agenix-compatible devenv helpers for adding,
editing, deleting, and rekeying encrypted project secrets.

### Cloud projects

Choose **AWS infrastructure**, **Google Cloud infrastructure**, or **Azure
infrastructure** for a focused provider project. Each runs the pinned
[cloud-projects-templates](https://github.com/olafkfreund/cloud-projects-templates)
generator and includes the provider CLI, Terraform, Kubernetes tooling, lint
and security tools, `AGENTS.md`, agent skills, MCP servers, and agenix-encrypted
secrets. **Cloud project** remains available when you want to combine providers:
AWS, Azure, GCP, OCI, Kubernetes, Cloudflare, Hetzner or DigitalOcean.

Inside the generated devenv:

- `secret-add NAME` and `secret-edit NAME` encrypt values without putting them
  in shell history;
- `secret-delete NAME` removes one encrypted secret after exact-name checks;
- `secret-user-add 'ssh-ed25519 …' LABEL` adds a teammate and rekeys the
  encrypted secrets;
- `secret-run --only NAME -- command` exposes a secret only to that command.

Some MCP servers need cloud credentials; give them read-only ones. The
project's own `AGENTS.md` says how to log in. Removing a recipient does not
erase access to old Git revisions, so rotate any compromised provider secret.

### Your own templates

A folder in `~/.config/nixarchy-devenv/templates/<id>/`, where `<id>` is
lower-case letters, digits and `-`, containing:

- `template.json`: `{"version": 1, "label": "My stack", "note": "What you get"}`
- `devenv.nix`: copied as it is
- `devenv.yaml`: optional

It appears under **Yours**. It is read, never evaluated, until you create a
project from it. An id that clashes with a built-in template is skipped, with a
warning from `nixarchy-devenv templates --json`.

### Processes and services

A project with `processes.*` or `services.*` in its `devenv.nix` gets a start
button. <kbd>s</kbd> runs `devenv up -d`, which returns once the process
manager is up; the processes keep running. <kbd>s</kbd> again stops them. Stop
works even while another job holds the panel.

### Updating

<kbd>g</kbd> runs `devenv update` and shows its log. One job runs at a time,
across the bar and the menu. <kbd>o</kbd> brings the log back after you close
the panel.

### Removing

<kbd>x</kbd> offers four choices. The cursor starts on the first:

1. **Revoke.** It stops activating on `cd`. Nothing is deleted.
2. **Remove devenv files.** `devenv.nix`, `devenv.yaml`, `devenv.lock` and
   `.devenv` go, but `.devenv/state` stays: that is where a service such as
   PostgreSQL keeps its data. Your code stays.
3. **Remove files and state.** The same, and `.devenv/state` too.
4. **Delete the folder.** The whole project, code included. Type its name to
   confirm.

The last three are refused while its processes run, or while that cannot be
told, and the reason is shown. The command that does the deleting checks
everything again right before it acts. It refuses:

- a path that is not canonical;
- `/` and your home directory;
- a project root, or anything that contains one;
- a folder without its own `devenv.nix`;
- a folder that is not the one that was listed. It is matched by device and
  inode, so a different project moved to that path since the list was drawn
  is refused, not deleted;
- a removal that arrives with no project root to check against, or with one
  that cannot be resolved -- a root on a drive that is not mounted, say.

The list is checked twice: once when the command starts, and again as the
last thing before it deletes. Asking devenv whether processes are running,
and revoking the directory, take seconds; the second check is what makes
those seconds safe.

`.envrc` is never removed.

### Bound environments

`devenv --from <source> allow` binds a directory to a configuration that lives
somewhere else, such as a flake on GitHub. The directory has a working
environment but no `devenv.nix` of its own. The list shows it with
**from &lt;source&gt;** where a template would be, and its saved profiles if it
has any. It reads the source as text and never fetches it.

- <kbd>enter</kbd>, <kbd>s</kbd>, <kbd>g</kbd> and <kbd>p</kbd> work as usual.
  <kbd>s</kbd> offers Start even though the plugin cannot tell whether the
  source defines processes; if it defines none, `devenv up` says so in the log.
- <kbd>e</kbd> does nothing: there is no `devenv.nix` here to edit.
- <kbd>x</kbd> offers **Revoke** only. It forgets the binding, its source and
  its saved profiles, all of which devenv keeps in one entry. Nothing is
  deleted, and the row then leaves the list.
- A `devenv.nix` in the directory, or in any folder above it, wins over the
  binding, as it does in devenv. Such a directory is listed as an ordinary
  project, or as part of the one above it.

### devenv gc

<kbd>G</kbd> asks, then runs `devenv gc`. It deletes old devenv shell
generations **for your user, across every project**, not only the selected
one. Cancel is the default answer.

## Settings

| Setting | Default | |
| --- | --- | --- |
| Project roots | `~/Source:~/Projects` | Folders to search, separated by `:` like `PATH`. New projects go in the first. A root that is a symlink is followed; nothing below it is. |
| Refresh interval | 60 s | The bar's re-read. An open panel refreshes every 5 s. |
| Editor | empty | What <kbd>e</kbd> opens, in a terminal. Empty means `$EDITOR`, then `nvim`. Plain words only, such as `hx` or `nvim -p`. |
| Hide the bar icon when empty | off | |

## Troubleshooting

**"The nixarchy-devenv command is not installed".** The plugin was added
without Nix. Install the command (see [Install without Nix](#install-without-nix)).

**"devenv is not installed, so create, enter and processes are off".** Turn it
on (see [Requirements](#requirements)), then reopen the panel.

**A project is missing from the list.** It has to be at most three levels
below a project root, or allowed with `devenv allow`. Folders named `.git`,
`node_modules`, `.devenv` and `.direnv` are not searched. Symlinks inside a
root are not followed. `nixarchy-devenv list --json --root <dir>` shows what
the plugin sees, including a `warnings` list.

**Removal says "Could not tell whether its processes are running".** Press
<kbd>p</kbd> and wait for the status line. If devenv cannot answer within 10
seconds, removal stays refused. Stop the processes from a terminal
(`devenv processes down`) and try again.

**A new project's first shell takes long.** It is fetching the inputs that
`devenv.yaml` names. On nixarchy, the devenv service adds devenv.cachix.org, so
most of it is downloaded rather than built.

**Nothing happens on a key.** `qs log -i <instance>` (from `qs list --all`)
shows the shell's log. `omarchy-shell shell call nixarchy.devenv status ''`
prints the plugin's state: dependencies, roots, counts and the last error.

## Removal

To remove the plugin itself: `omarchy plugin disable nixarchy.devenv`, delete
`~/.config/omarchy/plugins/nixarchy.devenv` and
`~/.config/hypr/devenv-binds.lua`, or drop the flake input. Your projects are
ordinary devenv projects and keep working without it. The one extra file they
carry, `.devenv-template`, says which template made them and can be deleted.
