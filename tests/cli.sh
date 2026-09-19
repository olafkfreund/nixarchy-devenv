#!/usr/bin/env bash
# Tests for the nixarchy-devenv CLI against a stub devenv (tests/stub/devenv).
#
#   tests/cli.sh path/to/bin/nixarchy-devenv
#
# Everything runs under one temp root with HOME and XDG_* pointed into it, so
# nothing here can touch the invoking user's projects or devenv trust data.
set -uo pipefail

cli=$(readlink -f "$1")
here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

export HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" \
  XDG_DATA_HOME="$root/home/.local/share" XDG_STATE_HOME="$root/home/.local/state" \
  XDG_CACHE_HOME="$root/home/.cache" STUB_LOG="$root/stub.log"
unset DEVENV_HOME
mkdir -p "$HOME" "$XDG_DATA_HOME/devenv"
: >"$STUB_LOG"
# A PATH with only what the tests and the CLI need: never the invoking user's
# devenv or nix. "No devenv" has to mean no devenv, and nothing here may reach
# the network or the real trust database.
mkdir -p "$root/bin"
for c in bash env git cat grep sed jq mktemp readlink dirname rm mkdir sleep touch; do
  ln -s "$(command -v "$c")" "$root/bin/$c"
done
base_path="$root/bin"
export PATH="$base_path"
with_devenv() { PATH="$here/stub:$base_path" "$@"; }

pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*" >&2; }

# expect CODE DESCRIPTION -- COMMAND...
expect() {
  local want=$1 what=$2
  shift 3
  local got=0
  "$@" >"$root/out" 2>"$root/err" || got=$?
  if [ "$got" = "$want" ]; then ok; else
    bad "$what: exit $got, wanted $want"
    sed 's/^/    /' "$root/err" >&2
  fi
}

fresh() { local d; d=$(mktemp -d "$root/p.XXXX"); echo "$d"; }

# ---- templates ----------------------------------------------------------------

expect 0 "templates --json" -- "$cli" templates --json
jq -e 'length == 16 and all(.[]; .id and .kind and .group and .label)' "$root/out" >/dev/null ||
  bad "templates: 16 entries with id/kind/group/label"
jq -e 'map(select(.id=="cloud"))[0] | .honours_git == false and (.providers|index("aws"))' "$root/out" >/dev/null ||
  bad "templates: cloud generator fields"
expect 1 "templates without --json" -- "$cli" templates

mkdir -p "$XDG_CONFIG_HOME/nixarchy-devenv/templates/"{mine,Bad,python,broken}
for t in mine Bad python; do
  echo '{ }' >"$XDG_CONFIG_HOME/nixarchy-devenv/templates/$t/devenv.nix"
  echo '{"version":1,"label":"Mine","note":"n"}' >"$XDG_CONFIG_HOME/nixarchy-devenv/templates/$t/template.json"
done
echo '{ }' >"$XDG_CONFIG_HOME/nixarchy-devenv/templates/broken/devenv.nix"
echo 'not json' >"$XDG_CONFIG_HOME/nixarchy-devenv/templates/broken/template.json"
echo 'inputs: {}' >"$XDG_CONFIG_HOME/nixarchy-devenv/templates/mine/devenv.yaml"
expect 0 "templates with personal" -- "$cli" templates --json
jq -e 'length == 17 and (map(select(.id=="mine"))[0].kind == "personal")' "$root/out" >/dev/null ||
  bad "personal: only 'mine' is added (Bad id, built-in collision, broken json skipped)"
grep -q "Bad" "$root/err" && grep -q "python" "$root/err" && grep -q "broken" "$root/err" ||
  bad "personal: each skip is warned about"

# ---- init ---------------------------------------------------------------------

