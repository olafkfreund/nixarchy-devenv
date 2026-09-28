---
status: draft
issue: 50
intent: intent/2026-09-28-50-cloud-templates.md
---

# Spec: Cloud infrastructure templates

## Design

Add three `generator` entries to `data/templates.nix`: `aws`, `gcp`, and
`azure`. Each entry reuses the existing pinned
`olafkfreund/cloud-projects-templates` generator and declares exactly one
provider. The generic `cloud` entry remains available for projects combining
providers.

The generator source becomes the owner of the generated cloud project and its
secret workflow. Its common output provides Terraform, TFLint, Trivy,
Terraform Docs, Kubernetes tooling, and provider-specific CLIs. The generated
project also contains an agenix-based encrypted secret layout suitable for
devenv:

- `secrets.nix` declares encrypted files and authorized public keys.
- `secrets/*.age` contains ciphertext only.
- devenv reads decrypted values at runtime through explicit file paths or
  environment setup; Nix evaluation never reads secret contents.
- Git ignores plaintext and generated report material while allowing encrypted
  files and the recipient declaration to be reviewed.

The generated environment exposes one stable shell-helper surface:

- `secret-add NAME`: create a new encrypted secret without accepting a secret
  value as a command-line argument.
- `secret-edit NAME`: decrypt to agenix's controlled editor flow and re-encrypt
  on save.
- `secret-delete NAME`: require an exact validated secret name, remove its
  ciphertext and recipient declaration, and show the Git diff for review.
- `secret-user-add PUBLIC_KEY [LABEL]`: validate an SSH public key, add it to
  the recipient set, and rekey all encrypted secrets with `agenix -r`.

The helpers print credential-free help, never echo secret values, reject path
traversal and malformed recipients, and do not make cloud API calls. The
external generator's revision must be bumped to the commit containing this
workflow before the three plugin entries are enabled.

The plugin changes remain small: catalogue entries, provider-aware template
checking, CLI test fixtures, and user documentation. The existing form and
generator argv contract are reused.

## Alternatives rejected

- **Implement secret helpers in this plugin's QML or CLI:** rejected because
  the plugin does not own generated project files and secret operations belong
  beside the generated `secrets.nix` and agenix layout.
- **Use SOPS and agenix as two independent backends in the first version:**
  rejected as duplicate command surfaces. Agenix is the initial backend because
  the existing cloud generator already uses it; SOPS can be added behind the
  same helper contract later if a concrete template needs it.
- **Pass secret values through helper arguments or shell strings:** rejected
  because values can leak through history, process listings, and logs.
- **Turn the three entries into presets:** rejected because presets cannot
  safely add the generated multi-file secret and cloud-tool scaffold.

## Risks

- The plugin and generator repositories must be updated together; an old
  pinned revision will not provide the new helper contract.
- Agenix requires a user's SSH/age identity and recipient setup; the template
  can guide setup but cannot create or distribute trust keys.
- Rekeying all secrets changes many ciphertext files at once and must remain an
  explicit user action with a reviewable diff.
- Provider CLIs and Kubernetes tools increase closure size and still require
  separate provider authentication.

## Verification

- Validate the generator's agenix helpers with credential-free `--help` and
  refusal tests for bad names, paths, and public keys.
- Generate each provider project without credentials and confirm the encrypted
  layout, ignored plaintext paths, and helper commands.
- Run `nix run .#templates-check aws gcp azure` after pinning the generator.
- Run `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`.
- Run `node --test 'tests/model/*.test.js'` and `nix flake check --no-build`.
