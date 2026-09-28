---
status: draft
issue: 54
spec: spec/2026-09-28-54-project-templates.md
---

# Plan: Add Omarchy plugin and NixOS configuration templates

Implement two local scaffold generators while preserving the existing preset
and external generator contracts. The generated repositories will be
independent, immediately usable file trees with the shared agenix devenv
secret workflow and no machine-specific credentials or configuration.

## Steps

1. `pkgs/scaffold.sh`, `pkgs/cli.nix`, `pkgs/cli.sh`, and
   `data/templates.nix`: add the packaged scaffold assets and the `scaffold`
   catalogue kind. Implement file creation for `omarchy-plugin` and
   `nixos-config`, including their devenv files, README files, validation
   scripts, and shared encrypted-secret scaffold. Verify each scaffold writes
   only inside the destination and refuses an existing file tree.
2. `Model.js` and `tests/model/`: treat `scaffold` as a generator-like
   template for git and allow consent, but omit provider fields and provider
   argv. Add parsing, form, and hostile-input coverage. Verify all model tests
   pass.
3. `pkgs/templates-check.nix` and `tests/cli.sh`: validate scaffold metadata,
   generated file trees, secret helpers, no plaintext secret files, and the
   lightweight `validate` commands. Cover failure cleanup, `--no-git`, and
   `--allow`. Verify the CLI suite and focused template checks pass.
4. `README.md` and `docs/usage.md`: document both templates, generated layouts,
   Omarchy's live validation boundary, NixOS hardware/host review boundary,
   explicit rebuild workflow, and agenix secret ownership. Verify the docs
   match the generated files and commands.
5. Run all checks, review the diff against this plan, push the branch, and open
   a PR linking the approved intent, spec, and plan with `Closes #54`. Merge
   only after the complete validation succeeds.

## Tests

```bash
node --test 'tests/model/*.test.js'
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
nix flake check --all-systems --no-build
nix run .#templates-check omarchy-plugin nixos-config
nix run .#templates-check
```

The focused and full checks must scaffold and evaluate successfully, run the
lightweight project validators, contain only encrypted secret placeholders,
and preserve the invoking user's devenv allow list.

## Rollback

Revert the implementation commits on the feature branch. This removes the
`scaffold` kind and both catalogue entries while preserving the existing
preset, external generator, and secret-policy behavior.
