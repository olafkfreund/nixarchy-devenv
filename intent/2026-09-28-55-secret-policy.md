---
status: approved
issue: 55
author: olafkfreund
---

# Intent: Standardize encrypted secrets across templates

## Problem

The catalogue now contains cloud, language, and web templates, but their
secret-management behavior is not governed by one documented policy. Some
generated projects use an agenix-compatible scaffold while other template
families still need an explicit choice for encrypted files, runtime exposure,
recipient ownership, rotation, and helper safety. Future AI, Omarchy, and NixOS
templates could otherwise introduce incompatible or unsafe secret workflows.

## Proposed outcome

Every built-in or generated project template declares one supported secret
workflow and provides a short, auditable path for adding, editing, deleting,
using, rotating, and sharing secrets. Repository secrets remain encrypted,
plaintext values never enter generated Nix or evaluation, and users can tell
which values are exposed only at runtime and which files are safe to commit.

## Affected users and systems

- Users creating any built-in, cloud-generator, or future personal-compatible
  project template.
- `data/templates.nix`, the preset CLI scaffold, cloud generator integration,
  template checks, helper tests, and user documentation.
- Cloud, language, web, AI, Omarchy, and NixOS template families.

## Constraints

- Use SOPS and/or agenix for encrypted repository secrets, and use devenv's
  SecretSpec where an environment-variable or application-secret contract is
  the better fit.
- Never generate credentials, evaluate plaintext secrets, or place secret
  values in the Nix store, logs, command arguments, or committed plaintext.
- Helpers must validate names, paths, and recipients; refuse unsafe deletion;
  support recipient/user addition followed by rekeying; and leave auditable
  Git changes.
- Keep the smallest reusable implementation possible and preserve existing
  template creation, consent, and hermetic-check behavior.
- Do not require real credentials or machine-wide NixOS changes in tests.

## Open questions

- Should the shared default remain agenix-compatible, or should new and
  existing templates move to SOPS/SecretSpec as the common baseline?
- Which secret contract belongs in the preset CLI and which belongs in the
  external cloud generator?
- What minimum policy metadata must each catalogue entry declare so future
  templates cannot omit secret handling accidentally?
