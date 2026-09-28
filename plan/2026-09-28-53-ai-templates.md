---
status: approved
issue: 53
spec: spec/2026-09-28-53-ai-templates.md
---

# Plan: Add local and hosted AI templates

Implement the approved AI template design: two built-in presets, a safe
`shellPackages` catalogue field that extends `devenv init`'s existing package
list, shared agenix secrets, documentation, and focused validation.

## Steps

1. `pkgs/cli.nix`, `data/templates.nix`, and `pkgs/templates-check.nix`: add
   optional `shellPackages` rendering and validation, then define `local-ai`
   with Python/uv, local inference and hardware tools, and `ai-providers` with
   Python/uv plus curl/jq. Verify with focused template scaffolding and inspect
   the generated `devenv.nix` package lines.
2. `tests/cli.sh`: add the smallest fixture assertions for the two IDs and the
   generated shell package fragments. Verify the CLI test suite passes with
   stubbed external commands.
3. `README.md` and `docs/usage.md`: document the AI templates, provider SDK
   installation boundary, GPU/driver and model-service boundary, and existing
   agenix secret helpers. Verify links and wording against the generated
   template notes.
4. Run the complete checks, review the diff against this plan, and commit each
   implementation step with the issue number. Push the branch and open a PR
   linking intent, spec, and plan with `Closes #53`.

## Tests

```bash
node --test 'tests/model/*.test.js'
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
nix flake check --all-systems --no-build
nix run .#templates-check local-ai ai-providers
```

The focused template check must report both projects scaffolded and evaluated,
with encrypted-only secret files and an unchanged real devenv allow list. The
full template check must also continue to pass before the PR is opened.

## Rollback

Revert the implementation commits on the feature branch. This removes the two
catalogue entries and the optional package-rendering path while leaving the
approved intent, spec, and prior template releases intact.
