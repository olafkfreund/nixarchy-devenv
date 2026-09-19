# nixarchy.devenv

[devenv](https://devenv.sh) environments in the [Omarchy](https://omarchy.org)
shell: a bar widget and a full-screen keyboard menu on **Super+Alt+E** that list
every devenv project under your project roots. You can enter one, edit it,
start and stop its processes, update its lock, allow or revoke it, and remove
it. You can also create a new project from templates for languages, mobile and
cloud.

Built for [nixarchy](https://olafkfreund.github.io/nixarchy/), and it works on
any Omarchy with devenv installed.
**Manual and screenshots:** <https://olafkfreund.github.io/nixarchy-devenv/>

## What it does

- **Lists your environments.** It finds every `devenv.nix` under your project
  roots (three levels deep, without following symlinks inside a root), plus
  anything you have `devenv allow`ed elsewhere. Allowed projects come first,
  then the most recently edited.
- **Enter** opens `devenv shell` in a new terminal, in the project.
  **e** opens `devenv.nix` in your editor.
- **s** starts the project's processes (`devenv up -d`) or stops them. Stop is
  never locked out, even while an update runs somewhere else.
- **g** runs `devenv update`, streaming the log into the panel.
- **a** allows or revokes automatic activation on `cd`.
- **x** removes a project in four steps, least destructive first:
  1. revoke (nothing deleted);
  2. devenv's files (keeps `.devenv/state` and your code);
  3. files and state;
  4. the whole folder (you type its name).
- **c** creates a new project from a template:

  | Group | Templates |
  | --- | --- |
  | Languages | Node.js, React, TypeScript, Python, Go, Rust, Java (Gradle), Java (Maven), Kotlin, .NET, PHP, Ruby |
  | Data & ML | Machine learning (uv, CUDA/ROCm), Jupyter |
  | Mobile | Flutter |
  | Cloud | [cloud-projects-templates](https://github.com/olafkfreund/cloud-projects-templates): AWS, Azure, GCP, OCI, Kubernetes, Cloudflare, Hetzner, DigitalOcean, one or several |
  | Yours | anything in `~/.config/nixarchy-devenv/templates/` |

The same actions work from a terminal, through the `nixarchy-devenv` command
that the plugin calls:

```console
$ nixarchy-devenv help
$ nixarchy-devenv new --parent ~/Source --name api python
$ nixarchy-devenv init --allow rust          # in the current directory
$ nixarchy-devenv list --json --root ~/Source
```

On nixarchy, `nixarchy dev init <template>` is the same command.

## Install

### NixOS and nixarchy

nixarchy ships this plugin on by default (olafkfreund/nixarchy#802). On any other
Nix setup:

```nix
# flake.nix
inputs.nixarchy-devenv.url = "github:olafkfreund/nixarchy-devenv";

# NixOS or Home Manager: the command
environment.systemPackages = [ inputs.nixarchy-devenv.packages.${system}.cli ];

# nixarchy: the plugin
programs.nixarchy.plugins.devenv.src = inputs.nixarchy-devenv.packages.${system}.plugin;

# Home Manager: the key (writes ~/.config/hypr/devenv-binds.lua)
imports = [ inputs.nixarchy-devenv.homeManagerModules.default ];
programs.nixarchy-devenv.keybinding = "SUPER + ALT + E";   # the default; null for none
```

Then enable the plugin once with `omarchy plugin enable nixarchy.devenv`, and
load the key from `~/.config/hypr/bindings.lua`:

```lua
pcall(require, "hypr.devenv-binds")
```

### Without Nix

```console
$ omarchy plugin add https://github.com/olafkfreund/nixarchy-devenv
$ nix profile install github:olafkfreund/nixarchy-devenv#cli
```

`omarchy plugin add` clones the plugin and builds nothing. The panel tells you
if the `nixarchy-devenv` command is missing. For the key, copy
`devenv-binds.lua` from the plugin folder to `~/.config/hypr/`. For the Omarchy
menu row, paste `share/omarchy-menu.jsonc` into
`~/.config/omarchy/extensions/omarchy-menu.jsonc`.

### Requirements

- **`devenv`** creates, enters and runs environments. On nixarchy it is one
  line: `nixarchy-service-enable devenv && nixarchy apply`. Without it the list
  still works, and the panel says what is off.
- **`nix`** with flakes, for the cloud templates.
- **`git`**, for `git init` in new projects.
- **`wl-copy`**, for copying a path.

## Settings

These are the bar widget's settings (Setup > Plugins, or its entry in the bar
layout):

| Setting | Default | |
| --- | --- | --- |
| `projectRoots` | `~/Source:~/Projects` | Where to look, separated by `:`. New projects go in the first one. |
| `refreshIntervalSec` | `60` | How often the bar re-reads the roots. An open panel refreshes every 5 seconds. |
| `terminalEditor` | `""` | The editor `e` opens, in a terminal. Empty means `$EDITOR`, then `nvim`. |
| `hideWhenEmpty` | `false` | Hide the bar icon while there is nothing to list. |

## Safety

- **Nothing is allowed behind your back.** `devenv allow` runs only from the
  form's "Allow automatic activation" switch or the `a` key. A `devenv.nix` is
  code that runs when you enter it.
- **Removal is checked where it happens.** Right before deleting anything, the
  `nixarchy-devenv remove` command refuses unless all of these hold:
  - the path is canonical;
  - it is not `/`, your home directory, or a project root (or anything
    containing one);
  - it has its own `devenv.nix`;
  - it is on the device it was listed on;
  - its processes are stopped. If that cannot be told, it refuses.

  `.devenv/state`, where a service keeps its database, goes only when you
  pick "files and state". `.envrc` is never removed.
- **No shell anywhere.** Every command is an argument list, and every field and
  path is checked before it reaches one.
- **The template check is hermetic.** `nix run .#templates-check` scaffolds
  every template with a real devenv in a throwaway `HOME`, and fails if your
  own devenv allow list changes.

## Development

See [AGENTS.md](AGENTS.md). In short:

```console
$ node tests/run.js                 # Model.js
$ nix flake check                   # the above, the CLI tests, manifest and repo checks
$ nix run .#templates-check         # every template against a real devenv (network)
```

The design is in `intent/`, `spec/` and `plan/`.

## License

MIT.
