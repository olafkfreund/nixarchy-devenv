---
status: draft
issue: 6
author: olafkfreund
---

# Intent: the menu stays open after revoking a bound environment

Closes #6.

## Problem

Revoking a bound environment (#4) from the full-screen menu works: the binding
leaves devenv's `allowed` file and the row leaves the list. But about 3 seconds
later, the menu closes by itself. Nobody pressed Esc, clicked the backdrop or
toggled it. Nothing appears in `qs log`.

It happened on both scripted runs on razer on 2026-09-21, and not in these
controls:

- revoking a **local** row the same way leaves the menu open (polled every
  0.25 s for 8 s);
- with no input, the menu stays open (polled every 0.5 s for 60 s).

The difference: a revoked bound row **disappears** from the list, and under a
filter the list becomes empty ("Nothing matches that filter"). A revoked local
row stays, as not allowed. So the trigger is likely "the cursor's row was
removed from the list", which until #4 only happened when a project directory
vanished. Bound rows make it routine.

The cause is not known yet. Nothing in `DevenvView.qml` or `Menu.qml` closes
the surface on a refresh. The only closers are the toggle, a scrim click, Esc
in the list, and enter/edit. So either one of those fires indirectly (for
example, focus falling to `keyCatcher` with no rows, or a list reconcile
destroying the focused item), or the host closes an `Exclusive` layer.

## Proposed outcome

- After revoking a bound environment, the menu stays open on the list, with
  the row gone and focus in a sensible place. A surface only closes when the
  user closes it.
- The same holds for any row that leaves the list while the menu is open,
  such as a directory deleted from outside.
- The cause is found and written down, and a test covers whatever part of it
  is logic (`Model.js`).

## Affected users and systems

- Users of bound environments, and anyone whose listed directory vanishes
  while the menu is open.
- Probably `DevenvView.qml` and/or `EnvList.qml`, and `Model.js` if the cursor
  or reconcile logic is at fault. The bar popup (`Panel.qml`) is to be
  checked for the same behaviour.

## Constraints

- Keep-loaded surface rules (AGENTS.md): `open()` resets and focuses the final
  mode. Nothing may touch the stream or the log.
- The fix must not change what revoke does, or the one-mutation-at-a-time lock.
- Live verification per AGENTS.md "Verifying live", with `docs/capture.sh`'s
  `demo-bound`. Check the layers before every `wtype`. And in any scripted
  check, **never** pipe `hyprctl` into `grep -q` under `pipefail`: that gave
  false "menu closed" readings during #4.

## Open questions

1. Is the bar popup affected too? This is to be established while diagnosing,
   not assumed.
