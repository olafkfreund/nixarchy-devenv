---
status: draft
issue: 9
intent: intent/2026-09-24-9-removal-identity.md
---

# Spec: removal verifies the directory's identity, and verifies it last

## Design

Three changes, one branch. The shape: the list hands removal an **identity
token** instead of a device number; the CLI's target checks become **one
function that runs twice**, the second time as the last statement before the
delete; and the root guard is made impossible to disarm by silence, in the
plugin, in `Model.js` and in `cli.sh`.

### 1. The identity token (#9)

Today `cmd_list` puts `stat -c %d` in each row (`pkgs/cli.sh:391` for ordinary
rows, `pkgs/cli.sh:418` for bound rows) and `cmd_remove` compares it at
`pkgs/cli.sh:511`. A device number names the filesystem, so the check passes
for every directory on the same disk.

Replace it with device **and** inode, carried as one opaque string:

| Where | Now | After |
| --- | --- | --- |
| `pkgs/cli.sh:391` | `--argjson dev "$(stat -c %d "$real")"` | `--arg ident "$(stat -c '%d:%i' -- "$real")"` |
| `pkgs/cli.sh:418` | `--argjson dev "$(stat -c %d "$real")"` | `--arg ident "$(stat -c '%d:%i' -- "$real")"` |
| `Model.js:258` | `dev: typeof r.dev === "number" ? r.dev : -1` | `ident: /^[0-9]+:[0-9]+$/.test(str(r.ident)) ? str(r.ident) : ""` |
| `Model.js:812`, `Model.js:825` | `typeof env.dev !== "number" \|\| env.dev < 0` | `!env.ident` |
| `Model.js:826` | `"--dev", String(env.dev)` | `"--ident", env.ident` |
| `pkgs/cli.sh:486-494` | `--dev`, `[[ $dev =~ ^[0-9]+$ ]]` | `--ident`, `[[ $ident =~ ^[0-9]+:[0-9]+$ ]]` |

Allowlisted at the boundary in the same style as the neighbouring `template`
field (`Model.js:257`): anything that is not `DEV:INO` becomes `""`, and `""`
is a refusal, not a skipped check.

The field is **renamed, not extended**, so that version skew between the
package's plugin and the `nixarchy-devenv` on the shell's PATH fails closed in
both directions:

- new plugin, old CLI → `--ident` hits `pkgs/cli.sh:487`'s `-*)` arm, exit 1,
  nothing touched;
- old plugin, new CLI → `--dev` gets its own arm and an explicit exit 1, rather
  than being quietly accepted. Adding `--inode` alongside `--dev` would instead
  let an old plugin's `--dev`-only call through with no inode check at all.

**`mtime` is not part of the token** (open question 1). Three reasons:

1. It does not catch anything device+inode misses *for this threat*. The threat
   is "a different directory now stands at this path", and a different
   directory has a different inode. An in-place edit of the same directory is
   not an identity change; what protects content there is the tier boundary
   (`.envrc` is never removed, `files` keeps `.devenv/state` —
   `pkgs/cli.sh:535-545`), not freshness.
2. It would refuse ordinary work. The row's `mtime` is `devenv.nix`'s
   (`pkgs/cli.sh:392`); a directory `mtime` would additionally move on every
   file created or deleted inside it, including by `devenv up`. The list polls
   on an interval of at least 10 s (`DevenvState.qml:22`), so between the poll
   the panel drew and the user's confirmation an edit is perfectly likely, and
   the user would get "refresh and try again" on a project nothing happened to.
3. It buys nothing adversarially: second granularity, and settable with
   `touch`.

`mtime` **stays in the row** — it is the list's sort key (`Model.js:379`,
`compareEnvs`). It is simply never a guard.

### 2. One check function, run twice, the second time last (#11)