d=$(fresh)
expect 0 "init python" -- with_devenv bash -c "cd '$d' && '$cli' init --no-git python"
grep -q 'languages.python = {' "$d/devenv.nix" || bad "init python: preset spliced"
grep -q '^  languages.python = {' "$d/devenv.nix" || bad "init python: indented two spaces"
! grep -q 'languages.rust' "$d/devenv.nix" || bad "init python: placeholder replaced"
[ "$(cat "$d/.devenv-template")" = python ] || bad "init python: .devenv-template"
! grep -q "$d :: allow" "$STUB_LOG" || bad "init python: no allow unless asked"
[ ! -d "$d/.git" ] || bad "init --no-git: no repository"

expect 2 "init twice refuses" -- with_devenv bash -c "cd '$d' && '$cli' init python"
grep -q 'languages.python' "$root/err" || bad "refusal prints the lines to paste"

d=$(fresh)
expect 0 "init --allow go" -- with_devenv bash -c "cd '$d' && '$cli' init --allow go"
grep -q "$d :: allow" "$STUB_LOG" || bad "init --allow: devenv allow ran"
[ -d "$d/.git" ] || bad "init: git init by default"

d=$(fresh)
expect 1 "unknown template" -- with_devenv bash -c "cd '$d' && '$cli' init nope"
expect 1 "preset with providers" -- with_devenv bash -c "cd '$d' && '$cli' init python aws"
expect 1 "generator without providers" -- with_devenv bash -c "cd '$d' && '$cli' init cloud"
expect 1 "generator bad provider" -- with_devenv bash -c "cd '$d' && '$cli' init cloud aws mars"
expect 1 "generator --no-git" -- with_devenv bash -c "cd '$d' && '$cli' init --no-git cloud aws"
d=$(fresh)
expect 3 "no devenv" -- bash -c "cd '$d' && '$cli' init python"
grep -q 'nixarchy-service-enable devenv' "$root/err" || bad "missing devenv names the enable line"
[ ! -e "$d/devenv.nix" ] || bad "failed inits leave nothing behind"

d=$(fresh)
expect 0 "init cloud aws gcp" -- with_devenv bash -c "cd '$d' && '$cli' init cloud aws gcp"
grep -q "nix --extra-experimental-features nix-command flakes run github:olafkfreund/cloud-projects-templates/[0-9a-f]\{40\} -- aws gcp" "$STUB_LOG" ||
  bad "generator: pinned flake run with the providers"
[ "$(cat "$d/.devenv-template")" = cloud ] || bad "generator: .devenv-template"

d=$(fresh)
expect 0 "init personal" -- bash -c "cd '$d' && '$cli' init --no-git mine"
[ -f "$d/devenv.nix" ] && [ -f "$d/devenv.yaml" ] || bad "personal: files copied"
[ -w "$d/devenv.nix" ] || bad "personal: copies are writable"

# ---- new ----------------------------------------------------------------------

p=$(fresh)
expect 0 "new" -- with_devenv "$cli" new --no-git --parent "$p" --name app python
[ -f "$p/app/devenv.nix" ] || bad "new: project created"
expect 2 "new into existing" -- with_devenv "$cli" new --parent "$p" --name app python
expect 2 "new under missing parent" -- with_devenv "$cli" new --parent "$p/nope" --name x python
expect 1 "new relative parent" -- with_devenv "$cli" new --parent rel --name x python
for n in '../x' 'a b' '..' '-x' 'a;b' '$(id)' ''; do
  expect 1 "new rejects name '$n'" -- with_devenv "$cli" new --parent "$p" --name "$n" python
done
mkdir -p "$HOME/src"
expect 0 "new with ~ parent" -- with_devenv "$cli" new --no-git --parent "~/src" --name t python
[ -f "$HOME/src/t/devenv.nix" ] || bad "new: ~ expands to HOME"
expect 3 "new without devenv cleans up" -- "$cli" new --parent "$p" --name gone python
[ ! -e "$p/gone" ] || bad "new: failed create removes its directory"
expect 1 "new unknown template creates nothing" -- with_devenv "$cli" new --parent "$p" --name nt nope
[ ! -e "$p/nt" ] || bad "new: unknown template creates no directory"

echo "cli: $pass passed, $fail failed"
[ "$fail" = 0 ]
