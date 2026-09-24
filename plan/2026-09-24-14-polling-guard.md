---
status: draft
issue: 14
spec: spec/2026-09-24-14-polling-guard.md
---

# Plan: no status poll runs once every surface is closed

Two exit handlers in `DevenvState.qml` restart `statusDebounce` unconditionally
after a mutation, unlike every other post-mutation refresh in the file, which
checks `root.active || root.background` first. If a user triggers an action
and closes the panel/menu before the process exits, the timer still fires and
spawns a stray `nixarchy-devenv status …` ~300ms later with nothing on screen.

Approved decisions carried from the spec (already approved, no open
decisions remain):

- Guard both restarts with the exact same condition already used by the
  `root.refresh()` calls beside them: `if (root.active || root.background)`.
- Suppression only — no "owed status" bookkeeping. Both reopen paths
  (plain reopen via `reset()`, and IPC/menu reopen via `selectPath(path)`)
  already change `cursorKey` and trigger `onCursorKeyChanged` →
  `requestStatus()`, which re-fetches status independently through its own
  debounce. There is nothing for an owed-flag to fix.
- `statusProcess.onExited`'s own restart (line 361, the stale-answer retry)
  is untouched. It cannot fire while both surfaces are closed: the only way
  `root.statusPath` changes is `onCursorKeyChanged`, which requires a live
  cursor, which requires an open surface. It is unreachable in the closed
  window and needs no guard.
- `statusPath` is not cleared on dismiss/close. Out of scope — broader than
  the defect and rejected in the spec.
- `root.status = null` stays unconditional in both handlers: it costs
  nothing when nothing is drawing it, and still blanks the process table
  immediately when a surface is open.
- No shared helper function: two call sites, one line each, matching the
  file's existing style of repeating the guard inline (AGENTS.md: QML stays
  wiring, logic lives in `Model.js`).

## Steps

Re-verified against main at `e254c82` (post-#8, which touched this same file
but only removed unread state and dead handlers — it did not add a shared
guard helper and did not touch either of these two call sites; both
unconditional restarts are still present, unchanged except for a one-line
shift from #8's earlier deletions). No rebase of the fix itself is needed,
only of the line numbers below.

1. `DevenvState.qml:376`, `actionProcess.onExited` — change

   ```qml
   if (verb.indexOf("processes") !== -1) { root.status = null; statusDebounce.restart() }
   ```

   to

   ```qml
   if (verb.indexOf("processes") !== -1) { root.status = null; if (root.active || root.background) statusDebounce.restart() }
   ```

   → verify by reading the line back: the guard is character-for-character
   the one on the very next line, `377` (`if (root.active || root.background)
   root.refresh()`).

2. `DevenvState.qml:387-388`, `downProcess.onExited` — change

   ```qml
       root.status = null
       statusDebounce.restart()
   ```

   to

   ```qml
       root.status = null
       if (root.active || root.background) statusDebounce.restart()
   ```

   → verify by reading the line back against the same guard used in step 1
   and at line 156 (`onRootsChanged: if (root.active || root.background)
   refresh()`).

No other file changes. `statusProcess.onExited` (line 361) and
`streamProcess.onExited` (line 401) are read but not touched. #8 introduced
no shared guard helper or property anywhere in this file — every guarded
call site (156, 377, 401, and the two new ones) still repeats the same
inline `if (root.active || root.background)` condition, so this plan's
"no shared helper" decision needs no revisiting.

## Tests

Quickshell runtime behaviour (a live `Process` spawned from a QML singleton)
is not unit-testable from this repo's Node suite: the Model tests exercise
only `Model.js`, and `DevenvState.qml` is deliberately outside that boundary.
Verification is live, per AGENTS.md's "Verifying live":

Automated suites that must still pass unchanged (no behaviour of theirs is
touched by this diff, run to confirm no regression; `tests/run.js` no longer
exists post-#8 — use the current commands):

```bash
node --test 'tests/model/*.test.js'            # currently 70 pass
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"   # currently 63 passed
nix flake check
```

Live check (the actual fix verification):

1. Install and enable the built plugin (AGENTS.md steps 1–2: rebuild, copy
   into `~/.config/omarchy/plugins/nixarchy.devenv`, `rescanPlugins`, enable,
   `omarchy-restart-shell`, wait for `omarchy-shell shell ping`).
2. Open a surface, select an environment with `hasProcesses: true`, trigger
   `down` on it (easiest repro — not lock-refused, runs even mid-mutation),
   and close the surface (panel or menu) immediately, before `downProcess`
   exits.
3. Before closing, start watching for the stray process:
   ```bash
   watch -n0.2 'ps -eo comm,args | grep "[n]ixarchy-devenv status"'
   ```
   Before the fix: one `nixarchy-devenv status …` process appears ~300ms
   after `downProcess` exits, with both surfaces closed. After the fix: none
   appears.
4. Cross-check the same window with `qs log -i <instance>` (get `<instance>`
   from `qs list --all`) — no `statusArgv` process trace should appear after
   close.
5. Regression, open case: repeat the same `down` action with a surface left
   open; confirm the `EnvList` process table still blanks and refreshes
   within ~300ms of the action completing (the `root.active` branch must
   still fire, not be skipped).
6. Regression, reopen freshness: close mid-action as in step 2, then reopen
   via IPC `select` (`omarchy-shell shell nixarchy.devenv.bar open` then
   `select(path)`) or the menu's `{"path": …}` payload for the same
   environment; confirm a fresh `nixarchy-devenv status` process runs once
   for that path, driven by `selectPath` → `onCursorKeyChanged` →
   `requestStatus`.

## Rollback

Revert the two one-line guards (`git revert` the commit, or drop the
`if (root.active || root.background)` wrapper back to the unconditional
`statusDebounce.restart()` at both sites). No state, schema, or lockfile
changes are involved, so rollback is the diff alone.