`cmd_remove` currently runs its checks at `pkgs/cli.sh:496-511`, then spends up
to ten seconds in `cmd_status` (`pkgs/cli.sh:516`, the `timeout` at
`pkgs/cli.sh:447`), then `devenv revoke` (`pkgs/cli.sh:524`), and only then
deletes (`pkgs/cli.sh:529`/`535`).

Lift `pkgs/cli.sh:496-511` verbatim into one function and call it in both
places:

```sh
# Everything that must be true of the target. Pure reads, microseconds. Called
# once up front so a bad request is refused before any subprocess runs, and
# again as the last statement before anything is deleted -- that second call is
# the authoritative one.
verify_target() { ... }   # same refusals, same exit 2
```

Order inside it, unchanged from today except for the last two lines:

1. `--confirm` names `$dir` exactly
2. `realpath -e` resolves, and resolves to `$dir` itself (canonical)
3. not `/`
4. not `$HOME`, and does not contain `$HOME`
5. not a project root, and does not contain one — every `--root`, now
   fail-closed (§3)
6. `$dir/devenv.nix` is a regular file and not a symlink
7. `stat -c '%d:%i' -- "$dir"` equals `--ident`

Check 7 is last because it is the one whose answer can change; checks 2-6 are
re-run with it because the swap the intent reproduced (an ancestor replaced by
a symlink) defeats check 2, not check 7, and re-running the whole set costs
nothing.

New `cmd_remove` body:

```
parse argv; verify_target            # fast, loud refusal
cmd_status  -> stopped / no devenv   # up to 10s
devenv revoke                        # subprocess
verify_target                        # <- authoritative, last statement
rm ...
```

`devenv revoke` stays *before* the final verify. Moving it after would reopen
the window it was moved out of. The consequence — a removal refused at the
final verify may already have been revoked — is harmless (revoke deletes
nothing, the user can re-allow) but must not be silent, so the refusal path
prints one extra line:

```
nixarchy-devenv: $dir was revoked before this refusal; run `devenv allow` there if you still want automatic activation.
```

This narrows the unguarded window from ~10 s of subprocess time to the
microseconds between the final `stat` and `rm`. It does not close it: `rm -rf`
takes a path and resolves it again. The `files` and `state` tiers are already
bounded — `rm -f` on a symlinked `devenv.nix` removes the link, and `find`
(`pkgs/cli.sh:542`) does not follow symlinks — so the residue is the `folder`
tier only. See Risks.

### 3. The root guard cannot be disarmed (#10)

Four holes, each closed where it is:

**(a) `cli.sh` accepts an empty `--root` and discards it.** `pkgs/cli.sh:486`
is `--root) roots+=("${2:-}"); shift ;;`, and the empty string then fails
`realpath` at `pkgs/cli.sh:507` and hits `continue`. Make it match what
`cmd_list` already does at `pkgs/cli.sh:326`:

```sh
--root) [ -n "${2:-}" ] || die 1 "--root needs a directory"; roots+=("$2"); shift ;;
```

**(b) `cli.sh` silently skips an unresolvable root.** `pkgs/cli.sh:507`:
`rc=$(realpath -e -- ... ) || continue`. **Refuse** (open question 2). A root
whose path will not resolve is a root whose relationship to `$dir` is unknown,
and "fail closed" is the stated constraint. The cost the intent worries about —
removal impossible while a drive is offline — does not land on the plugin path,
because `cmd_list` already drops an unreadable root before it is ever reported
(`pkgs/cli.sh:347-350`, which warns and `continue`s, so it never reaches
`$tmp/roots`, `parsed.roots`, or `canonicalRoots`). It bites only someone
invoking the CLI by hand with a stale root list, and the message tells them
exactly which entry to drop.

