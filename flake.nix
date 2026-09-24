{
  description = "nixarchy.devenv -- devenv environments in the Omarchy shell: a bar widget, a full-screen keyboard menu, and the nixarchy-devenv CLI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;

      manifest = builtins.fromJSON (builtins.readFile ./manifest.json);

      # Exactly what the shell loads. The CLI is its own package; the
      # artifacts, tests and docs are for whoever reads the repository.
      files = [
        ./manifest.json
        ./qmldir
        ./LICENSE
        ./Model.js
        ./Panel.qml
        ./Menu.qml
        ./DevenvState.qml
        ./DevenvView.qml
        ./EnvList.qml
        ./CreateForm.qml
        ./LogView.qml
        ./ShortcutSheet.qml
        ./devenv-binds.lua
      ];

      pluginFor = pkgs:
        # runCommand and plain copies, deliberately: omarchy-plugin-validate
        # refuses any symlink inside a plugin folder, so symlinkJoin or a
        # linkFarm would fail validation at rebuild time.
        pkgs.runCommand "nixarchy-devenv-plugin-${manifest.version}"
          {
            meta = with pkgs.lib; {
              description = "Omarchy plugin: list, create, enter and manage devenv environments from the bar and a key";
              homepage = "https://github.com/olafkfreund/nixarchy-devenv";
              license = licenses.mit;
              platforms = platforms.linux;
            };
          }
          ''
            mkdir -p "$out"
            ${nixpkgs.lib.concatMapStringsSep "\n" (f: ''cp ${f} "$out/${baseNameOf f}"'') files}
          '';
    in
    {
      # The key bind, the one piece of the plugin that lives outside the plugin
      # folder. Writes ~/.config/hypr/devenv-binds.lua from the same file the
      # plugin ships, so the Nix and non-Nix installs bind the same thing.
      # bindings.lua still has to load it: pcall(require, "hypr.devenv-binds").
      homeManagerModules.default = { config, lib, ... }:
        let cfg = config.programs.nixarchy-devenv;
        in
        {
          options.programs.nixarchy-devenv.keybinding = lib.mkOption {
            # A chord only: the value lands inside a Lua string.
            type = lib.types.nullOr (lib.types.strMatching "[A-Z0-9_ +]+");
            default = "SUPER + ALT + E";
            description = "Chord that opens Dev environments, in Omarchy's o.bind syntax. Null writes no bind.";
          };

          config = lib.mkIf (cfg.keybinding != null) {
            home.file.".config/hypr/devenv-binds.lua".text =
              builtins.replaceStrings [ "SUPER + ALT + E" ] [ cfg.keybinding ]
                (builtins.readFile ./devenv-binds.lua);
          };
        };

      packages = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in rec {
          cli = pkgs.callPackage ./pkgs/cli.nix { };
          plugin = pluginFor pkgs;
          default = plugin;
        });

      apps = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          templates-check = {
            type = "app";
            program = "${pkgs.callPackage ./pkgs/templates-check.nix { cli = self.packages.${system}.cli; }}/bin/templates-check";
            meta.description = "Scaffold every template with a real devenv and evaluate it (needs network)";
          };
        });

      checks = forAll (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cli = self.packages.${system}.cli;
          hasAndroid = nixpkgs.lib.elem "android" cli.templateIds;
        in
        # Evaluated, not built, so `--all-systems --no-build` proves it: an
        # entry's `systems` hides it from every other system's index.
        assert system == "x86_64-linux" -> hasAndroid;
        assert system != "x86_64-linux" -> !hasAndroid;
        {
          # The CLI against stub devenv and nix: templates, init, new, list,
          # status. tests/cli.sh builds its own PATH, so the tools it links
          # have to be on this one.
          cli = pkgs.runCommand "nixarchy-devenv-cli-check"
            {
              nativeBuildInputs = with pkgs; [ bash git jq coreutils gnugrep gnused ];
            }
            ''
              cp -r ${./tests} tests
              chmod -R u+w tests
              patchShebangs tests
              bash tests/cli.sh ${cli}/bin/nixarchy-devenv
              touch "$out"
            '';

          # Model.js carries all the plugin's logic, and runs under plain Node.
          model = pkgs.runCommand "nixarchy-devenv-model-check"
            { nativeBuildInputs = [ pkgs.nodejs ]; }
            ''
              cp -r ${./tests} tests
              cp ${./Model.js} Model.js
              node --test 'tests/model/*.test.js'
              touch "$out"
            '';

          # The manifest is what the shell validates at load: a typo in it is a
          # plugin that silently never appears.
          plugin = let plugin = self.packages.${system}.plugin; in
            pkgs.runCommand "nixarchy-devenv-plugin-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
              jq -e '
                .schemaVersion == 1
                and .id == "nixarchy.devenv"
                and .keepLoaded == true
                and (.kinds | index("menu") and index("bar-widget"))
                and .entryPoints.menu == "Menu.qml"
                and .entryPoints.barWidget == "Panel.qml"
              ' ${plugin}/manifest.json > /dev/null
              for f in $(jq -r '.entryPoints[]' ${plugin}/manifest.json); do
                test -f "${plugin}/$f" || { echo "entry point $f missing from the package" >&2; exit 1; }
              done
              # Without this line the bar and the menu each get their own
              # state, and "one mutation at a time" silently stops holding.
              grep -qx 'singleton DevenvState 1.0 DevenvState.qml' ${plugin}/qmldir \
                || { echo "qmldir does not declare the DevenvState singleton" >&2; exit 1; }
              if [ -n "$(find ${plugin} -mindepth 1 -type l)" ]; then
                echo "symlink inside the package" >&2; exit 1
              fi
              # A literal colour survives a theme switch and looks wrong.
              if grep -nE '"#[0-9a-fA-F]{3,8}"' ${plugin}/*.qml; then
                echo "hardcoded colour above; use a Color.* token" >&2; exit 1
              fi
              touch "$out"
            '';

          # Every local component a packaged .qml references (Quickshell
          # resolves siblings by bare filename, with no import line) or imports
          # by path must itself be in the package. Candidate names come from
          # the whole repository, not just what is packaged: that is what
          # catches a new file that was referenced but never added to the
          # `files` list above, which otherwise passes every check here and
          # fails only when the shell loads the plugin.
          files = let plugin = self.packages.${system}.plugin; in
            pkgs.runCommand "nixarchy-devenv-files-check" { } ''
              fail=0
              for f in ${plugin}/*.qml; do
                base=$(basename "$f" .qml)
                for other in ${self}/*.qml; do
                  obase=$(basename "$other" .qml)
                  [ "$obase" = "$base" ] && continue
                  if grep -qw "$obase" "$f" && [ ! -f "${plugin}/$obase.qml" ]; then
                    echo "$base.qml references $obase, but $obase.qml is not in flake.nix's files list" >&2
                    fail=1
                  fi
                done
                for imp in $(grep -ohE 'import "[^"]+"' "$f" | sed -E 's/import "(.*)"/\1/'); do
                  [ -f "${plugin}/$imp" ] || {
                    echo "$base.qml imports \"$imp\", which is not in flake.nix's files list" >&2
                    fail=1
                  }
                done
              done
              [ "$fail" -eq 0 ] || exit 1
              touch "$out"
            '';

          # omarchy-plugin-validate refuses a symlink anywhere in a plugin, and
          # `omarchy plugin add` clones this repository AS the plugin folder.
          repo = pkgs.runCommand "nixarchy-devenv-repo-check" { } ''
            if [ -n "$(find ${self} -mindepth 1 -type l)" ]; then
              find ${self} -mindepth 1 -type l >&2
              echo "symlink in the repository above" >&2; exit 1
            fi
            # docs/img ships inside every `omarchy plugin add` clone.
            if [ -d ${self}/docs/img ] && [ "$(du -sk ${self}/docs/img | cut -f1)" -gt 8192 ]; then
              du -sh ${self}/docs/img >&2
              echo "docs/img is over 8 MB" >&2; exit 1
            fi
            # Excludes only the files whose job is to talk *about* the rule:
            # flake.nix carries this pattern's own text, AGENTS.md states the
            # rule, and intent/spec/plan hold design history that quotes it
            # while proposing to change it. Nothing else may mention either
            # word, not even in a comment.
            if grep -rnwE 'pacman|yay' ${self} \
                --exclude-dir=.git --exclude-dir=result \
                --exclude=flake.nix --exclude=AGENTS.md \
                --exclude-dir=intent --exclude-dir=spec --exclude-dir=plan; then
              echo "Arch package manager reference above" >&2; exit 1
            fi
            touch "$out"
          '';
        });
    };
}
