---
status: approved
issue: 65
author: olafkfreund
---

# Intent: load the menu view on first open (drop keepLoaded)

Part of olafkfreund/nixos_config#3107. The full, reviewed intent is
[intent/2026-11-19-3107-shell-startup.md][full] in nixos_config; this record
carries the part that applies to `nixarchy.devenv`.

[full]: https://github.com/olafkfreund/nixos_config/blob/perf/3107-shell-startup/intent/2026-11-19-3107-shell-startup.md

## Problem

`keepLoaded: true` makes the shell build this view at every start and keep
it all session, adding work to the shell's main thread during startup.

## Proposed outcome

The view loads on first open. Every keybind and menu row still opens it,
and nothing running is lost when it unloads.

## Decisions

Artifacts pre-approved by the owner on 2026-11-19 for nixos_config#3107
("review and research and implement").