**(c) The plugin passes the roots that resolved, not the roots configured.**
This is the root cause that makes (b) look safe when it is not: `DevenvState.qml:267`
passes `root.canonicalRoots`, which is `parseList`'s `roots`
(`DevenvState.qml:339`) — that is, exactly the roots `list` managed to resolve.
An offline root disappears from that list, so removal of that very directory
loses its guard *without any refusal firing anywhere*. Fix: pass the configured
roots too. One new readonly property beside `roots` (`DevenvState.qml:26`),
the union of `root.roots` and `root.canonicalRoots`, deduped, used at
`DevenvState.qml:267`. Duplicate `--root` flags are harmless; `removeArgv`
emits one per entry. With this, an offline root reaches the CLI, the CLI cannot
resolve it, and (b) refuses — the chain is closed end to end.

**(d) Zero roots reads as "nothing to protect".** In `Model.js`, `removeArgv`
(`Model.js:821-834`) and `removeRefusal` (`Model.js:799-819`) both treat an
empty roots list as success: the loop at `Model.js:827-831` runs zero times and
the argv is returned with no `--root` at all. Add, in `removeArgv` before the
loop, and mirrored in `removeRefusal`:

```js
if (!list.length) return null   // the root guard lives in the CLI; never call it disarmed
```
```js
if (!(roots || []).length) return "No project roots are configured; fix projectRoots and refresh"
```

and the authoritative half in `cmd_remove`, after the usage check at
`pkgs/cli.sh:493`:

```sh
[ ${#roots[@]} -gt 0 ] || die 1 "remove needs at least one --root: with none there is nothing to protect the project roots."
```

`--root` therefore becomes **required for `remove`** (it stays optional for
`list`, where zero roots is a real configuration — the allow file is still a
candidate source, `pkgs/cli.sh:360-374` — and where nothing is deleted).
`Model.DEFAULT_ROOTS` means the setting is never empty in practice; an empty
`rootsFor` result (`Model.js:~205`) means every configured entry was rejected,
which already surfaces as a warning (`DevenvState.qml:341-342`), and refusing
to delete in that state is the right answer.

### Refusal messages

CLI, exit 2 unless noted. Unchanged: `pkgs/cli.sh:496`, `:498`, `:499`, `:500`,
`:503`, `:504`, `:508`, `:510`. Changed or new:

| Line | Message |
| --- | --- |
| replaces `:511` | `refused: $dir is not the directory that was listed; it has been replaced since. Refresh and try again.` |
| replaces `:507`'s `continue` | `refused: the project root $r cannot be resolved; it may be on a drive that is not mounted. Removal needs every root to resolve.` |
| new, after `:524` on the refusal path | `nixarchy-devenv: $dir was revoked before this refusal; run \`devenv allow\` there if you still want automatic activation.` |
| `:486`, exit 1 | `--root needs a directory` |
| new, exit 1 | `remove needs at least one --root: with none there is nothing to protect the project roots.` |
| replaces `:493`'s `--dev` arm, exit 1 | `--ident is DEV:INO, as \`list --json\` reports it.` |
| new skew arm, exit 1 | `--dev is gone; the plugin calling this is older than the command. Update the plugin.` |

`Model.js` (advisory, drawn in the panel): `"Refresh the list first"`
(`Model.js:812`) is kept, now keyed on `!env.ident`; the new one is
`"No project roots are configured; fix projectRoots and refresh"`.

Usage line at `pkgs/cli.sh:98` and `:494` becomes:

```
nixarchy-devenv remove --tier files|state|folder --confirm DIR --ident DEV:INO --root DIR [--root DIR]... DIR
```

### One PR

Open question 3: **one PR on `fix/9-removal-identity`, closing #9, #10 and
#11.** #9 and #11 are one edit (the token, and `verify_target`'s second call).
#10 lands in the same `cmd_remove` argument loop, the same two `Model.js`
functions, and the same `tests/cli.sh` block — which has to be rewritten for
the now-required `--root` regardless. Splitting means rewriting the same ~60
test lines twice and leaves `main` carrying a half-armed guard in between. One
commit per plan step, each citing its step.

## Alternatives rejected

