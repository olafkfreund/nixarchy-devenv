# `nix run .#templates-check [id...]` -- scaffold every template with the real
# CLI and a real devenv, and evaluate it. Needs the network, so it is not in
# `nix flake check`; run it before changing data/templates.nix and before a
# release.
#
# Hermetic about the one thing that matters: devenv's trust data. The runner
# this replaces (nixarchy's devenv-presets) moved HOME but inherited
# XDG_DATA_HOME, and every run added its temp directories to the invoking
# user's real allow list -- 80 dead entries on p620. Here every scaffold runs
# under `env -i` with HOME, XDG_* and DEVENV_HOME all inside one temp root, and
# the real allow list's checksum is compared before and after.
{
  writeShellApplication,
  cli,
  devenv,
  cacert,
  coreutils,
  git,
  jq,
}:
writeShellApplication {
  name = "templates-check";
  runtimeInputs = [ cli devenv coreutils git jq ];
  text = ''
    real_allowed=''${DEVENV_HOME:+$DEVENV_HOME/allowed}
    real_allowed=''${real_allowed:-''${XDG_DATA_HOME:-$HOME/.local/share}/devenv/allowed}
    sum() { if [ -f "$real_allowed" ]; then sha256sum <"$real_allowed"; else echo absent; fi; }
    before=$(sum)

    root=$(mktemp -d)
    cleanup() { chmod -R u+w "$root" 2>/dev/null; rm -rf "$root"; }
    trap cleanup EXIT
    mkdir -p "$root/home" "$root/p"

    # PATH, the Nix variables and the CA bundle pass through (devenv and the
    # cloud generator fetch from GitHub through the daemon); nothing else from
    # the invoking session does. Without a CA bundle devenv's fetch fails as
    # "the SSL certificate is invalid", so fall back to nixpkgs' own.
    ca=''${SSL_CERT_FILE:-''${NIX_SSL_CERT_FILE:-${cacert}/etc/ssl/certs/ca-bundle.crt}}
    iso() {
      env -i PATH="$PATH" TERM=dumb \
        NIX_PATH="''${NIX_PATH:-}" NIX_REMOTE="''${NIX_REMOTE:-}" \
        SSL_CERT_FILE="$ca" NIX_SSL_CERT_FILE="$ca" \
        HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" XDG_DATA_HOME="$root/home/.local/share" \
        XDG_STATE_HOME="$root/home/.local/state" XDG_CACHE_HOME="$root/home/.cache" \
        "$@"
    }

    index=$(iso nixarchy-devenv templates --json)
    if [ $# -gt 0 ]; then
      ids=("$@")
    else
      mapfile -t ids < <(jq -r '.[].id' <<<"$index")
    fi

    failed=()
    for id in "''${ids[@]}"; do
      kind=$(jq -r --arg id "$id" '.[] | select(.id == $id) | .kind' <<<"$index")
      args=(--no-git)
      extra=()
      if [ "$kind" = generator ]; then args=(); extra=(aws); fi
      printf '%-12s ' "$id"
      if ! iso nixarchy-devenv new "''${args[@]}" --parent "$root/p" --name "$id" "$id" "''${extra[@]}" >"$root/$id.log" 2>&1; then
        echo "FAIL (scaffold)"; sed 's/^/    /' "$root/$id.log" | tail -20; failed+=("$id"); continue
      fi
      # `devenv info` is the cheapest command that evaluates the whole module.
      if ! (cd "$root/p/$id" && iso devenv info) >>"$root/$id.log" 2>&1; then
        echo "FAIL (devenv info)"; tail -20 "$root/$id.log" | sed 's/^/    /'
        sed 's/^/    | /' "$root/p/$id/devenv.nix"; failed+=("$id"); continue
      fi
      # flutter stands in for dart through `package`; prove it is on PATH.
      if [ "$id" = flutter ] && ! (cd "$root/p/$id" && iso devenv shell -- flutter --version) >>"$root/$id.log" 2>&1; then
        echo "FAIL (flutter --version)"; tail -20 "$root/$id.log" | sed 's/^/    /'; failed+=("$id"); continue
      fi
      echo ok
    done

    if [ "$before" != "$(sum)" ]; then
      echo "the real devenv allow list at $real_allowed changed during the check" >&2
      exit 1
    fi
    echo "allow list at $real_allowed unchanged"

    if [ ''${#failed[@]} -gt 0 ]; then
      echo "failed: ''${failed[*]}" >&2
      exit 1
    fi
    echo "all ''${#ids[@]} templates scaffold and evaluate"
  '';
}
