---
status: draft
issue: 14
intent: intent/2026-09-24-14-polling-guard.md
---

# Spec: no status poll runs once every surface is closed

## Design

Add the same open-surface guard used everywhere else in `DevenvState.qml` to
the two unconditional `statusDebounce.restart()` calls that lack it:

- `actionProcess.onExited`, `DevenvState.qml:375` —
  `if (verb.indexOf("processes") !== -1) { root.status = null; statusDebounce.restart() }`
- `downProcess.onExited`, `DevenvState.qml:386-387` —
  ```
  root.status = null
  statusDebounce.restart()
  ```

Both become:

```qml
if (verb.indexOf("processes") !== -1) {
  root.status = null
  if (root.active || root.background) statusDebounce.restart()
}
```

```qml
root.status = null
if (root.active || root.background) statusDebounce.restart()
```

This is character-for-character the guard already used two lines below in
`actionProcess.onExited` (`if (root.active || root.background) root.refresh()`,
line 376) and in `streamProcess.onExited` (line 400). No new property, no new
function — the fix makes the file's one rule ("nothing polls while every
surface is closed") apply uniformly to every post-mutation refresh instead of
three out of four.

`root.status = null` stays unconditional in both handlers: it clears a
possibly-stale process table from view even if nothing is currently drawing
it, and costs nothing (no process, no timer).

### Suppress, or record an "owed" status for next open?

Suppression alone is correct. Traced both reopen paths that exist in this
repo — a plain reopen and an IPC/menu-payload reopen with an explicit path —
and both already produce a fresh status fetch independent of whatever the
debounce was doing at close time:

**Plain reopen** (`Panel.qml:48-56` `onOpenedChanged`, `Menu.qml:63-72`
`open()`): both call `DevenvState.acquire("view")` then `view.reset()`.
`DevenvView.reset()` (`DevenvView.qml:88-100`) unconditionally sets
`cursorActive = false; cursorKey = ""`. If the surface closed with a row
selected, `cursorKey` was non-empty, so this assignment changes it and fires
`onCursorKeyChanged` (`DevenvView.qml:71-74`):
```qml
onCursorKeyChanged: {
  var env = Model.envByPath(DevenvState.envs, root.cursorKey)
  DevenvState.requestStatus(env && env.hasProcesses ? env.path : "")
}
```
`requestStatus("")` (`DevenvState.qml:162-167`) sets `statusPath = ""`,
`status = null`, and restarts the debounce itself — this is not the debounce
the bug touches, it is the ordinary per-keystroke debounce that `requestStatus`
always owns. On a plain reopen there is no restored selection: `reset()`
leaves the cursor inactive, so there is nothing to show a status for until the
user moves the cursor again. There is no "selected row" to keep fresh here,
so nothing needs to be recorded as owed.

**IPC/menu reopen with a path** (`Panel.qml:71-74` IPC `select`, `Menu.qml:68-70`
`open()` payload `{"path": …}`): both call `view.selectPath(path)` after
`reset()`. `selectPath` (`DevenvView.qml:137-144`) sets `cursorActive = true`
and `cursorKey = String(path || "")` directly. Since `reset()` just cleared
`cursorKey` to `""`, this is always a change from `""` to a real path, so
`onCursorKeyChanged` always fires and calls `requestStatus(path)` — a fresh
fetch for exactly the row the caller asked to land on, again through
`requestStatus`'s own debounce, unrelated to whatever the suppressed restart
in `actionProcess`/`downProcess` would have done.

In both cases the reopen path already drives a correct, independent status
request through `onCursorKeyChanged` → `requestStatus`. Recording "a status is
owed" would duplicate state that `reset()`/`selectPath()` already produce
correctly, for no observable benefit — the constraint "reopening must still
show a fresh status for the selected row" is met by the existing cursor
lifecycle, not by anything the two buggy restarts contribute today. Suppression
is the entire fix.

### `statusProcess.onExited`'s own restart (line 360)

