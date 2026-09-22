---
status: draft
issue: 8
author: olafkfreund
---

# Intent: remove dead and duplicated code

Closes #8.

## Problem

A review of the whole repository for over-engineering (2026-09-22: three
reviewers, and every claim below re-checked by grep) found about 136 lines
that do nothing or do something twice. They are left over from #1, #3 and #4:

- **Dead code.** Two things are called only by their own tests:
  - `Model.removeMessage`: the removal chooser draws `tiersFor(env)[i].text`,
    a gap found live during #4;
  - `Model.templateOrder`: `CreateForm.qml` rebuilds the order in QML.

  Some properties are written and never read: `DevenvState.skipped` and
  `streamName`. `hideWhenEmpty` is pushed into DevenvState's settings, but only
  Panel reads it. There is also an empty `onSwitchPanelRequested` handler in
  `Menu.qml`, and `pkgs/cli.nix`'s `passthru.share`.
- **Duplication.**
  - Two root-argument loops (`listArgv`, `removeArgv`) and three
    find-by-field loops (`templateById`, `envByPath`, `tierById`).
  - The busy guard in `run` and `startStream`.
  - A pending-text string, built in `busyText` and `statusJson`.
  - `refreshIntervalSec` clamped twice.
  - `removeTiers[Math.min(…)]` written twice.
  - `cmd_new` repeats `expand_root`'s `~` expansion.
  - The pacman/yay grep in two flake checks.
  - `templates-check` re-running `templates --json` for each id.
  - The shared fields of the local and bound row builders in `cli.sh`.
- **Hand-rolled code that already exists.**
  - `tests/harness.js` and `tests/run.js` are a test runner that `node:test`
    ships.
  - `sanitize` re-implements a character-class strip and `trim`.
  - The fallback splice in `cli.sh` goes through head, cat, tail and mv where
    one `sed r` does it.
  - `allowed_file()` is a 7-line function with one caller.
- **Small things.**
  - A one-field `lock` object.
  - `EnvList.maxHeight`, which nothing sets.
  - A redundant `width` fallback, and a reset done twice in `closeRemove`.
  - A single-arm `case` in `cli.sh`.
  - `DEVENV_HOME`/`STUB_PROCESSES` set twice in `tests/cli.sh`.
  - A `declare -f` subshell that rebuilds `rm_cli`.
  - `import Quickshell` apparently unused in `DevenvView.qml` and `Panel.qml`.

Each item is small. Together they are code a reader has to understand and a
change has to keep working, for no behaviour at all.

## Proposed outcome

- One PR that removes or collapses the items above. Nothing a user can see
  changes: the same list, actions, messages, CLI output and exit codes.
- `node tests/run.js` (or its replacement) and `tests/cli.sh` pass, with the
  assertions for deleted functions removed and none of the others weakened.
  `nix flake check` and `--all-systems --no-build` pass.
- The plugin still loads and works on a live shell (razer), because QML only
  fails on a missing type or import at runtime.

## Affected users and systems

- Nobody, by design. Developers read less code.
- `Model.js`, `DevenvState.qml`, `DevenvView.qml`, `CreateForm.qml`,
  `EnvList.qml`, `Panel.qml`, `Menu.qml`, `pkgs/cli.sh`, `pkgs/cli.nix`,
  `pkgs/templates-check.nix`, `flake.nix`, and `tests/`. Perhaps AGENTS.md, if
  the test command changes.

## Constraints

- **No behaviour change.** Anything that changes output, messages or exit codes
  is out of scope.
- **Rules that record real failures stay.** Two review findings were dropped
  for this reason:
  - `rowRecord`'s explicit typing, because a ListModel takes its role types
    from the first row;
  - the flake check for symlinks inside the built package, because a check is
    not bloat.

  The removal safety checks in `cli.sh` are not touched.
- **Logic stays in `Model.js` with a Node test** (AGENTS.md). Moving
  `CreateForm`'s template flattening and filtering into Model means a new Node
  test for it, not a deleted one.
- **No new dependencies.** `node:test` ships with Node.

## Decisions

The owner approved this intent on 2026-09-22 with the proposals as written:

1. **The test runner:** replace it with `node:test`, and update the command in
   `flake.nix`, AGENTS.md and the README.
2. **`import Quickshell`:** remove it from `DevenvView.qml` and `Panel.qml`,
   proven by a live load on razer.
3. **`CreateForm.templateChoices`:** move it into a Node-tested
   `Model.templateChoices(templates, filter)`, which replaces `templateOrder`.

## Open questions

None.