- **Carry `mtime` in the token.** Refuses a removal after any touch of the
  directory, catches nothing the inode misses for this threat, and is
  `touch`-settable. Reasoned in full in Design §1.
- **Keep `--dev` and add `--inode`.** An old plugin sending only `--dev` would
  be accepted with no inode check — fails open on exactly the skew a rename
  makes loud.
- **Warn and continue on an unresolvable root.** The fail-open reading of the
  one guard whose whole job is "never delete a project root". Its supposed cost
  is not paid on the plugin path, because `list` already drops unreadable roots
  before reporting them (`pkgs/cli.sh:347-350`).
- **Write a cookie file into the project at list time and check it before
  deleting.** Writes into the user's directory in order to read it, and a
  `cp -r` of the project carries the cookie to a second path.
- **Hold an open fd on the directory across the status call**
  (`exec {fd}<"$dir"`, compare `stat` on `/proc/self/fd/$fd`). Genuinely
  closes the window rather than narrowing it, but bash cannot `rm -rf` through
  an fd, so the delete still takes a path and the residue returns; it also adds
  a `/proc` dependence. Noted as the upgrade path if the residual window ever
  matters in practice.
- **Stop sourcing `list` candidates from devenv's allow file**
  (`pkgs/cli.sh:360-374`), so every row is under a root by construction. Hides
  environments the user deliberately allowed outside their roots — a
  user-visible regression — and does nothing for a by-hand CLI caller.
- **#10 as a separate PR.** Reasoned in Design.

## Risks

- **CLI break, deliberate.** `--dev` is gone and `--root` is required for
  `remove`. Both skew directions exit non-zero without touching a file. The
  usage text (`pkgs/cli.sh:98`), `docs/usage.md` and the README must change in
  the same PR — AGENTS.md requires it for any user-visible change.
- **Residual TOCTOU on the `folder` tier.** Microseconds between the final
  `stat` and `rm -rf "$dir"`, irreducible while the delete is path-based in
  bash. `files` and `state` are already bounded (`rm -f` on a symlink removes
  the link; `find` does not follow). Mark it with a `ponytail:`-style comment
  naming the ceiling and the fd upgrade path.
- **A refused removal can leave the environment revoked.** Reversible, and now
  said out loud; the alternative reopens the window.
- **Test churn.** Every `rm_cli` call in `tests/cli.sh:276-322` gains `--root`
  and swaps `--dev` for `--ident` — about fifteen lines. `dev_of`
  (`tests/cli.sh:270`) becomes `ident_of`.
- **One wall-clock-sensitive test.** The #11 window test needs a stub that is
  slow *and* answers "stopped" (today's `hang` mode answers "unknown", which
  already refuses). Adding a `slow)` arm to `tests/stub/devenv` is the smallest
  way. Flake risk on a loaded machine is bounded by asserting only "exit 2 and
  the directory is intact", never on timing, and by giving the stub a sleep
  three times the swap delay.
- **`stat -c '%d:%i'` is GNU coreutils**, already a dependency
  (`pkgs/cli.sh:391`, `tests/cli.sh:25` symlinks `stat` onto the test PATH).
- **Inode reuse.** A freed inode can be handed to a new directory at the same
  path. It requires the original to be deleted first, which is the outcome the
  user asked for; not a practical path to deleting the *wrong* directory.

## Verification

```bash
node tests/run.js
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
nix flake check
nix flake check --all-systems --no-build
```

Live, on a nixarchy desktop, per AGENTS.md "Verifying live": install the built
plugin, create `t1` and `t2` under a `mktemp -d` inside an existing project
root, and drive the intent's own reproduction — list, `mv` `t2` over `t1`'s
path from another terminal, confirm — expecting the refusal and both trees
intact. Never against a real project.

### Filesystem tests to add — `tests/cli.sh`, the `remove` block (from line 258)

Helpers: `ident_of() { stat -c '%d:%i' -- "$1"; }` replaces `dev_of`
(`tests/cli.sh:270`); every existing `rm_cli` call gains `--root "$R/root"`.

