{
  description = "nixarchy.devenv -- devenv environments in the Omarchy shell: a bar widget, a full-screen keyboard menu, and the nixarchy-devenv CLI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in rec {
          cli = pkgs.callPackage ./pkgs/cli.nix { };
          default = cli;
        });

      checks = forAll (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cli = self.packages.${system}.cli;
        in
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

          # omarchy-plugin-validate refuses a symlink anywhere in a plugin, and
          # `omarchy plugin add` clones this repository AS the plugin folder.
          repo = pkgs.runCommand "nixarchy-devenv-repo-check" { } ''
            if [ -n "$(find ${self} -mindepth 1 -type l)" ]; then
              find ${self} -mindepth 1 -type l >&2
              echo "symlink in the repository above" >&2; exit 1
            fi
            if grep -rnwE 'pacman|yay' ${self}/pkgs ${self}/data; then
              echo "Arch package manager reference above" >&2; exit 1
            fi
            touch "$out"
          '';
        });
    };
}