```qml
onExited: function(code) {
  if (forPath !== root.statusPath) { if (root.statusPath) statusDebounce.restart(); return }
  root.status = code === 0 ? Model.parseStatus(statusOut.text) : { state: "unknown", devenv: true, processes: [] }
}
```

Checked whether `statusPath` is cleared when a surface dismisses: it is not.
`Panel.qml`'s `onOpenedChanged` (else-branch, close) calls
`DevenvState.release("view")` and `view.dismiss()`; `Menu.qml`'s `close()`
does the same. `DevenvView.dismiss()` (`DevenvView.qml:147-150`) only closes
the help sheet and the confirm dialog — it never touches `cursorKey`,
`cursorActive`, or `DevenvState.statusPath`. So `statusPath` is left exactly
as it was at the moment of close, same as before this fix.

Definitive answer: this cannot poll or loop after close, and this spec
requires no change to it. Reasoning: this branch only fires a *second*
`statusDebounce.restart()` when the answer that just arrived is for a
*different* path than the one now current (`forPath !== root.statusPath`) —
i.e. the cursor moved while the request was in flight. Moving the cursor is a
keyboard/mouse action inside an open surface; nothing can move it while both
surfaces are closed. So while closed, `root.statusPath` cannot change between
when a `statusProcess` is dispatched and when it exits (dispatch and the only
things that can change `statusPath` — `requestStatus` calls, all reached
through cursor movement or the two now-guarded exit handlers — are unreachable
with no surface open), which means `forPath === root.statusPath` always holds
for a status process that both starts and ends while closed. The mismatch
branch, and its restart, is simply unreachable in that window. It is not a
second bug and needs no guard.

One residual note for completeness, not a defect: if a `statusProcess` is
in flight for `forPath = X` and the surface closes, then a
now-correctly-suppressed `actionProcess`/`downProcess` restart would have
tried to requery the *same* `statusPath` anyway (neither handler changes
`statusPath`, only `root.status` and the debounce) — so even before this fix,
that combination could not have produced a mismatch either. The only way
`statusPath` changes while closed today is through `onCursorKeyChanged`,
which requires a live cursor, which requires an open surface.

## Alternatives rejected

- **Record "status owed" and refetch on next open.** Rejected: the existing
  `reset()`/`selectPath()` cursor lifecycle already refetches status
  correctly for both reopen shapes (see Design). Adding an owed-flag would be
  new state duplicating what the cursor already drives, with no case it
  fixes — pure speculative complexity for a two-line bug.
- **Guard inside `statusDebounce.onTriggered` instead of at each call site.**
  Rejected: the debounce is shared with the legitimate per-keystroke path
  (`requestStatus`, used while a surface is open) and with the
  `statusProcess.onExited` stale-answer retry, both of which must keep firing
  while open regardless of `active`/`background` — gating the timer itself
  would either need to distinguish callers (more code than the fix) or risk
  silently breaking the debounce for the open-surface case it must keep
  serving.
- **Clear `statusPath` on `dismiss()`/`close()`.** Rejected: broader than the
  defect, touches both `Panel.qml` and `Menu.qml`, and changes behaviour the
  intent doesn't ask for (`statusFor()` would start returning null for a path
  that's still valid on next open, undermining "must not make the status
  display lazier while a surface IS open" if a race ever exposed it, and adds
  a rule to reason about elsewhere in the file). The two-call-site guard is
  strictly smaller and self-contained to the actual defect.
