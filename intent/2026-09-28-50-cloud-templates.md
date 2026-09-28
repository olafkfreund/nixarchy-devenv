---
status: approved
issue: 50
author: olafkfreund
---

# Intent: Cloud infrastructure templates

## Problem

The plugin currently offers one generic cloud generator, but users working with
AWS, GCP, and Azure need separate starting environments. A generic cloud
template does not make the provider CLI, Terraform workflow, Kubernetes tooling,
and provider-specific operational tools immediately available or explain which
provider the project targets.

## Proposed outcome

The create form and `nixarchy-devenv` CLI offer separate `aws`, `gcp`, and
`azure` templates. Each provides a practical provider-specific environment for
managing cloud infrastructure with Terraform and Kubernetes, including
formatting, validation, linting, and security-oriented tooling where it is
appropriate and supportable by devenv.

The templates remain credential-free: authentication is performed by the user
through the provider's supported local or federated mechanisms. Every template
is checked with a real devenv before release and is documented in the user
guide and README.

The generated environment also exposes documented shell helpers for adding,
editing, and deleting encrypted secrets, plus adding authorized users and
rekeying the encrypted secrets for the new recipient set. Helpers must keep
secret values out of command history and logs and leave changes reviewable in
Git.

## Affected users and systems

- Users creating projects from the nixarchy-devenv menu or CLI.
- `data/templates.nix` and the CLI catalogue/package generation.
- `templates-check` and its real-devenv validation path.
- README and `docs/usage.md`.

## Constraints

- Add the shared catalogue entries here; do not recreate them in nixarchy.
- Keep each provider as a separate template rather than hiding provider choice
  behind a new form abstraction.
- Use ordinary devenv option lines and existing template fields where possible.
- Do not read, generate, or persist credentials, tokens, or secret files.
- Every template family must provide a documented encrypted-secret path using
  SOPS and/or agenix, with SecretSpec used where devenv environment-variable
  contracts are appropriate; secrets remain runtime-only during evaluation.
- Include common Terraform and Kubernetes tools only when they are useful across
  providers; avoid turning each template into an unbounded tool collection.
- Follow current official guidance: Terraform formatting and validation, the
  provider CLIs, and provider-supported Kubernetes access tooling.
- Run the repository checks plus `nix run .#templates-check` for the new
  templates before implementation is considered complete.

## Open questions

- Which provider-specific security and policy tools have stable nixpkgs/devenv
  packages and should be included in the first version?
- Should Kubernetes tooling be limited to `kubectl` and the provider's cluster
  helper (`eksctl`, `gcloud`, or `az`), or should Helm and a manifest linter be
  included too?
- Should the templates remain presets, or should any provider need a generator
  because it must create starter Terraform files or additional project files?
- Should the shared encrypted-secret scaffold live in the existing cloud
  generator repository and be reused by all richer templates, or should this
  plugin add a smaller common generator of its own?
- Should the helpers target agenix only, SOPS only, or expose one stable command
  surface with backend-specific implementations?
