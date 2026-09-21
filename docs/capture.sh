#!/usr/bin/env bash
# Stages throwaway demo projects for the showcase captures in docs/img, and
# removes them again. Run it on the desktop the captures are taken on.
#
#   docs/capture.sh --setup      create the demo projects and point the widget
#                                at them (refuses if a previous run is recorded)
#   docs/capture.sh --teardown   remove exactly what --setup created, and put
#                                back the two saved config files
#   docs/capture.sh --shot NAME X,Y WxH
#                                crop one still into docs/img/NAME.png
#
# Only demo-* projects may appear in a capture. The owner's list names client
# work, so --setup points the widget's projectRoots at a fresh root holding
# nothing but demo projects, by editing the bar entry in shell.json -- saved
# before and restored on teardown byte for byte (cp -a), like
# omarchy-menu.jsonc. Every path it creates is recorded, and --teardown removes
# only those, revoking any it allowed.
set -euo pipefail

img_dir="$(cd "$(dirname "$0")" && pwd)/img"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
shell_json="$config/omarchy/shell.json"
saved=("$shell_json" "$config/omarchy/extensions/omarchy-menu.jsonc")
run_dir="${XDG_RUNTIME_DIR:-/tmp}/nixarchy-devenv-capture"
# One line per created thing, "kind value", read back by --teardown.
state="$run_dir/state"

made() { echo "$1 $2" >>"$state"; }

setup() {
  mkdir -p "$run_dir"
  if [ -s "$state" ]; then
    echo "refusing: $state exists (run --teardown first)" >&2
    exit 1
  fi
  : >"$state"
  local f i=0
  for f in "${saved[@]}"; do
    if [ -e "$f" ] || [ -L "$f" ]; then
      cp -a "$f" "$run_dir/saved.$i"
      made saved "$i $f"
    fi
    i=$((i + 1))
  done

  local demo
  demo=$(mktemp -d "$HOME/Projects/devenv-demo.XXXX")
  made root "$demo"
  nixarchy-devenv new --no-git --parent "$demo" --name demo-api python >/dev/null
  nixarchy-devenv new --parent "$demo" --name demo-web typescript >/dev/null
  nixarchy-devenv new --no-git --parent "$demo" --name demo-mobile flutter >/dev/null
  nixarchy-devenv new --no-git --parent "$demo" --name demo-svc go >/dev/null
  # A process, so the start button and the running state have something to show.
  sed -i 's|^  # processes.dev.exec.*|  processes.server.exec = "sleep 3600";|' "$demo/demo-svc/devenv.nix"
  nixarchy-devenv new --parent "$demo" --name demo-infra cloud aws gcp >/dev/null
  # Filled dots: two of them allowed, and revoked again on teardown.
  (cd "$demo/demo-api" && devenv allow >/dev/null) && made allowed "$demo/demo-api"
  (cd "$demo/demo-infra" && devenv allow >/dev/null) && made allowed "$demo/demo-infra"
  # A bound environment (#4): demo-bound has no devenv.nix of its own and takes
  # demo-shared's through `devenv --from`. GREET names the source, so the
  # shell's greeting shows where the environment came from. The first shell is
  # built here, so the recording does not sit through an evaluation.
  mkdir "$demo/demo-shared" "$demo/demo-bound"
  (cd "$demo/demo-shared" && devenv init >/dev/null 2>&1)
  sed -i 's|^  env.GREET = .*|  env.GREET = "demo-shared";|' "$demo/demo-shared/devenv.nix"
  (cd "$demo/demo-bound" && devenv --from "path:$demo/demo-shared" allow >/dev/null) && made allowed "$demo/demo-bound"
  (cd "$demo/demo-bound" && devenv shell -- true >/dev/null 2>&1) || echo "warning: demo-bound's first shell failed" >&2

  # Point the widget at the demo root only. The entry may be a bare id or an
  # object; either way it becomes an object carrying projectRoots.
  local tmp
  tmp=$(mktemp)
  jq --arg root "$demo" '
    .bar.layout |= with_entries(.value |= map(
      if . == "nixarchy.devenv" then {id: "nixarchy.devenv", projectRoots: $root}
      elif (type == "object" and .id == "nixarchy.devenv") then . + {projectRoots: $root}
      else . end))
  ' "$shell_json" >"$tmp"
  cat "$tmp" >"$shell_json"
  rm -f "$tmp"
  echo "demo root: $demo"
}

teardown() {
  [ -f "$state" ] || { echo "nothing recorded; nothing to remove"; return; }
  local kind rest
  while read -r kind rest; do
    case $kind in
      allowed) [ -d "$rest" ] && (cd "$rest" && devenv processes down >/dev/null 2>&1; devenv revoke >/dev/null 2>&1) || true ;;
    esac
  done <"$state"
  while read -r kind rest; do
    [ "$kind" = root ] || continue
    case $rest in "$HOME"/Projects/devenv-demo.*) ;; *) continue ;; esac
    [ -d "$rest/demo-svc" ] && (cd "$rest/demo-svc" && devenv processes down >/dev/null 2>&1) || true
    chmod -R u+w -- "$rest" 2>/dev/null || true
    rm -rf -- "$rest"
  done <"$state"
  while read -r kind rest; do
    [ "$kind" = saved ] || continue
    local i=${rest%% *} f=${rest#* }
    rm -f -- "$f"
    cp -a "$run_dir/saved.$i" "$f"
  done <"$state"
  rm -rf -- "$run_dir"
}

shot() {
  local name=$1 pos=$2 size=$3
  mkdir -p "$img_dir"
  grim -g "$pos $size" "$img_dir/$name.png"
  echo "  $name.png ($size at $pos)"
}

case "${1:-}" in
  --setup) setup ;;
  --teardown) teardown ;;
  --shot) shift; shot "$@" ;;
  *) sed -n '2,10p' "$0" >&2; exit 2 ;;
esac
