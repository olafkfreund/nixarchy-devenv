# The template catalogue: what `nixarchy-devenv init|new <id>` scaffolds and
# what the plugin's create form offers, grouped by `group`.
#
# Moved here from nixarchy's data/devenv-presets.nix (#1). The eight presets
# below the "moved" line are that file's entries verbatim, comments included,
# with only `kind` and `group` added; their history is in the nixarchy repo.
#
# ## Two kinds
#
#   preset     `lines` spliced into the devenv.nix that `devenv init` writes.
#   generator  a pinned flake app run inside the new directory, for templates
#              that are more than option lines (cloud-projects-templates
#              writes AGENTS.md, skills, .mcp.json, secrets.nix).
#
# ## The bar for a preset
#
# `lines` are ordinary devenv option assignments. `pkgs` and `lib` expressions
# are fine (ml and jupyter use them); what is not fine is anything that makes
# the user's project depend on nixarchy or on this repo -- no helper, no
# import of anything we ship. The file is committed, shared with a team, and
# read by people who have never heard of nixarchy.
#
# A preset may not set `packages`: `devenv init` writes `packages = [ pkgs.git ];`
# into the same attrset literal, and a second definition is
# `error: attribute 'packages' already defined`. Reach for the `languages.*`
# option that installs the tool instead.
#
# `yaml` (optional) is plain devenv.yaml keys for what option lines cannot
# say -- the project's own nixpkgs configuration, such as allowing an unfree
# SDK. The CLI appends it to the devenv.yaml that `devenv init` writes, and
# refuses rather than write a second top-level key; it never overwrites.
# `systems` (optional) is the Nix systems an entry is offered on; without it,
# everywhere. An entry hidden on a system is absent from that system's index.
#
# Nothing here validates itself -- `lines` is a string. `nix run .#templates-check`
# scaffolds every entry with a real devenv and evaluates it. Run it before
# changing this file.
#
# ## Option names of the presets added here, read at devenv v2.3.1
#
#   src/modules/languages/java.nix    enable, jdk.package, maven.enable,
#                                     gradle.enable, lsp.enable (default on)
#   src/modules/languages/kotlin.nix  enable, lsp.enable (default on)
#   src/modules/languages/dotnet.nix  enable, package, lsp.enable
#   src/modules/languages/php.nix     enable, version, package, packages.composer
#   src/modules/languages/ruby.nix    enable, package, version, bundler.enable,
#                                     lsp.enable (default on)
#   src/modules/languages/dart.nix    enable, package
#   src/modules/integrations/android.nix
#                                     enable, emulator.enable, systemImages.enable,
#                                     ndk.enable (all three default on)
#
# devenv has no flutter module; flutter ships its own dart, so it is
# `languages.dart.package = pkgs.flutter`.
#
# ## Fields
#   kind     "preset" or "generator".
#   group    The create form's section: Languages, Data & ML, Mobile, Cloud.
#   label    Shown in the picker and in `nixarchy-devenv help`.
#   note     What the user gets and what it costs.
#   lines    (preset) devenv option lines, written flush left -- Nix '' strings
#            strip common indentation; pkgs/cli.nix indents them on the way in.
#   yaml     (preset, optional) devenv.yaml keys, flush left, appended as is.
#   systems  (optional) Nix systems the entry is offered on.
#   flake, rev, providers, honours  (generator) see the `cloud` entry.
{
  # react and node are the same three lines under two names, and that is
  # deliberate rather than an oversight waiting to be deduplicated. The name a
  # person types is the whole interface here: somebody starting a React app
  # types `react`, and answering "no such preset, did you mean node?" would be
  # a worse command for no gain. If the JavaScript lines ever diverge, they
  # diverge here without a caller changing.
  react = {
    kind = "preset";
    group = "Languages";
    label = "React";
    lines = ''
      languages.javascript = {
        enable = true;
        npm.enable = true;
      };
    '';
    note = "Node and npm, pinned to the project. Vite, Next and every other React toolchain install through npm from here.";
  };

  node = {
    kind = "preset";
    group = "Languages";
    label = "Node.js";
    lines = ''
      languages.javascript = {
        enable = true;
        npm.enable = true;
      };
    '';
    note = "Node and npm and nothing else. The starting point for anything JavaScript that is not React.";
  };

  # typescript on top of javascript, not instead of it: devenv's typescript
  # module adds the compiler and the language server and no runtime at all, so
  # a project with only `languages.typescript.enable` has tsc and no node to
  # run the output with. Checked against src/modules/languages/typescript.nix.
  typescript = {
    kind = "preset";
    group = "Languages";
    label = "TypeScript";
    lines = ''
      languages.javascript = {
        enable = true;
        npm.enable = true;
      };
      languages.typescript.enable = true;
    '';
    note = "Node, npm, tsc and the TypeScript language server. The javascript lines come too -- devenv's typescript module is the compiler, not a runtime.";
  };

  # uv.enable, not uv.sync.enable: sync runs `uv sync` on entering the shell,
  # which wants a pyproject.toml a freshly scaffolded project does not have.
  # With uv.enable devenv creates the venv through uv and puts uv itself on
  # the project's PATH; `uv sync` is one documented line for a project that
  # grows a pyproject.toml. Checked against src/modules/languages/python.
  python = {
    kind = "preset";
    group = "Languages";
    label = "Python";
    lines = ''
      languages.python = {
        enable = true;
        venv.enable = true;
        uv.enable = true;
      };
    '';
    note = "Python with uv and a virtualenv devenv creates and enters for you, so `uv pip install` and `pip install` land in the project rather than in your home directory.";
  };

  # The two machine-learning presets, and the reason they look nothing like a
  # nixpkgs answer to the same question.
  #
  # ## `ml`: uv's own CPython, deliberately
  #
  # The wheels an ML project actually installs -- torch, jax, onnxruntime --
  # ship their own CUDA or ROCm runtime INSIDE the wheel. The one thing they
  # cannot bundle is the driver, and on NixOS `libcuda.so.1` lives in
  # /run/opengl-driver/lib, which is on no default search path. That is the
  # whole of the machine-specific problem; nixpkgs' own cudaPackages solve a
  # different one (building CUDA software from source) at the cost of an
  # unfree rebuild of the world.
  #
  # And the correction that belongs with it, because it is the most common
  # "I did what the wiki said and it still fails": **nix-ld does not help a
  # nixpkgs Python.** nix-ld works by supplying a loader at the path a foreign
  # binary expects one, and reading NIX_LD/NIX_LD_LIBRARY_PATH from the
  # environment. A python3 out of nixpkgs is patched to use Nix's own loader
  # and never consults either variable. Only an UNPATCHED interpreter -- the
  # CPython uv downloads for itself -- is in a position to read them. Hence
  # `UV_PYTHON_PREFERENCE = "only-managed"` below, forced over the
  # "only-system" that `languages.python.uv.enable` sets: this preset is the
  # case where uv's interpreter is the point, not an implementation detail.
  #
  # Not poetry2nix. It is legacy, and its own README points at uv2nix, which
  # self-describes as experimental with breaking API changes -- fine for a
  # template somebody opts into with their eyes open, not for the preset a
  # first ML project gets scaffolded from.
  ml = {
    kind = "preset";
    group = "Data & ML";
    label = "Machine learning (uv, CUDA/ROCm)";
    lines = ''
      languages.python = {
        enable = true;
        uv.enable = true;
      };

      # The line that makes this preset different from `python`. uv will
      # otherwise reuse the nixpkgs interpreter the line above puts on PATH,
      # and a nixpkgs python3 is patched to use Nix's own loader -- it never
      # reads NIX_LD, so nix-ld cannot help a wheel it imports. uv's own
      # downloaded CPython is an ordinary Linux binary, and is the one
      # interpreter here that can.
      #
      # mkForce, because `languages.python.uv.enable` sets this itself, to
      # "only-system". Two plain definitions at equal priority are an
      # evaluation error, not a last-one-wins -- devenv added its default
      # under us and the preset stopped evaluating at the next nixpkgs bump.
      # The override says which of the two this preset means, and keeps
      # saying it if upstream changes its default again.
      env.UV_PYTHON_PREFERENCE = lib.mkForce "only-managed";

      # The driver is the one piece no wheel can ship. On NixOS it is here.
      env.LD_LIBRARY_PATH = "/run/opengl-driver/lib:" + lib.makeLibraryPath [
        pkgs.stdenv.cc.cc.lib
        pkgs.zlib
      ];
    '';
    note = "uv, with the driver on LD_LIBRARY_PATH so PyPI's CUDA and ROCm wheels load. Start with `uv venv` then `uv pip install torch` (CUDA) or `uv pip install torch --index-url https://download.pytorch.org/whl/rocm6.3` (ROCm). Deliberately uses uv's own Python: a nixpkgs python3 ignores nix-ld entirely.";
  };

  # ## `jupyter`: an ordinary devshell, which is the sharp part
  #
  # Search for Jupyter on Nix and the first answer is jupyenv (formerly
  # jupyterWith). It is unmaintained and does not track current nixpkgs, so
  # the evening goes: find it, fight its flake inputs, fail, conclude that
  # Jupyter on NixOS is hard. It is not hard. `python3.withPackages` with
  # jupyterlab in it is the entire answer, and `languages.python.package` is
  # where devenv takes one.
  #
  # `processes.jupyter` rather than an `enterShell` that launches it: devenv's
  # process manager is what upstream's own documentation reaches for, it means
  # `devenv up` starts the server and `cd` does not, and it is one more option
  # the user can read about at devenv.sh rather than here.
  jupyter = {
    kind = "preset";
    group = "Data & ML";
    label = "Jupyter";
    lines = ''
      languages.python = {
        enable = true;
        package = pkgs.python3.withPackages (ps: [
          ps.jupyterlab
          ps.ipykernel
          ps.ipywidgets
          ps.numpy
          ps.pandas
          ps.matplotlib
        ]);
      };

      processes.jupyter.exec = "jupyter lab --no-browser";
    '';
    note = "JupyterLab from nixpkgs, pinned by devenv.lock -- `devenv up` starts the server. Not jupyenv (formerly jupyterWith): that project is unmaintained and does not track current nixpkgs, and this is the working path it is usually mistaken for.";
  };

  go = {
    kind = "preset";
    group = "Languages";
    label = "Go";
    lines = ''
      languages.go.enable = true;
    '';
    note = "The Go toolchain plus gopls and delve, which devenv turns on with it.";
  };

  # No `channel` line. devenv defaults languages.rust.channel to "nixpkgs",
  # which is the toolchain the project's own nixpkgs already carries -- setting
  # it to "stable" instead would pull rust-overlay into every Rust project for
  # a version most people do not need, and it is one documented line for
  # someone who does.
  rust = {
    kind = "preset";
    group = "Languages";
    label = "Rust";
    lines = ''
      languages.rust.enable = true;
    '';
    note = "cargo, rustc, clippy and rust-analyzer from the project's nixpkgs. Add `languages.rust.channel = \"stable\";` for a rust-overlay toolchain instead.";
  };

  # ---- added in nixarchy-devenv #1 -------------------------------------------

  # Gradle rather than Maven as the plain `java`, because it is what `gradle
  # init` and Android Studio produce; Maven is one line away and has its own
  # entry because the name a person types is the interface.
  java = {
    kind = "preset";
    group = "Languages";
    label = "Java (Gradle)";
    lines = ''
      languages.java = {
        enable = true;
        gradle.enable = true;
      };
    '';
    note = "The JDK from the project's nixpkgs, Gradle and the Java language server. Set `languages.java.jdk.package = pkgs.jdk21;` to pin a release.";
  };

  java-maven = {
    kind = "preset";
    group = "Languages";
    label = "Java (Maven)";
    lines = ''
      languages.java = {
        enable = true;
        maven.enable = true;
      };
    '';
    note = "The JDK, Maven and the Java language server.";
  };

  # kotlin brings kotlinc and its language server but no build tool; Gradle is
  # what nearly every Kotlin project builds with, so the java module comes too.
  kotlin = {
    kind = "preset";
    group = "Languages";
    label = "Kotlin";
    lines = ''
      languages.kotlin.enable = true;
      languages.java = {
        enable = true;
        gradle.enable = true;
      };
    '';
    note = "kotlinc, the Kotlin language server, a JDK and Gradle.";
  };

  dotnet = {
    kind = "preset";
    group = "Languages";
    label = ".NET";
    lines = ''
      languages.dotnet.enable = true;
    '';
    note = "The dotnet SDK from the project's nixpkgs. `dotnet new console` from here.";
  };

  php = {
    kind = "preset";
    group = "Languages";
    label = "PHP";
    lines = ''
      languages.php.enable = true;
    '';
    note = "PHP with Composer. Add `services.mysql` or `services.postgres` for a database, and `languages.php.fpm.pools` for a web server.";
  };

  ruby = {
    kind = "preset";
    group = "Languages";
    label = "Ruby";
    lines = ''
      languages.ruby = {
        enable = true;
        bundler.enable = true;
      };
    '';
    note = "Ruby, Bundler and the Ruby language server. `languages.ruby.versionFile = ./.ruby-version;` follows a project's pinned version.";
  };

  flutter = {
    kind = "preset";
    group = "Mobile";
    label = "Flutter";
    lines = ''
      # Flutter ships its own Dart, so it stands in for the Dart SDK here.
      languages.dart = {
        enable = true;
        package = pkgs.flutter;
      };
    '';
    note = "Flutter and its Dart for web, Linux desktop and tests. Android builds need the Android SDK: that is the android template.";
  };

  # The SDK is unfree and a project's nixpkgs is its own (devenv.yaml), so the
  # preset carries the one yaml key that allows it; the module accepts the SDK
  # licence itself. The emulator, system images and NDK default on upstream --
  # gigabytes nobody asked for -- so they start off. x86_64 only: androidenv's
  # SDK and emulator are x86_64 binaries.
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

  # ---- generators ------------------------------------------------------------

  # Not a flake template: init.sh composes several providers into one project
  # (YAML imports, merged .mcp.json, skills), which `nix flake init -t` cannot.
  # Pinned: a bump of `rev` is its own commit, after templates-check passes.
  cloud = {
    kind = "generator";
    group = "Cloud";
    label = "Cloud project";
    flake = "github:olafkfreund/cloud-projects-templates";
    rev = "3ae8b0d73f2842dfc579f63e55944987cd787b4b";
    providers = [
      "aws"
      "azure"
      "gcp"
      "oci"
      "kubernetes"
      "cloudflare"
      "hetzner"
      "digitalocean"
    ];
    # init.sh runs `git init` whenever the directory is not in a work tree
    # (pkgs/init.sh:38), so the form cannot turn it off. It never allows.
    honours = {
      git = false;
      allow = true;
    };
    note = "Provider CLIs, Terraform, lint and security tools, AGENTS.md and agent skills, and MCP servers for AI agents. Some MCP servers need cloud credentials: give them read-only ones. Always runs git init.";
  };
}