1. **The #9 reproduction.** `p=$(mkproj a); q=$(mkproj b); i=$(ident_of "$p")`,
   then `rm -rf "$p"; mv "$q" "$p"`, then `rm_cli --tier folder --confirm "$p"
   --ident "$i" --root "$R/root" "$p"` → exit 2, `$p` still holds b's
   `src/main.py`. This is the test that fails against today's code.
2. **Same device, different inode.** Two projects on the same temp filesystem;
   removal of one with the other's ident → exit 2. Proves the check is not
   satisfied by the device half alone.
3. **An ordinary edit does not block removal.** `touch "$p/devenv.nix"; echo x
   >>"$p/src/main.py"`, then remove with the ident captured before the edit →
   exit 0. Pins the "no `mtime`" decision; it fails the moment someone adds
   `mtime` to the token.
4. **Malformed `--ident`.** `--ident 5`, `--ident a:b`, `--ident ""`,
   `--ident 5:` → exit 1 each, target untouched.
5. **Skew.** `--dev 2049` → exit 1, message names the plugin.
6. **Empty root value.** `--root ""` → exit 1, `untouched`.
7. **No `--root` at all.** → exit 1, `untouched`. (Today this is exit 0 and the
   directory is gone; that is #10's first route.)
8. **Unresolvable root.** `--root "$R/root" --root /definitely/not/mounted` →
   exit 2, `untouched`. The fail-closed answer to open question 2.
9. **The #11 window.** Add `slow)` to `tests/stub/devenv`'s `processes` arm:
   `sleep 3` then the `stopped` message and `exit 1`. Then run
   `STUB_PROCESSES=slow rm_cli --tier folder … "$p" &`, `sleep 1`, swap
   (`rm -rf "$p"; mv "$q" "$p"`), `wait` → exit 2 and `$p` intact. With the
   identity check in its current position the swap lands after the check and
   the directory is deleted, so this test fails on `main`.
10. **The #11 ancestor-symlink variant.** Same shape, but during the sleep
    replace an ancestor directory of `$p` with a symlink to a sibling tree →
    exit 2, and nothing in either tree removed. Covers the canonical-path check
    being re-run rather than only the identity check.
11. **The happy paths still pass.** `tests/cli.sh:306`, `:314`, `:318`, `:322`
    re-run with `--ident`/`--root`, including `grep -q "$p :: revoke"
    "$STUB_LOG"` (`tests/cli.sh:311`) — revoke still runs, still before the
    final verify.
12. **Revoke-then-refuse is announced.** Force a refusal at the final verify
    (test 9) and assert the stderr line naming `devenv allow` is present, and
    that `$STUB_LOG` shows the revoke.

### Node tests to add — `tests/model/`

In `remove.test.js` (alongside the existing `refuse`/`ROOTS` harness at
`tests/model/remove.test.js:1-6`):

- `removeArgv(e(), "files", [])` → `null`, and
  `removeRefusal(e(), "files", [], HOME, STOPPED)` matches `/project roots/`.
  Covers #10's `Model.js` route.
- `removeArgv` with a non-absolute entry among the roots → `null` (existing
  behaviour, now pinned beside the empty case).
- `removeArgv` builds `--ident` from `env.ident` and emits one `--root` per
  root, in order.
- A row with `ident: ""`, a missing `ident`, or `ident: "5"` → `removeArgv`
  `null` and `removeRefusal` `"Refresh the list first"`.
- `revoke` is still allowed with zero roots and no ident
  (`tests/model/remove.test.js:13-16` must keep passing — revoke deletes
  nothing).

In `parsing.test.js`: `parseList` keeps a well-formed `ident`, blanks
`"5"`/`5`/absent, and still parses `mtime`. In `rows.test.js`: `compareEnvs`
still sorts on `mtime` (`Model.js:379`), so removing it from the guard did not
remove it from the row.
