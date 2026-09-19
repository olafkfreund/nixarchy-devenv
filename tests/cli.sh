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
for c in bash env git cat grep sed jq mktemp readlink dirname rm mkdir sleep touch ln sort uniq wc sha256sum stat; do
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
# A root that is itself a symlink is followed; nothing below it is.
ln -s "$L" "$root/linkroot"
expect 0 "list via a symlinked root" -- "$cli" list --json --root "$root/linkroot"
jq -r '.rows[].path' "$out" | grep -qxF "$L/a" || bad "list: a symlinked root is followed, rows are canonical"
jq -e --arg l "$L" '.roots == [$l]' "$out" >/dev/null || bad "list: roots reported canonically"
! jq -r '.rows[].path' "$out" | grep -q "/link$" || bad "list: symlinks below a root still not followed"
expect 1 "list without --json" -- "$cli" list

# ---- status -------------------------------------------------------------------

S=$(fresh)
STUB_PROCESSES=running expect 0 "status running" -- with_devenv env STUB_PROCESSES=running "$cli" status --json "$S"
jq -e '.state == "running" and (.processes | map(.name) == ["web","db"])' "$root/out" >/dev/null || bad "status: running parsed"
expect 0 "status: progress only, exit 0" -- with_devenv env STUB_PROCESSES=noise "$cli" status --json "$S"
jq -e '.state == "unknown"' "$root/out" >/dev/null || bad "status: exit 0 with no process rows is unknown"
expect 0 "status stopped" -- with_devenv env STUB_PROCESSES=stopped "$cli" status --json "$S"
jq -e '.state == "stopped"' "$root/out" >/dev/null || bad "status: stopped"
expect 0 "status hang" -- with_devenv env STUB_PROCESSES=hang NIXARCHY_DEVENV_STATUS_TIMEOUT=1 "$cli" status --json "$S"
jq -e '.state == "unknown"' "$root/out" >/dev/null || bad "status: a hang is unknown"
expect 0 "status fail" -- with_devenv env STUB_PROCESSES=fail "$cli" status --json "$S"
jq -e '.state == "unknown"' "$root/out" >/dev/null || bad "status: an error is unknown"
expect 0 "status without devenv" -- "$cli" status --json "$S"
jq -e '.state == "unknown" and .devenv == false' "$root/out" >/dev/null || bad "status: no devenv"
expect 2 "status of missing dir" -- "$cli" status --json "$root/nope"

# ---- remove -------------------------------------------------------------------

R=$(fresh)
mkdir -p "$R/root"
mkproj() {
  local d="$R/root/$1"
  mkdir -p "$d/src" "$d/.devenv/state/db" "$d/.devenv/profile"
  echo '{ }' >"$d/devenv.nix"; echo 'inputs: {}' >"$d/devenv.yaml"; echo '{}' >"$d/devenv.lock"
  echo python >"$d/.devenv-template"; echo code >"$d/src/main.py"; echo data >"$d/.devenv/state/db/x"
  echo 'use devenv' >"$d/.envrc"
  echo "$d"
}
dev_of() { stat -c %d "$1"; }
rm_cli() { with_devenv env STUB_PROCESSES="${STUB_PROCESSES:-stopped}" "$cli" remove "$@"; }
untouched() { [ -f "$1/devenv.nix" ] && [ -f "$1/src/main.py" ] && [ -f "$1/.devenv/state/db/x" ] || bad "$2: nothing may be deleted"; }

p=$(mkproj a)
d=$(dev_of "$p")
expect 1 "remove: bad tier" -- rm_cli --tier all --confirm "$p" --dev "$d" "$p"
expect 1 "remove: no --dev" -- rm_cli --tier files --confirm "$p" "$p"
expect 2 "remove: confirm mismatch" -- rm_cli --tier files --confirm "$p/" --dev "$d" "$p"; untouched "$p" "confirm mismatch"
ln -s "$p" "$R/alias"
expect 2 "remove: symlinked dir" -- rm_cli --tier folder --confirm "$R/alias" --dev "$d" "$R/alias"; untouched "$p" "symlink"
expect 2 "remove: HOME" -- rm_cli --tier folder --confirm "$HOME" --dev "$(dev_of "$HOME")" "$HOME"
expect 2 "remove: a root" -- rm_cli --tier folder --confirm "$R/root" --dev "$(dev_of "$R/root")" --root "$R/root" "$R/root"
echo '{ }' >"$R/devenv.nix"
expect 2 "remove: a root's parent" -- rm_cli --tier folder --confirm "$R" --dev "$(dev_of "$R")" --root "$R/root" "$R"
[ -d "$R/root" ] || bad "remove: a root's parent: nothing may be deleted"
ln -s "$R/root" "$R/rootlink"
expect 2 "remove: a root given as a symlink" -- rm_cli --tier folder --confirm "$R" --dev "$(dev_of "$R")" --root "$R/rootlink" "$R"
expect 2 "remove: dev mismatch" -- rm_cli --tier files --confirm "$p" --dev 999999 "$p"; untouched "$p" "dev mismatch"
mkdir -p "$R/root/plain"
expect 2 "remove: no devenv.nix" -- rm_cli --tier folder --confirm "$R/root/plain" --dev "$d" "$R/root/plain"
[ -d "$R/root/plain" ] || bad "remove: no devenv.nix: nothing may be deleted"
expect 2 "remove: running" -- env STUB_PROCESSES=running bash -c "$(declare -f rm_cli with_devenv); cli='$cli' here='$here' base_path='$base_path' rm_cli --tier files --confirm '$p' --dev '$d' '$p'"
untouched "$p" "running"
expect 2 "remove: unknown" -- env STUB_PROCESSES=hang NIXARCHY_DEVENV_STATUS_TIMEOUT=1 bash -c "$(declare -f rm_cli with_devenv); cli='$cli' here='$here' base_path='$base_path' rm_cli --tier files --confirm '$p' --dev '$d' '$p'"
untouched "$p" "unknown"

: >"$STUB_LOG"
expect 0 "remove: files" -- rm_cli --tier files --confirm "$p" --dev "$d" "$p"
[ ! -e "$p/devenv.nix" ] && [ ! -e "$p/devenv.yaml" ] && [ ! -e "$p/devenv.lock" ] && [ ! -e "$p/.devenv-template" ] || bad "files: devenv files gone"
[ -f "$p/.devenv/state/db/x" ] || bad "files: .devenv/state kept"
[ ! -e "$p/.devenv/profile" ] || bad "files: the rest of .devenv gone"
[ -f "$p/src/main.py" ] && [ -f "$p/.envrc" ] || bad "files: code and .envrc kept"
grep -q "$p :: revoke" "$STUB_LOG" || bad "files: revoked"

p=$(mkproj b)
expect 0 "remove: state" -- rm_cli --tier state --confirm "$p" --dev "$(dev_of "$p")" "$p"
[ ! -e "$p/.devenv" ] && [ -f "$p/src/main.py" ] || bad "state: .devenv gone, code kept"

p=$(mkproj c)
expect 0 "remove: folder" -- rm_cli --tier folder --confirm "$p" --dev "$(dev_of "$p")" --root "$R/root" "$p"
[ ! -e "$p" ] && [ -d "$R/root" ] || bad "folder: the project gone, the root kept"

p=$(mkproj d)
expect 0 "remove: without devenv, nothing can be running" -- "$cli" remove --tier files --confirm "$p" --dev "$(dev_of "$p")" "$p"
[ ! -e "$p/devenv.nix" ] || bad "remove without devenv"

echo "cli: $pass passed, $fail failed"
[ "$fail" = 0 ]
