---
status: approved
issue: 14
author: olafkfreund
---

# Intent: no status poll runs once every surface is closed

Closes #14.

## Problem

AGENTS.md: "Nothing polls while every surface is closed. The bar's slow poll
for the glyph is the only exception."

Two exit handlers in the state singleton restart the status debounce timer
unconditionally, with none of the open-surface guard that every other
post-mutation refresh in the same file uses. If the user triggers an action —
stopping an environment, starting one, allowing or revoking — and then closes
the panel or menu before the process exits, the timer fires anyway and a
`nixarchy-devenv status` process is spawned three hundred milliseconds later
with nothing on screen.

The effect is bounded: one stray invocation per action that was in flight when
the surface closed, not a runaway timer. It is a real gap in a stated
invariant rather than a performance problem, and the fix is the guard that is
already used a few lines away.

## Proposed outcome

- No process is spawned by the status path once both surfaces are closed.
- The guard matches the one already used by the refresh calls in the same
  handlers, so the file has one consistent rule rather than two.

## Affected users and systems

Anyone who closes the panel or menu while an action is still running. Touches
`DevenvState.qml` only. No CLI, no packaging, no user-visible UI change.

## Constraints

- The bar's slow glyph poll stays as the documented exception.
- Listing must keep working normally while a surface is open; this must not
  make the status display lazier than it is today.
- The keep-loaded rule is unchanged: reopening a surface must still produce a
  fresh status for the selected row.
- QML stays drawing and wiring; no logic moves out of `Model.js`.

## Open questions

1. Should the guard suppress the restart entirely, or record that a status is
   owed so it is fetched on the next open? Suppressing is the smaller change;
   recording avoids a stale status on reopen — though the existing reset path
   may already cover that.
2. This is a two-line change to one file. It is arguably exempt from the full
   artifact chain under the AGENTS.md exemption for one-line config changes.
   Confirm whether the spec and plan stages are wanted, or whether approving
   this intent is enough to implement.
