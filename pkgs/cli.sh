# nixarchy-devenv: the half of the plugin that touches the disk.
#
# The QML plugin draws this command's JSON and calls it by argv; it never
# reads a project directory or runs devenv itself, except to open a terminal.
# That keeps every check that protects your files in one place that can be
# tested from a shell, and makes the plugin's features usable without it.
#
# pkgs/cli.nix prepends `share=<store path>` to this file. `devenv`, `git` and
# `nix` are NOT runtime inputs: devenv bundles its own Nix, and a machine that
# never asked for devenv must not get that closure through this command.
#
# Exit codes: 0 ok, 1 usage, 2 refused, 3 missing dependency, 4 the command
# this ran failed. JSON goes to stdout as one document; messages to stderr.

index="$share/templates.json"
personal_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy-devenv/templates"

die() {
  local code=$1
  shift
  printf 'nixarchy-devenv: %s\n' "$@" >&2
  exit "$code"
}

need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  case "$1" in
    devenv)
      die 3 "devenv is not installed." \
        "On nixarchy: nixarchy-service-enable devenv && nixarchy apply" \
        "Elsewhere: https://devenv.sh/getting-started/"
      ;;
    *) die 3 "$1 is not installed, and this needs it." ;;
  esac
}

# ---- templates ----------------------------------------------------------------

