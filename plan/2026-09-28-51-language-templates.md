---
status: draft
issue: 51
spec: spec/2026-09-28-51-language-templates.md
---

# Plan: Rust, Python, Go, and C++ templates

Add four small preset templates and one shared encrypted-secret scaffold. The
presets remain ordinary devenv option lines; the scaffold is injected once by
the CLI so it cannot drift between templates or create a second `packages`
attribute.

## Steps

1. `data/templates.nix`: add `rust`, `python`, `go`, and `cpp` preset entries
   using the approved language-module options and notes. Add the common secret
   scaffold marker to these entries → verify the catalogue evaluates.
2. `pkgs/cli.sh`, `pkgs/cli.nix`, and the smallest shared scaffold assets:
   extend preset creation to add agenix-compatible `secrets.nix`, an empty
   encrypted-only `secrets/` directory, and devenv scripts for secret add,
   edit, delete, run, rekey, and recipient add. Put helper dependencies on
   each script, validate names and keys, and never write secret values to the
   Nix expression or store → verify generated files contain no plaintext
   values and existing preset creation remains unchanged.
3. `tests/cli.sh` and related fixtures: assert the four catalogue entries,
   generated language options, scaffold files, helper commands, and refusal of
   unsafe secret names/recipient input → verify with the stub CLI test.
4. `pkgs/templates-check.nix`: include the four presets in the real devenv
   runner and preserve the hermetic environment and allow-list check → verify
   each generated project evaluates with `nix run .#templates-check rust python
   go cpp`.
5. `README.md` and `docs/usage.md`: document the four templates, the intentional
   C++ build-system choice, Python's lack of automatic dependency sync, and the
   shared encrypted-secret commands → verify the documented template IDs match
   the catalogue.

## Tests

```bash
node --test 'tests/model/*.test.js'
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
nix flake check --all-systems --no-build
nix run .#templates-check rust python go cpp
```

The generated projects must contain only encrypted files below `secrets/`, a
valid `secrets.nix`, and no plaintext secret values. The invoking user's
devenv allow list must remain unchanged.

## Rollback

Revert the implementation commits for this issue. The catalogue entries and
scaffold changes are additive; existing templates remain available and no
machine-wide NixOS or user secret state is modified.
