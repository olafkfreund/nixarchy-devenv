---
status: approved
issue: 50
spec: spec/2026-09-28-50-cloud-templates.md
---

# Plan: Cloud infrastructure templates

Implement three provider-specific cloud generators while keeping the plugin's
catalogue small and making the generated project the owner of tools and secret
files.

## Steps

1. `olafkfreund/cloud-projects-templates`: add the agenix project layout,
   credential-free helper commands for adding/editing/deleting secrets and
   adding users, recipient rekeying, ignore rules, documentation, and refusal
   tests. Verify helper `--help`, malformed-name, unsafe-path, and malformed-key
   cases without credentials.
2. `data/templates.nix`: add `aws`, `gcp`, and `azure` generator entries using
   the released cloud-generator revision, each with one provider and notes that
   name the tool and agenix workflow. Keep `cloud` unchanged. Verify catalogue
   evaluation and system filtering.
3. `pkgs/templates-check.nix`: select the first provider declared by each
   generator instead of always passing `aws`. Verify all three generators are
   scaffolded with their matching provider.
4. `tests/cli.sh`: assert the three entries, provider metadata, and generator
   argv behaviour. Update expected counts and the provider-aware templates
   check. Verify with the stub CLI tests.
5. `README.md` and `docs/usage.md`: document the three entries, their tool
   coverage, credential boundary, and secret helper commands. Verify links and
   examples remain consistent with the catalogue.
6. Run the complete checks and inspect the generated project contents:
   `node --test 'tests/model/*.test.js'`, `nix flake check`, the CLI test, and
   `nix run .#templates-check aws gcp azure`.

## Tests

- The external generator's helper and generated-project tests pass without real
  credentials.
- `nixarchy-devenv templates --json` reports `aws`, `gcp`, and `azure` as
  generators with exactly one matching provider each.
- The three generated projects contain only encrypted secret files and expose
  the helper commands.
- All existing model, CLI, flake, and plugin checks pass.
- The real templates check does not alter the invoker's devenv allow list.

## Rollback

Revert the generator revision pin and the catalogue/test/documentation commits.
The generic `cloud` entry remains the fallback. Do not delete generated user
projects or encrypted secret files as part of rollback.
