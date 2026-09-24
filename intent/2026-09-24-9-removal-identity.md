---
status: approved
issue: 9
author: olafkfreund
---

# Intent: removal verifies the directory's identity, and verifies it last

Closes #9, #10, #11.

## Problem

`nixarchy-devenv remove` deletes project directories. AGENTS.md states that the
CLI performs the authoritative checks "immediately before it deletes", and that
one of them is that the directory is "unchanged since it was confirmed". Three
separate defects mean that guarantee does not hold today. All three were found
in a cross-model review and reproduced.

**The identity check does not identify anything (#9).** The freshness guard
compares `stat -c %d`, which is the *filesystem's* device number. Every
directory on the same disk shares it, so the check only catches a change of
mount point. A user can confirm removal of one project and have a different
project deleted: list `proj-A`, then an ordinary `mv` in another terminal puts
`proj-B` at that path, then confirm — exit 0, `proj-B`'s code is gone. No
attacker and no race is required; a stale panel row is enough, and the list is
polled. `list` already computes an `mtime` it never uses as a guard.

**The root guard can be switched off silently, by two routes (#10).** In
`Model.js`, `rootArgs` returns an empty array for an empty root list, and an
empty array is truthy, so the `if (!r) return null` guard never fires and the
command is built with no `--root` arguments at all. Reachable because the
listing draws candidates from devenv's allow file regardless of configured
roots. Separately, the CLI accepts an empty `--root` value and then discards it
without a word, where the listing command refuses the same input. Both were
reproduced by deleting a directory that had been passed as a project root. Both
fail open.

**The checks are not immediately before the delete (#11).** Between the last
check and `rm -rf` the command runs `devenv processes list` under a ten-second
timeout and then `devenv revoke`. With a stalling stub, swapping an ancestor
directory for a symlink inside that window redirected the delete into another
tree.

These are pre-existing and independent of the dead-code work on #8.

## Proposed outcome

- Confirming removal of a project and having a *different* directory deleted is
  refused, including when the swap happens after the confirmation.
- The root guard cannot be disabled by an empty or unresolvable root: such
  input is refused rather than ignored, in the command that deletes as well as
  the one that lists.
- The identity check is the last thing that happens before the delete, not the
  first of several seconds of subprocess work.
- Each new refusal is covered by a filesystem test, and the `Model.js`
  pre-check by a Node test, per the existing AGENTS.md rules.

## Affected users and systems

Anyone using the plugin's remove action or the `nixarchy-devenv remove`
command, on any host. `pkgs/cli.sh` owns the authoritative checks;
`Model.js` builds the argv and holds the pre-checks; `tests/cli.sh` and
`tests/model/` hold the proofs. No QML surface changes.

## Constraints

- The authoritative checks must stay in the CLI, immediately before the delete.
  `Model.js` pre-checks remain advisory, per AGENTS.md.
- Must not weaken any existing refusal, and must keep the tier boundaries:
  `.envrc` is never removed, and the `files` tier keeps `.devenv/state`.
- Refusals must fail closed. Anything the command cannot verify is a refusal,
  never a silent skip.
- Argv arrays only, no `sh -c`.
- Every refusal needs a filesystem test; every `Model.js` pre-check needs a Node
  test.

## Open questions

1. `list` already computes `mtime` and discards it. Should the freshness guard
   use device plus inode only, or also carry `mtime`? Device plus inode is
   sufficient to refuse every case reproduced here; `mtime` would additionally
   catch in-place edits, at the cost of refusing a removal after any touch of
   the directory.
2. An unresolvable root (a root on an unmounted drive) currently skips the
   guard. Refusing the whole removal is the fail-closed reading, but it makes
   removal impossible while any configured root is offline. Refuse, or warn and
   continue?
3. Should this land as one PR closing all three issues, or as #9 plus #11 in
   one PR (they are a single edit) and #10 separately?