- **A single shared helper, e.g. `restartStatusIfOpen()`.** Considered and
  rejected: two call sites, one line each, matching an inline pattern the
  file already repeats three times (`refresh()`'s own callers). A named
  helper for two lines is the abstraction AGENTS.md's "logic goes in
  Model.js, QML stays drawing and wiring" rule would call unnecessary — this
  is wiring, and the file's existing style is to repeat the guard inline.

## Risks

- **None to the mutation lock or the action pipeline.** `root.mutating` is
  `actionProcess.running || streamProcess.running`; this change touches
  neither process's own lifecycle, command, or lock semantics, only what
  happens to the *status* debounce after they exit.
- **None to `polls` observability.** `DevenvState.polls` only counts
  `listProcess` runs (`refresh()`, line 128); it does not count status
  fetches, so this change doesn't affect the one counter `status()`/IPC
  exposes for outside verification. (Status fetches have no counter at all —
  see Verification for how this is checked instead.)
- **Behavioural risk while a surface IS open: none.** The guard is
  `root.active || root.background` — true whenever a view is open or a bar
  holds interest, which is every case where a status display exists to be
  lazy. The two handlers only skip the restart when neither is true, i.e.
  when there is provably nothing on screen to be stale.
- **Risk of leaving a stale `root.status` visible:** none introduced. Both
  handlers still set `root.status = null` unconditionally before the guard,
  so if a surface *is* open, the process table blanks immediately and the
  (now-guarded) restart still fires to refill it. If no surface is open,
  `null` is written to a property nothing reads — inert.

## Verification

This is Quickshell runtime behaviour (process spawns from a live QML
singleton), which cannot be unit-tested from this repo's Node suite —
`tests/run.js` exercises `Model.js` only, and `DevenvState.qml` is
deliberately excluded from that boundary (`Model.js` is "Pure `.pragma
library` with no QML, tested under Node"). Verification has to happen live,
per `AGENTS.md`'s "Verifying live" procedure:

1. Install the built plugin and enable it (`AGENTS.md` steps 1–2).
2. Open a surface, select an environment with processes running (`hasProcesses`
   true) so `requestStatus` has a real path, then trigger an action whose verb
   contains "processes" — `up` ("starting processes of …") or `down`
   ("stopping … "/`downProcess`) — and **close the surface immediately**,
   before the process exits (`down` especially: it is not lock-refused and
   runs even while a mutation is pending, so it's the easier repro; `up`
   needs the panel closed within `actionProcess`'s run time).
3. With both surfaces closed, watch for the stray process the intent
   describes: `watch -n0.2 'ps -eo comm,args | grep "[n]ixarchy-devenv status"'`
   run just before closing, through a few seconds after the action's process
   exits. Before the fix: one `nixarchy-devenv status …` appears roughly 300ms
   after the action exits, with nothing on screen. After the fix: none
   appears.
4. Cross-check with `qs log -i <instance>` over the same window — the `Process`
   for `statusArgv` shows in the log's process/exec tracing if Quickshell logs
   process starts at the configured level; absence corroborates the `ps`
   watch.
5. Regression-check the constraint that this must not make status lazier
   while open: with a surface open, repeat the same action (`up`/`down` on a
   row with processes) and confirm the process table in `EnvList` still
   blanks and refreshes within ~300ms of the action completing, same as
   before this change — the guard's `root.active` branch is exercised, not
   skipped.
6. Regression-check reopen freshness: close mid-action as in step 2, then
   reopen via IPC `select` (`omarchy-shell shell nixarchy.devenv.bar open`
   then `select(path)`, or the menu's `{"path": …}` payload) for the same
   environment, and confirm its process status appears fresh (a
   `nixarchy-devenv status` process for that path runs once, on reopen,
   driven by `selectPath` → `onCursorKeyChanged` → `requestStatus`, per
   Design).

### Is a plan stage worth writing here?

My view: not much. Everything decision-bearing that a plan would normally
carry — which lines change, what the guard reads verbatim, why no new state
is introduced, why the two rejected shapes (owed-flag, `statusPath` clearing)
don't apply — is already fixed by this spec with no remaining choice; a
`plan/` file would restate "edit these two spots, use this exact guard" as a
numbered list without adding a decision. Given AGENTS.md's gate 4 ("No
implementation edits until plan/ is status: approved") and that issue #14 is
tracked, I'd still write the minimal one-step plan for the paper trail and to
let the PR cite a plan step, per the repo's own commit convention — but the
plan's content will just be this design restated as "Step 1: apply the two
guards above; test: the live procedure in Verification." Deciding to skip it
under the AGENTS.md one-line-config exemption instead is defensible too; that
call belongs to the task owner, not to this spec.
