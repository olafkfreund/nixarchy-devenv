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
for c in bash env git cat grep sed jq mktemp readlink dirname rm mkdir sleep touch ln sort uniq wc sha256sum printf; do
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

# ---- list ---------------------------------------------------------------------

L=$(fresh)
mkdir -p "$L/a" "$L/a/nested" "$L/deep/1/2/3" "$L/b/node_modules/x" "$L/b/.git/y" "$L/real" "$L/sp ace"
for d in a a/nested deep/1/2/3 b/node_modules/x b/.git/y real "sp ace"; do echo '{ }' >"$L/$d/devenv.nix"; done
ln -s "$L/real" "$L/link"
echo python >"$L/a/.devenv-template"
echo '../../etc' >"$L/real/.devenv-template"
printf '{ ... }:\n{\n  processes.web.exec = "x";\n}\n' >"$L/a/nested/devenv.nix"
printf '{ ... }:\n{\n  # processes.web.exec = "x";\n}\n' >"$L/real/devenv.nix"
touch "$L/a/devenv.lock"
O=$(fresh)
mkdir -p "$O/outside"
echo '{ }' >"$O/outside/devenv.nix"

allowed="$XDG_DATA_HOME/devenv/allowed"
{
  echo "{\"path\":\"$L/a\"}"
  echo "{\"path\":\"$O/outside\"}"
  echo "{\"path\":\"$root/gone\"}"
  echo 'not json'
  echo '{"path":42}'
  echo "{\"path\":\"$L/a\""
} >"$allowed"
before=$(sha256sum "$allowed")

expect 0 "list" -- "$cli" list --json --root "$L" --root "$root/missing"
out="$root/out"
paths() { jq -r '.rows[].path' "$out" | sort; }
paths | grep -qxF "$L/a" || bad "list: a"
paths | grep -qxF "$L/a/nested" || bad "list: nested project is its own row"
paths | grep -qxF "$L/sp ace" || bad "list: path with a space"
paths | grep -qxF "$L/real" || bad "list: real"
! paths | grep -q "/link$" || bad "list: symlink not followed"
! paths | grep -q "deep/1/2/3" || bad "list: depth limit"
! paths | grep -q "node_modules\|\.git" || bad "list: pruned directories"
paths | grep -qxF "$O/outside" || bad "list: allowed path outside the roots is listed"
! paths | grep -q "/gone" || bad "list: dead allow entry hidden"
[ "$(paths | sort | uniq -d | wc -l)" = 0 ] || bad "list: no duplicates"
jq -e '.skipped == 3' "$out" >/dev/null || bad "list: 3 malformed allow lines counted, got $(jq .skipped "$out")"
jq -e '.warnings | length == 1 and (.[0] | test("missing"))' "$out" >/dev/null || bad "list: missing root warned"
row() { jq -c --arg p "$1" '.rows[] | select(.path == $p)' "$out"; }
row "$L/a" | jq -e '.allowed and .lockfile and .template == "python" and (.hasProcesses | not) and (.dev|type=="number")' >/dev/null || bad "list: row a fields"
row "$L/real" | jq -e '(.allowed | not) and (.lockfile | not) and .template == "custom" and (.hasProcesses | not)' >/dev/null || bad "list: bad .devenv-template is custom, commented processes ignored"
row "$L/a/nested" | jq -e '.hasProcesses' >/dev/null || bad "list: hasProcesses"
[ "$before" = "$(sha256sum "$allowed")" ] || bad "list: allow file unchanged"

DEVENV_HOME="$root/dh" expect 0 "list with DEVENV_HOME" -- env DEVENV_HOME="$root/dh" "$cli" list --json
jq -e '.rows == [] and .skipped == 0' "$out" >/dev/null || bad "list: DEVENV_HOME replaces the XDG allow file"
mkdir -p "$root/xdg2/devenv" && echo "{\"path\":\"$O/outside\"}" >"$root/xdg2/devenv/allowed"
expect 0 "list with XDG_DATA_HOME" -- env XDG_DATA_HOME="$root/xdg2" "$cli" list --json
jq -e '.rows | length == 1' "$out" >/dev/null || bad "list: XDG_DATA_HOME honoured"
expect 1 "list without --json" -- "$cli" list

# ---- status -------------------------------------------------------------------

S=$(fresh)
STUB_PROCESSES=running expect 0 "status running" -- with_devenv env STUB_PROCESSES=running "$cli" status --json "$S"
jq -e '.state == "running" and (.processes | map(.name) == ["web","db"])' "$root/out" >/dev/null || bad "status: running parsed"
expect 0 "status stopped" -- with_devenv env STUB_PROCESSES=stopped "$cli" status --json "$S"
jq -e '.state == "stopped"' "$root/out" >/dev/null || bad "status: stopped"
expect 0 "status hang" -- with_devenv env STUB_PROCESSES=hang NIXARCHY_DEVENV_STATUS_TIMEOUT=1 "$cli" status --json "$S"
jq -e '.state == "unknown"' "$root/out" >/dev/null || bad "status: a hang is unknown"
expect 0 "status fail" -- with_devenv env STUB_PROCESSES=fail "$cli" status --json "$S"
jq -e '.state == "unknown"' "$root/out" >/dev/null || bad "status: an error is unknown"
expect 0 "status without devenv" -- "$cli" status --json "$S"
jq -e '.state == "unknown" and .devenv == false' "$root/out" >/dev/null || bad "status: no devenv"
expect 2 "status of missing dir" -- "$cli" status --json "$root/nope"

echo "cli: $pass passed, $fail failed"
[ "$fail" = 0 ]
