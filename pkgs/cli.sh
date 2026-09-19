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

# ---- dispatch -----------------------------------------------------------------

case "${1:-help}" in
  templates) shift; cmd_templates "$@" ;;
  init) shift; cmd_init "$@" ;;
  new) shift; cmd_new "$@" ;;
  help | -h | --help) cmd_help ;;
  *) cmd_help >&2; die 1 "unknown command '$1'." ;;
esac
