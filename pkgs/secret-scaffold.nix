  scripts = {
    secret-add = {
      description = "Encrypt a secret: printf %s VALUE | secret-add NAME (or prompt)";
      packages = [ pkgs.age pkgs.jq pkgs.gnused pkgs.openssh ];
      exec = ''
        set -euo pipefail
        name=''${1:?usage: secret-add NAME}
        [ $# = 1 ] || { echo 'usage: secret-add NAME' >&2; exit 1; }
        [[ $name =~ ^[A-Z][A-Z0-9_]*$ ]] || { echo "NAME must match ^[A-Z][A-Z0-9_]*$" >&2; exit 1; }
        cd "$DEVENV_ROOT"
        recipient_args=()
        while read -r recipient; do [ -n "$recipient" ] && recipient_args+=(--recipient "$recipient"); done < <(
          nix-instantiate --eval --strict --json \
            --argstr secretFile "$DEVENV_ROOT/secrets.nix" --argstr name "$name" \
            -E '{ secretFile, name }: (builtins.getAttr ("secrets/" + name + ".age") (import secretFile)).publicKeys' | jq -r '.[]'
        )
        [ ''${#recipient_args[@]} -gt 0 ] || { echo "add a recipient to secrets.nix first" >&2; exit 1; }
        entry="\"secrets/$name.age\".publicKeys = recipients;"
        if ! grep -Fqx -- "  $entry" secrets.nix; then
          sed -i "/# secret-add inserts entries above this line/i\\  $entry" secrets.nix
          trap 'rm -f -- "secrets/$name.age.tmp"; sed -i "\\|  $entry|d" secrets.nix' EXIT
        fi
        if [ -t 0 ]; then read -rsp "$name: " value; echo >&2; else value=$(cat); fi
        [ -n "$value" ] || { echo "empty value, nothing written" >&2; exit 1; }
        printf %s "$value" | age "''${recipient_args[@]}" -o "secrets/$name.age.tmp"
        mv -- "secrets/$name.age.tmp" "secrets/$name.age"
        trap - EXIT
        echo "wrote secrets/$name.age" >&2
      '';
    };
    secret-edit = {
      description = "Replace a secret's value";
      exec = ''exec secret-add "$@"'';
    };
    secret-delete = {
      description = "Delete one encrypted secret and its declaration";
      packages = [ pkgs.gnused ];
      exec = ''
        set -euo pipefail
        name=''${1:?usage: secret-delete NAME}
        [ $# = 1 ] || { echo 'usage: secret-delete NAME' >&2; exit 1; }
        [[ $name =~ ^[A-Z][A-Z0-9_]*$ ]] || { echo "NAME must match ^[A-Z][A-Z0-9_]*$" >&2; exit 1; }
        cd "$DEVENV_ROOT"
        file="secrets/$name.age"
        [ -f "$file" ] && [ ! -L "$file" ] || { echo "missing encrypted secret: $file" >&2; exit 1; }
        entry="\"$file\".publicKeys = recipients;"
        grep -Fqx -- "  $entry" secrets.nix || { echo "missing declaration for $file" >&2; exit 1; }
        backup=$(mktemp -d)
        trap 'cp -- "$backup/secrets.nix" secrets.nix; cp -- "$backup/secret.age" "$file"; rm -rf -- "$backup"' EXIT
        cp -- secrets.nix "$backup/secrets.nix"
        cp -- "$file" "$backup/secret.age"
        tmp=$(mktemp secrets.nix.XXXXXX)
        grep -Fvx -- "  $entry" secrets.nix >"$tmp"
        mv -- "$tmp" secrets.nix
        rm -- "$file"
        trap - EXIT
        rm -rf -- "$backup"
        echo "deleted $file; review the Git diff" >&2
      '';
    };
    secret-user-add = {
      description = "Add an SSH recipient and re-encrypt all secrets";
      packages = [ pkgs.age pkgs.jq pkgs.gnused pkgs.openssh ];
      exec = ''
        set -euo pipefail
        key=''${1:?usage: secret-user-add SSH_PUBLIC_KEY [LABEL]}
        label=''${2:-}
        [ $# -le 2 ] || { echo 'usage: secret-user-add SSH_PUBLIC_KEY [LABEL]' >&2; exit 1; }
        [[ $key != *$'\n'* && $key != *'"'* && $key != *'\\'* ]] || { echo 'public key contains unsafe characters' >&2; exit 1; }
        [ -z "$label" ] || [[ $label =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'LABEL contains unsafe characters' >&2; exit 1; }
        printf '%s\n' "$key" | ssh-keygen -lf - >/dev/null 2>&1 || { echo 'invalid SSH public key' >&2; exit 1; }
        cd "$DEVENV_ROOT"
        grep -Fq -- "    \"$key\"" secrets.nix && { echo 'public key is already a recipient' >&2; exit 1; }
        backup=$(mktemp)
        trap 'cp -- "$backup" secrets.nix; rm -f -- "$backup"' EXIT
        cp -- secrets.nix "$backup"
        line="    \"$key\""
        [ -z "$label" ] || line="$line # $label"
        sed -i "/# secret-user-add inserts recipients above this line/i\\$line" secrets.nix
        secret-rekey
        trap - EXIT
        rm -f -- "$backup"
        echo 'recipient added and secrets rekeyed; review the Git diff' >&2
      '';
    };
    secret-list = {
      description = "List secret names, never values";
      exec = ''for f in "$DEVENV_ROOT"/secrets/*.age; do [ -e "$f" ] && basename "$f" .age; done; true'';
    };
    secret-rekey = {
      description = "Re-encrypt all secrets for the recipients in secrets.nix";
      packages = [ pkgs.age pkgs.jq ];
      exec = ''
        set -euo pipefail
        id="''${AGENIX_IDENTITY:-$HOME/.ssh/id_ed25519}"
        for file in "$DEVENV_ROOT"/secrets/*.age; do
          [ -e "$file" ] || continue
          name=$(basename "$file" .age)
          args=()
          while read -r recipient; do [ -n "$recipient" ] && args+=(--recipient "$recipient"); done < <(
            nix-instantiate --eval --strict --json \
              --argstr secretFile "$DEVENV_ROOT/secrets.nix" --argstr name "$name" \
              -E '{ secretFile, name }: (builtins.getAttr ("secrets/" + name + ".age") (import secretFile)).publicKeys' | jq -r '.[]'
          )
          [ ''${#args[@]} -gt 0 ] || { echo "no recipients for $name" >&2; exit 1; }
          if age -d -i "$id" "$file" | age "''${args[@]}" -o "$file.tmp"; then
            mv -- "$file.tmp" "$file"
          else
            rm -f -- "$file.tmp"
            echo "failed to rekey $name" >&2
            exit 1
          fi
        done
      '';
    };
    secret-run = {
      description = "Run a command with decrypted secrets: secret-run [--only NAME,...] -- CMD";
      packages = [ pkgs.age ];
      exec = ''
        set -euo pipefail
        id="''${AGENIX_IDENTITY:-$HOME/.ssh/id_ed25519}"
        only=""
        if [ "''${1:-}" = --only ]; then only=",''${2:?--only needs names},"; shift 2; fi
        [ "''${1:-}" = -- ] && shift
        [ $# -gt 0 ] || { echo 'usage: secret-run [--only NAME,...] -- CMD' >&2; exit 1; }
        found=,
        for file in "$DEVENV_ROOT"/secrets/*.age; do
          [ -e "$file" ] || continue
          name=$(basename "$file" .age)
          [ -z "$only" ] || [[ $only == *",$name,"* ]] || continue
          value=$(age -d -i "$id" "$file")
          export "$name=$value"
          found="$found$name,"
        done
        for name in ''${only//,/ }; do
          [ -z "$name" ] || [[ $found == *",$name,"* ]] || { echo "secret $name not found" >&2; exit 1; }
        done
        exec "$@"
      '';
    };
  };
