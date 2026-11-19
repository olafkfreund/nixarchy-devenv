---
status: approved
issue: 65
spec: spec/2026-11-19-65-no-keeploaded.md
---

# Plan: load the menu view on first open (drop keepLoaded)

Part of olafkfreund/nixos_config#3107. The full, reviewed plan is
[plan/2026-11-19-3107-shell-startup.md][full] in nixos_config; this record
carries the part that applies to `nixarchy.devenv`.

[full]: https://github.com/olafkfreund/nixos_config/blob/perf/3107-shell-startup/plan/2026-11-19-3107-shell-startup.md

## Steps

1. `manifest.json`: drop `keepLoaded`; fix comments, docs and the flake
   manifest check that asserted it.
   → verify: `jq -e 'has("keepLoaded")|not' manifest.json`; flake checks.

## Rollback

Revert the commit.