# Personal templates: ~/.config/nixarchy-devenv/templates/<id>/ with a
# template.json and a devenv.nix. Read, never evaluated. A bad one is skipped
# with a warning rather than hiding the rest.
personal_json() {
  local d id warn=${1:-quiet}
  [ -d "$personal_dir" ] || { echo '[]'; return; }
  for d in "$personal_dir"/*/; do
    [ -d "$d" ] || continue
    id=$(basename "$d")
    if ! [[ $id =~ ^[a-z0-9-]+$ ]]; then
      [ "$warn" = quiet ] || echo "nixarchy-devenv: skipped personal template '$id': ids are [a-z0-9-]" >&2
      continue
    fi
    if [ ! -f "$d/devenv.nix" ] || [ ! -f "$d/template.json" ]; then
      [ "$warn" = quiet ] || echo "nixarchy-devenv: skipped personal template '$id': needs template.json and devenv.nix" >&2
      continue
    fi
    if jq -e --arg id "$id" 'any(.[]; .id == $id)' "$index" >/dev/null; then
      [ "$warn" = quiet ] || echo "nixarchy-devenv: skipped personal template '$id': a built-in template has that id" >&2
      continue
    fi
    jq -c --arg id "$id" '
      select(.version == 1)
      | {id: $id, kind: "personal", group: "Yours",
         label: (.label // $id | tostring), note: (.note // "" | tostring)}
    ' "$d/template.json" 2>/dev/null ||
      [ "$warn" = quiet ] || echo "nixarchy-devenv: skipped personal template '$id': template.json is not version 1 JSON" >&2
  done | jq -s '.'
}

all_templates() {
  jq -s '.[0] + .[1]' "$index" <(personal_json "${1:-quiet}")
}

template_field() {
  all_templates | jq -r --arg id "$1" --arg f "$2" \
    'map(select(.id == $id))[0] | if . != null and has($f) then .[$f] | if type == "array" then join(" ") else tostring end else empty end'
}

cmd_templates() {
  [ "${1:-}" = "--json" ] || die 1 "usage: nixarchy-devenv templates --json"
  all_templates warn
}

cmd_help() {
  echo "Templates:"
  all_templates warn | jq -r '.[] | [.id, .label, .group] | @tsv' |
    while IFS=$'\t' read -r id label group; do
      printf '  %-12s %-34s %s\n' "$id" "$label" "[$group]"
    done
  cat <<'EOF'

  nixarchy-devenv init [--allow] [--no-git] <template> [provider...]
      scaffold the current directory
  nixarchy-devenv new [--allow] [--no-git] --parent DIR --name NAME <template> [provider...]
      create DIR/NAME and scaffold it
  nixarchy-devenv list --json [--root DIR]...
  nixarchy-devenv templates --json
  nixarchy-devenv status --json DIR
  nixarchy-devenv remove --tier files|state|folder --confirm DIR --dev N [--root DIR]... DIR

--allow runs `devenv allow` afterwards, so the environment activates on cd.
It is off unless you ask: a devenv.nix is code that runs when you enter it.
EOF
}

# ---- init / new ---------------------------------------------------------------

# Upstream's scaffold has one commented language line -- `# languages.rust.enable
# = true;` at 2.3.1 -- which is where a reader looks, so the preset replaces it.
# Matched on shape, not on `rust`. If upstream drops the comment the preset goes
# before the last column-zero `}` instead, never nowhere.
splice_preset() {
  local file=$1 placeholder close
  placeholder='^[[:space:]]*# languages\.[a-z0-9]+\.enable = true;[[:space:]]*$'
  if grep -qE "$placeholder" devenv.nix; then
    sed -i -E "/$placeholder/{
      r $file
      d
    }" devenv.nix
  else
    close=$(grep -n '^}' devenv.nix | tail -1 | cut -d: -f1)
    head -n "$((close - 1))" devenv.nix >devenv.nix.new
    cat "$file" >>devenv.nix.new
    tail -n +"$close" devenv.nix >>devenv.nix.new
    mv devenv.nix.new devenv.nix
  fi
}

cmd_init() {
  local allow=0 git=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --allow) allow=1 ;;
      --no-git) git=0 ;;
      -*) die 1 "unknown option $1" ;;
      *) break ;;
    esac
    shift
  done
  [ $# -ge 1 ] || die 1 "usage: nixarchy-devenv init [--allow] [--no-git] <template> [provider...]"
  local tpl=$1
  shift
  local kind
  kind=$(template_field "$tpl" kind)
  [ -n "$kind" ] || { cmd_help >&2; die 1 "no template '$tpl'."; }

  # A refusal, not a merge: against a devenv.nix somebody has been working in
  # there is no scaffold to splice into and no honest guess where lines go.
  if [ -e devenv.nix ]; then
    if [ "$kind" = preset ]; then
      {
        echo "nixarchy-devenv: this directory already has a devenv.nix."
        echo "To add the '$tpl' lines by hand:"
        echo
        sed 's/^/  /' "$share/presets/$tpl.nix"
      } >&2
      exit 2
    fi
    die 2 "this directory already has a devenv.nix."
  fi

  if [ "$kind" != generator ] && [ $# -gt 0 ]; then
    die 1 "'$tpl' takes no providers."
  fi

  case "$kind" in
    preset)
      need devenv
      devenv init || die 4 "devenv init failed."
      splice_preset "$share/presets/$tpl.nix"
      ;;
    personal)
      # -n: never overwrite. Checked above that devenv.nix is absent; a
      # devenv.yaml already here is kept and said so.
      cp -n --no-preserve=mode "$personal_dir/$tpl/devenv.nix" devenv.nix
      if [ -f "$personal_dir/$tpl/devenv.yaml" ]; then
        if [ -e devenv.yaml ]; then
          echo "nixarchy-devenv: kept the existing devenv.yaml" >&2
        else
          cp -n --no-preserve=mode "$personal_dir/$tpl/devenv.yaml" devenv.yaml
        fi
      fi
      ;;
    generator)
      [ $# -ge 1 ] || die 1 "'$tpl' needs at least one provider: $(template_field "$tpl" providers)"
      local p allowed
      allowed=" $(template_field "$tpl" providers) "
      for p in "$@"; do
        [[ $allowed == *" $p "* ]] || die 1 "'$p' is not a provider of '$tpl'. Providers:$allowed"
      done
      if [ "$git" = 0 ] && [ "$(template_field "$tpl" honours_git)" = false ]; then
        die 1 "'$tpl' always runs git init, so --no-git cannot be honoured."
      fi
      need nix
      nix --extra-experimental-features 'nix-command flakes' run "$(template_field "$tpl" flake)/$(template_field "$tpl" rev)" -- "$@" ||
        die 4 "the '$tpl' generator failed."
      ;;
  esac

  if [ "$git" = 1 ] && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    need git
    git init -q || die 4 "git init failed."
  fi

  echo "$tpl" >.devenv-template

  if [ "$allow" = 1 ]; then
    need devenv
    devenv allow || die 4 "devenv allow failed."
  fi

  cat <<EOF

Scaffolded a $tpl project in $PWD.

The first \`devenv shell\` here fetches the inputs devenv.yaml names -- it needs
the network once, takes a while, and writes devenv.lock. Commit the lock with
devenv.nix and devenv.yaml: it is what makes this reproducible.
EOF
  if [ "$allow" = 0 ]; then
    echo
    echo "Not allowed for automatic activation. Run \`devenv shell\`, or \`devenv allow\`"
    echo "here to have it activate when you cd in."
  fi
}

cmd_new() {
  local flags=() parent="" name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --allow | --no-git) flags+=("$1") ;;
      --parent) parent=${2:-}; shift ;;
      --name) name=${2:-}; shift ;;
      -*) die 1 "unknown option $1" ;;
      *) break ;;
    esac
    shift
  done
  [ -n "$parent" ] && [ -n "$name" ] && [ $# -ge 1 ] ||
    die 1 "usage: nixarchy-devenv new [--allow] [--no-git] --parent DIR --name NAME <template> [provider...]"
  [[ $name =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] ||
    die 1 "project names are letters, digits, '.', '_' and '-', starting with a letter, digit or '_'."
  case "$parent" in
    \~) parent=$HOME ;;
    \~/*) parent="$HOME/${parent:2}" ;;
    /*) ;;
    *) die 1 "the parent directory must be an absolute path or start with ~." ;;
  esac
  [ -d "$parent" ] || die 2 "$parent does not exist."
  local dir="$parent/$name"
  [ ! -e "$dir" ] && [ ! -L "$dir" ] || die 2 "$dir already exists. Pick another name, or run init inside it."
  [ -n "$(template_field "$1" kind)" ] || { cmd_help >&2; die 1 "no template '$1'."; }

  mkdir "$dir" || die 4 "could not create $dir."
  # The directory is ours until init succeeds, so a failed create takes it
  # away again rather than leaving a half-project that blocks the retry.
  local rc=0
  (cd "$dir" && cmd_init "${flags[@]}" "$@") || rc=$?
  if [ "$rc" != 0 ]; then
    rm -rf -- "$dir"
    die "$rc" "creating $dir failed; removed the partial directory."
  fi
}

# ---- list ---------------------------------------------------------------------

allowed_file() {
  if [ -n "${DEVENV_HOME:-}" ]; then
    echo "$DEVENV_HOME/allowed"
  else
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/devenv/allowed"
  fi
}

expand_root() {
  case "$1" in
    \~) echo "$HOME" ;;
    \~/*) echo "$HOME/${1:2}" ;;
    *) echo "$1" ;;
  esac
}

# The template a project was made from, if we made it. Anything else is
# "custom": guessing from the contents of devenv.nix would be a guess.
template_of() {
  local t=""
  [ -f "$1/.devenv-template" ] && t=$(head -n1 "$1/.devenv-template")
  if [[ $t =~ ^[a-z0-9-]+$ ]]; then echo "$t"; else echo custom; fi
}

# True when DIR or any ancestor has a devenv.nix; -e, as devenv's .exists().
shadowed() {
  local d=$1
  while :; do
    [ -e "$d/devenv.nix" ] && return 0
    [ "$d" = / ] && return 1
    d=$(dirname -- "$d")
  done
}

cmd_list() {
  [ "${1:-}" = "--json" ] || die 1 "usage: nixarchy-devenv list --json [--root DIR]..."
  shift
  local roots=() r
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) [ -n "${2:-}" ] || die 1 "--root needs a directory"; roots+=("$(expand_root "$2")"); shift ;;
      *) die 1 "unknown argument $1" ;;
    esac
    shift
  done

  local tmp
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  : >"$tmp/candidates"
  : >"$tmp/warnings"
  : >"$tmp/allowed"

  # Roots: -H follows a symlink only when it IS the root (~/Source is often
  # one) and never below it. The pruned directories are where vendored copies
  # of other people's devenv.nix live. Each root is also reported
  # canonically: rows are canonical paths, and "is this a root" has to compare
  # like with like.
  : >"$tmp/roots"
  for r in "${roots[@]}"; do
    if [ ! -d "$r" ] || [ ! -r "$r" ] || [ ! -x "$r" ]; then
      echo "$r is missing or unreadable" >>"$tmp/warnings"
      continue
    fi
    printf '%s\t%s\n' "$r" "$(realpath -e -- "$r")" >>"$tmp/roots"
    find -H "$r" -maxdepth 3 \
      \( -name .git -o -name node_modules -o -name .devenv -o -name .direnv \) -prune \
      -o -name devenv.nix -type f -printf '%h\0' 2>/dev/null >>"$tmp/candidates"
  done

  # The allow list: a hint, read and never written. A line that is not JSON
  # with a string path is counted rather than fatal -- devenv may be halfway
  # through writing it.
  local af skipped=0 total=0 good=0
  af=$(allowed_file)
  if [ -f "$af" ]; then
    total=$(grep -c . "$af" || true)
    jq -R -r 'fromjson? | .path? | select(type == "string" and startswith("/"))' "$af" \
      >"$tmp/allowed.raw" 2>/dev/null || true
    good=$(grep -c . "$tmp/allowed.raw" || true)
    skipped=$((total - good))
    while IFS= read -r r; do
      if [ -f "$r/devenv.nix" ] && [ ! -L "$r/devenv.nix" ]; then
        printf '%s\0' "$r" >>"$tmp/candidates"
      fi
      realpath -e -- "$r" 2>/dev/null >>"$tmp/allowed" || true
    done <"$tmp/allowed.raw"
  fi

  # Deduped by realpath; the path shown is that realpath, which is what a
  # removal later has to match exactly.
  local d real
  declare -A seen=()
  while IFS= read -r -d '' d; do
    real=$(realpath -e -- "$d" 2>/dev/null) || continue
    [ -z "${seen[$real]:-}" ] || continue
    seen[$real]=1
    jq -n -c \
      --arg path "$real" \
      --arg name "$(basename "$real")" \
      --argjson allowed "$(grep -qxF -- "$real" "$tmp/allowed" && echo true || echo false)" \
      --argjson lockfile "$([ -f "$real/devenv.lock" ] && echo true || echo false)" \
      --arg template "$(template_of "$real")" \
      --argjson hasProcesses "$(grep -qE '^[[:space:]]*(processes|services)[[:space:]]*[.=]' "$real/devenv.nix" && echo true || echo false)" \
      --argjson dev "$(stat -c %d "$real")" \
      --argjson mtime "$(stat -c %Y "$real/devenv.nix")" \
      '$ARGS.named + {from: "", profiles: []}'
  done <"$tmp/candidates" >"$tmp/rows"

  # Bound environments: `devenv --from SRC allow` writes the allow line as
  # {"path", "from", "profiles"} and nothing else records the binding
  # (TrustEntry in devenv/src/commands/hook.rs, read at v2.3.1). devenv only
  # consults a binding when no devenv.nix exists in the directory or any
  # ancestor (find_project_root, then trusted_from), so neither do we. Its
  # source is shown as text, never fetched; Start is offered because what the
  # source defines cannot be known without evaluating it.
  if [ -f "$af" ]; then
    jq -R -c 'fromjson? | select((.path | type) == "string" and (.path | startswith("/")) and (.from | type) == "string")
      | {path, from, profiles: ((.profiles // []) | if type == "array" then map(strings) else [] end)}' \
      "$af" 2>/dev/null >"$tmp/bound" || true
    local b
    while IFS= read -r b; do
      real=$(realpath -e -- "$(jq -r .path <<<"$b")" 2>/dev/null) || continue
      [ -d "$real" ] && [ -z "${seen[$real]:-}" ] || continue
      shadowed "$real" && continue
      seen[$real]=1
      jq -c \
        --arg path "$real" \
        --arg name "$(basename "$real")" \
        --argjson lockfile "$([ -f "$real/devenv.lock" ] && echo true || echo false)" \
        --argjson dev "$(stat -c %d "$real")" \
        --argjson mtime "$(stat -c %Y "$real")" \
        '{path: $path, name: $name, allowed: true, lockfile: $lockfile, template: "custom",
          hasProcesses: true, dev: $dev, mtime: $mtime, from, profiles}' <<<"$b"
    done <"$tmp/bound" >>"$tmp/rows"
  fi

  jq -n \
    --slurpfile rows "$tmp/rows" \
    --rawfile warnings "$tmp/warnings" \
    --rawfile roots "$tmp/roots" \
    --argjson skipped "$skipped" \
    '($roots | split("\n") | map(select(. != "") | split("\t") | {given: .[0], canonical: .[1]})) as $map
     | {rows: $rows, roots: ($map | map(.canonical) | unique), rootMap: $map,
      warnings: ($warnings | split("\n") | map(select(. != ""))), skipped: $skipped}'
}

# ---- status -------------------------------------------------------------------

# Read-only, and fast: with no process manager running, devenv answers in
# ~0.1 s without evaluating anything (measured at 2.3.1). Anything that is not
# one of its two known answers is "unknown" -- and unknown blocks removal.
cmd_status() {
  [ "${1:-}" = "--json" ] && [ -n "${2:-}" ] || die 1 "usage: nixarchy-devenv status --json DIR"
  local dir=$2 out rc=0
  [ -d "$dir" ] || die 2 "$dir is not a directory."
  if ! command -v devenv >/dev/null 2>&1; then
    jq -n '{state: "unknown", devenv: false, processes: []}'
    return
  fi
  out=$(cd "$dir" && timeout "${NIXARCHY_DEVENV_STATUS_TIMEOUT:-10}" devenv processes list 2>&1) || rc=$?
  # A process row is `name   status restarts: N`. Anything else in the output
  # is devenv's progress on stderr ("• Validating lock", "✓ …"), which is not
  # a process and must not become one.
  local rows
  rows=$(printf '%s\n' "$out" | grep -E '^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+restarts:' || true)
  if [ "$rc" = 0 ] && [ -n "$rows" ]; then
    printf '%s\n' "$rows" | jq -R -s '
      {state: "running", devenv: true,
       processes: (split("\n") | map(select(test("\\S")) | capture("^(?<name>\\S+)\\s+(?<status>\\S+)")?) )}'
  elif [ "$rc" != 124 ] && printf '%s' "$out" | grep -q 'No process manager is running'; then
    jq -n '{state: "stopped", devenv: true, processes: []}'
  else
    jq -n --arg why "$(printf '%s' "$out" | tail -n 3)" '{state: "unknown", devenv: true, processes: [], detail: $why}'
  fi
}

# ---- remove -------------------------------------------------------------------

# The one command here that deletes. Every check runs HERE, immediately before
# anything is removed -- the plugin checks too, but the plugin is a UI and this
# is the thing holding the knife. Any doubt is a refusal (exit 2) and nothing
# is touched.
#
#   files   devenv.nix, devenv.yaml, devenv.lock, .devenv-template, and .devenv/
#           EXCEPT .devenv/state (a service's data -- a database -- lives there),
#           then `devenv revoke`. Your code stays.
#   state   the above, and .devenv/state.
#   folder  the whole directory.
#
# .envrc is never removed: this tool never writes one, so no .envrc can be
# byte-identical to ours, and one somebody wrote is theirs.
cmd_remove() {
  local tier="" confirm="" dev="" dir="" roots=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier) tier=${2:-}; shift ;;
      --confirm) confirm=${2:-}; shift ;;
      --dev) dev=${2:-}; shift ;;
      --root) roots+=("${2:-}"); shift ;;
      -*) die 1 "unknown option $1" ;;
      *) [ -z "$dir" ] || die 1 "one directory at a time"; dir=$1 ;;
    esac
    shift
  done
  case "$tier" in files | state | folder) ;; *) die 1 "--tier is files, state or folder" ;; esac
  [ -n "$dir" ] && [ -n "$confirm" ] && [[ $dev =~ ^[0-9]+$ ]] ||
    die 1 "usage: nixarchy-devenv remove --tier files|state|folder --confirm DIR --dev N [--root DIR]... DIR"

  [ "$confirm" = "$dir" ] || die 2 "refused: --confirm does not name $dir exactly."
  local canon
  canon=$(realpath -e -- "$dir" 2>/dev/null) || die 2 "refused: $dir does not exist."
  [ "$canon" = "$dir" ] || die 2 "refused: $dir is not a canonical path (it resolves to $canon)."
  [ "$dir" != / ] || die 2 "refused: /."
  local home
  home=$(realpath -e -- "$HOME" 2>/dev/null || echo "$HOME")
  [ "$dir" != "$home" ] || die 2 "refused: your home directory."
  case "$home/" in "$dir"/*) die 2 "refused: $dir contains your home directory." ;; esac
  local r rc
  for r in "${roots[@]}"; do
    rc=$(realpath -e -- "$(expand_root "$r")" 2>/dev/null) || continue
    case "$rc/" in "$dir"/*) die 2 "refused: $dir is a project root, or contains one ($rc)." ;; esac
  done
  [ -f "$dir/devenv.nix" ] && [ ! -L "$dir/devenv.nix" ] || die 2 "refused: $dir has no devenv.nix of its own."
  [ "$(stat -c %d -- "$dir")" = "$dev" ] || die 2 "refused: $dir is not on the device it was listed on; refresh and try again."

  # Processes: stopped, or no devenv at all. Unknown is a no -- a database
  # losing its files under a running server is the failure this prevents.
  local state
  state=$(cmd_status --json "$dir" | jq -r '.state + " " + (.devenv | tostring)')
  case "$state" in
    "stopped true" | *" false") ;;
    "running true") die 2 "refused: processes are running in $dir; stop them first." ;;
    *) die 2 "refused: could not tell whether processes are running in $dir." ;;
  esac

  if command -v devenv >/dev/null 2>&1; then
    (cd "$dir" && devenv revoke) >/dev/null 2>&1 || echo "nixarchy-devenv: devenv revoke failed; continuing" >&2
  fi

  case "$tier" in
    folder)
      rm -rf -- "$dir" || die 4 "could not remove $dir."
      echo "Removed $dir."
      return
      ;;
  esac

  rm -f -- "$dir/devenv.nix" "$dir/devenv.yaml" "$dir/devenv.lock" "$dir/.devenv-template"
  if [ -L "$dir/.devenv" ]; then
    rm -f -- "$dir/.devenv"
  elif [ -d "$dir/.devenv" ]; then
    if [ "$tier" = state ]; then
      rm -rf -- "$dir/.devenv"
    else
      find "$dir/.devenv" -mindepth 1 -maxdepth 1 ! -name state -exec rm -rf -- {} +
      rmdir -- "$dir/.devenv" 2>/dev/null || true
    fi
  fi
  if [ "$tier" = state ]; then
    echo "Removed devenv's files and state from $dir. Your code is still there."
  else
    echo "Removed devenv's files from $dir, keeping .devenv/state. Your code is still there."
  fi
}

# ---- dispatch -----------------------------------------------------------------

case "${1:-help}" in
  templates) shift; cmd_templates "$@" ;;
  init) shift; cmd_init "$@" ;;
  new) shift; cmd_new "$@" ;;
  list) shift; cmd_list "$@" ;;
  status) shift; cmd_status "$@" ;;
  remove) shift; cmd_remove "$@" ;;
  help | -h | --help) cmd_help ;;
  *) cmd_help >&2; die 1 "unknown command '$1'." ;;
esac
