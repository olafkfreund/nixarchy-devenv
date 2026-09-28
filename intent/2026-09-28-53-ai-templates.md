---
status: approved
issue: 53
author: olafkfreund
---

# Intent: Add local and hosted AI templates

## Problem

The catalogue has no distinct environments for local AI development and hosted AI provider development. Users currently have to assemble a generic Python or machine-learning environment themselves, without a clear boundary between local inference tooling, provider SDK work, hardware setup, and credentials.

## Proposed outcome

Add two selectable templates, `local-ai` and `ai-providers`, that provide small, valid devenv starting points for their respective workflows. Each template will document its hardware or provider-specific boundaries, remain evaluable in the template checks, and use the repository's runtime-managed encrypted secret workflow without creating credentials or starting services automatically.

## Affected users and systems

- Users creating AI projects from the plugin catalogue.
- The template catalogue, generated template index, and preset checks.
- Documentation and tests covering template contents and secret handling.

## Constraints

- `local-ai` must provide a Python/uv baseline and practical local inference or model tooling without forcing a heavyweight model service, downloading model weights, or changing machine-wide GPU configuration.
- `ai-providers` must provide an SDK-oriented environment; provider CLIs or additional tools must be included only where they have a clear project-level purpose.
- Both templates must keep credentials user-managed at runtime through the existing agenix secret policy. No API keys, tokens, plaintext secrets, automatic activation, or service startup may be embedded in a template.
- Template definitions must follow the catalogue's preset rules and pass the real `templates-check` validation.
- Keep the implementation minimal and reuse the existing shared secret scaffold, catalogue, and test paths.

## Open questions

- Which local inference and GPU-adjacent command-line tools are useful enough to include without making the template heavyweight?
- Which hosted provider SDKs should be covered by the baseline, and which provider-specific tools should remain user additions?
