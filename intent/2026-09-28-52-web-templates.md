---
status: approved
issue: 52
author: olafkfreund
---

# Intent: Frontend and backend web templates

## Problem

The template catalogue has language and cloud starting points, but no distinct
web-development starting points. Users must choose a language template without
guidance for browser-facing work or general backend services, and a single
generic web template would hide important differences in those workflows.

## Proposed outcome

Users can select separate `frontend` and `backend` templates from the plugin or
CLI. Each creates a small, valid devenv baseline that evaluates with real
devenv, is clear about what it includes and what users add next, and follows
the shared encrypted-secret workflow required for generated environments.

## Affected users and systems

- Users creating projects through the plugin, `nixarchy dev`, or
  `nixarchy-devenv`.
- The built-in template catalogue, CLI index, template checks, and user
  documentation.
- Existing language, cloud, personal, and mobile templates must remain
  unchanged in behavior.

## Constraints

- Keep frontend and backend as separate selectable templates.
- Keep the baseline small; do not install every framework or service.
- Use devenv-supported options and verify them against a real devenv.
- Include the shared agenix-compatible encrypted-secret scaffold without
  placing plaintext values in generated Nix.
- Do not add machine-wide packages or system configuration.
- Preserve the existing catalogue rules: no duplicate `packages` assignment,
  no unsafe shell interpolation, and no automatic activation consent.

## Open questions

- Which frontend formatter/linter and browser-development baseline are stable
  enough for the default template?
- Should the backend baseline remain language-neutral, or choose the existing
  Node/Python modules as its smallest useful implementation?
