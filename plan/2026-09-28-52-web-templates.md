---
status: draft
issue: 52
spec: spec/2026-09-28-52-web-templates.md
---

# Plan: Frontend and backend web templates

Add two small Node/TypeScript presets. Both use devenv's language modules,
script-local formatter/linter packages, and the existing shared agenix secret
scaffold. Neither generates framework files, a package manifest, a database, or
a process that would fail before the user adds an application.

## Steps

1. `data/templates.nix`: add `frontend` and `backend` preset entries with
   `secretScaffold = true`, JavaScript/npm and TypeScript options, `format` and
   `lint` scripts using `pkgs.prettier` and `pkgs.eslint`, and notes describing
   the intended next framework choices → verify the catalogue evaluates.
2. `tests/cli.sh`: assert both entries, their secret-scaffold metadata, script
   definitions, and absence of a second top-level `packages` assignment in a
   generated project → verify the stub CLI suite.
3. `README.md` and `docs/usage.md`: add the two templates to the catalogue and
   explain the framework-neutral scope, formatter/linter commands, and shared
   encrypted-secret workflow → verify the documented IDs match the catalogue.
4. `pkgs/templates-check.nix` or its invocation coverage, only if required by
   the new entries: ensure both presets are included in real devenv checks and
   the allow-list isolation remains intact → verify both generated projects
   evaluate.

## Tests

```bash
node --test 'tests/model/*.test.js'
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
nix flake check --all-systems --no-build
nix run .#templates-check frontend backend
```

Generated projects must contain the shared `secrets.nix` and encrypted-only
`secrets/` directory, expose `format` and `lint`, and retain devenv's original
single `packages` assignment.

## Rollback

Revert the implementation commits for issue #52. This removes only the two
catalogue entries, their tests, and documentation; existing templates and
project secret state are unaffected.
