#!/usr/bin/env bash
set -euo pipefail

template=${1:-}
share=${2:-}

die() {
  echo "nixarchy-devenv: scaffold: $*" >&2
  exit 1
}

[ -n "$template" ] && [ -d "$share" ] || die "missing scaffold arguments"
[ -z "$(find . -mindepth 1 -maxdepth 1 -print -quit)" ] || die "the destination is not empty"

project=$(basename "$PWD")
safe_project=$(printf '%s' "$project" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')
[ -n "$safe_project" ] || safe_project=project

write_common() {
  cp "$share/secrets.nix" secrets.nix
  mkdir -p secrets
  : >secrets/.gitkeep
  cat >devenv.yaml <<'YAML'
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
YAML
}

write_devenv() {
  local packages=$1
  cat >devenv.nix <<NIX
{ pkgs, ... }:

{
  packages = [ $packages ];
NIX
  cat "$share/secret-scaffold.nix" >>devenv.nix
  printf '}\n' >>devenv.nix
}

write_omarchy() {
  local plugin_id="dev.local.${safe_project}"
  write_common
  write_devenv "pkgs.git pkgs.nodejs pkgs.jq pkgs.qt6Packages.qtdeclarative"

  cat >manifest.json <<JSON
{
  "schemaVersion": 1,
  "id": "$plugin_id",
  "name": "${safe_project} plugin",
  "version": "0.1.0",
  "author": "Replace me",
  "license": "MIT",
  "description": "A starter Omarchy plugin.",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": {
    "displayName": "${safe_project}",
    "category": "Utility",
    "allowMultiple": false,
    "defaultSection": "center"
  }
}
JSON

  cat >BarWidget.qml <<QML
import QtQuick
import Quickshell
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "$plugin_id"

  Text {
    anchors.centerIn: parent
    text: Model.label
    color: Style.colors.onSurface
  }
}
QML

  cat >Model.js <<'JS'
.pragma library

function label() { return "Edit me" }

var Model = {
  label: label()
}

if (typeof module !== "undefined") module.exports = Model
JS

  cat >bindings.example.lua <<'LUA'
-- Add a binding in your user's bindings.lua after installing the plugin.
-- Example: o.add("SUPER + ALT + P", "omarchy-shell", "toggle", "dev.local.project")
LUA

  mkdir -p tests scripts
  cat >tests/model.test.js <<'JS'
const test = require("node:test")
const assert = require("node:assert/strict")
const model = require("../Model.js")

test("the starter model has a label", () => {
  assert.equal(model.label, "Edit me")
})
JS

  cat >scripts/validate <<'SH'
#!/usr/bin/env bash
set -euo pipefail
jq -e '.schemaVersion == 1 and (.entryPoints.barWidget | strings)' manifest.json >/dev/null
test -f BarWidget.qml
node --test tests/model.test.js
if [ -n "${OMARCHY_PATH:-}" ] && command -v qmllint >/dev/null 2>&1; then
  qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml
fi
echo "Omarchy starter checks passed"
SH
  chmod +x scripts/validate

  cat >README.md <<README
# ${safe_project} Omarchy plugin

This is a minimal Omarchy bar-widget starter. Replace the placeholder author,
description, plugin ID, QML, and model logic before publishing.

Run \`./scripts/validate\` for the manifest and Node checks. With Omarchy
installed, set \`OMARCHY_PATH\` to its shell source to include \`qmllint\`; then
run \`omarchy plugin validate .\` and test the plugin in the live shell.

The generated \`secrets.nix\` and \`secrets/*.age\` scaffold uses agenix helpers:
\`secret-add\`, \`secret-edit\`, \`secret-delete\`, \`secret-user-add\`, and
\`secret-rekey\`. Add recipients before storing values. Never put credentials in
the manifest, QML, Lua, Git history, or Nix evaluation.
README
}

write_nixos() {
  write_common
  write_devenv "pkgs.git pkgs.nix pkgs.nixfmt pkgs.statix pkgs.deadnix"

  mkdir -p hosts/example modules scripts
  cat >flake.nix <<'NIX'
{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, agenix }:
    {
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          agenix.nixosModules.default
          ./hosts/example/configuration.nix
        ];
      };
    };
}
NIX

  cat >hosts/example/configuration.nix <<'NIX'
{ pkgs, ... }:

{
  networking.hostName = "example";
  environment.systemPackages = [ pkgs.git ];

  # Set this to the release you are actually deploying.
  system.stateVersion = "25.11";
}
NIX

  cat >modules/README.md <<'MD'
# Modules

Put reusable NixOS modules here. Keep host-specific hardware, boot devices,
users, and networking in the relevant `hosts/<name>/` directory.
MD

  cat >scripts/validate <<'SH'
#!/usr/bin/env bash
set -euo pipefail
nixfmt --check flake.nix hosts/example/configuration.nix
deadnix --fail .
statix check
nix flake check --no-build
echo "NixOS configuration starter checks passed"
SH
  chmod +x scripts/validate

  cat >README.md <<README
# ${safe_project} NixOS configuration

This is a deliberately small flake with one example host. Replace the host
name, system, state version, hardware configuration, users, and modules before
applying it. Do not copy this example's values into a real machine blindly.

Run \`./scripts/validate\` or \`devenv shell -- ./scripts/validate\`. Review the
result, then apply explicitly with your normal command, for example:
\`sudo nixos-rebuild switch --flake .#example\`.

Agenix is wired into the example flake for system secrets. Add your own age
recipients and declarations before adding a secret; never put private keys or
plaintext values in this repository. The devenv also includes \`secret-add\`,
\`secret-edit\`, \`secret-delete\`, \`secret-user-add\`, and \`secret-rekey\` for
project runtime secrets.
README
}

case "$template" in
  omarchy-plugin) write_omarchy ;;
  nixos-config) write_nixos ;;
  *) die "unknown scaffold '$template'" ;;
esac
