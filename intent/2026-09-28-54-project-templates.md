---
status: approved
issue: 54
author: olafkfreund
---

# Intent: Add Omarchy plugin and NixOS configuration templates

## Problem

The catalogue has language, web, cloud, and AI starting points, but no useful
project starters for the two Nixarchy-adjacent workflows this plugin serves:
building an Omarchy plugin and maintaining a NixOS configuration. Users must
manually reconstruct the expected repository layout, validation commands, and
secret boundaries before they can begin either project.

## Proposed outcome

Add two separately selectable templates, `omarchy-plugin` and `nixos-config`,
that create minimal, independent project structures with the relevant files,
tooling, validation workflow, and documentation. Generated projects should be
usable outside this plugin and clearly identify what remains machine-specific
or project-specific.

## Affected users and systems

- Users creating Omarchy plugin projects or NixOS configuration repositories.
- The template catalogue, generator/index contract, and template checks.
- Generated project files, documentation, and lightweight fixture tests.

## Constraints

- The two templates must have separate IDs and remain independent of this
  repository at runtime; they must not import or copy plugin implementation
  code unintentionally.
- The Omarchy template must cover the relevant QML/JavaScript/Lua structure,
  manifest expectations, and lightweight validation/test workflow without
  pretending to implement a complete plugin.
- The NixOS template must cover a flake, host/module layout, formatting, and
  validation tooling without embedding this machine's hosts, hardware, users,
  or credentials.
- Generated projects must use the established agenix secret policy where
  repository secrets are needed, never generate plaintext credentials, and
  never read secrets during Nix evaluation.
- Validation must be hermetic where possible and prove generated projects at
  least scaffold correctly, parse/evaluate, and run their lightweight checks.
- The starting structures must be minimal, readable, and maintainable without
  requiring the generated project to depend on nixarchy-devenv.

## Open questions

- Should each template be an external pinned generator, a local generator
  implementation, or a preset plus generated files?
- Which Omarchy plugin files and validation commands are the smallest useful
  stable baseline?
- Which NixOS flake layout and validation commands should be the default while
  remaining usable across machines and NixOS release pins?
