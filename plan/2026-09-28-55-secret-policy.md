---
status: approved
issue: 55
spec: spec/2026-09-28-55-secret-policy.md
---

# Plan: Standardize encrypted secrets across templates

Make secret handling a catalogue invariant: every built-in preset gets the
shared agenix scaffold by default, and every generator declares and is checked
against an explicit external policy. Keep SecretSpec opt-in for a future
template with a real provider contract.

## Steps

1. `pkgs/cli.nix` and `data/templates.nix`: add the `secretPolicy` catalogue
   field and derive `agenix` for every built-in preset while preserving explicit
   scaffold metadata. Mark cloud generators `external-agenix` → verify the
   template index exposes one supported policy for every entry.
2. `pkgs/cli.sh` and `pkgs/secret-scaffold.nix`: switch preset creation to the
   policy field, preserving the existing agenix files and helper commands. Keep
   runtime-only decryption, path/name/recipient validation, deletion rollback,
   and no plaintext values in generated Nix → verify representative old presets
   create the same safe scaffold.
3. `pkgs/templates-check.nix`: after each scaffold, assert the declared secret
   files and helper commands for presets and generators, while retaining the
   hermetic HOME/XDG environment and allow-list checksum → verify every
   catalogue entry with `nix run .#templates-check`.
4. `tests/cli.sh` and fixtures: cover all policy metadata, representative
   preset scaffolds, generator output, invalid secret names, unsafe/duplicate
   recipients, encrypted-only directory contents, and absence of plaintext
   values → verify the stub CLI suite without real credentials.
5. `README.md` and `docs/usage.md`: document the policy boundary, agenix
   workflow, runtime-only use, recipient ownership/rotation, and when a future
   template may use SecretSpec or SOPS → verify all supported template IDs and
   helper names are documented.

## Tests

```bash
node --test 'tests/model/*.test.js'
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
nix flake check --all-systems --no-build
nix run .#templates-check
```

The real template runner must report the invoking user's devenv allow list
unchanged. It must scaffold every available preset and generator without real
credentials, and any generated `secrets/` file must be `.age` or `.gitkeep`.

## Rollback

Revert the implementation commits for issue #55. This restores the previous
template metadata and scaffold selection; it does not touch existing project
secret files or machine-wide secret state.
