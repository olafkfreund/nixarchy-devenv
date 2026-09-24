---
status: approved
issue: 9
spec: spec/2026-09-24-9-removal-identity.md
---

# Plan: removal verifies the directory's identity, and verifies it last

Base: `main` at **e254c82** (merge of PR #26, which closed #8). Branch
`fix/9-removal-identity`, one PR closing #9, #10 and #11.

`nixarchy-devenv remove` deletes project directories, and AGENTS.md promises the
CLI performs the authoritative checks "immediately before it deletes", one of
them being that the directory is "unchanged since it was confirmed". Three
defects mean that does not hold.

**#9 — the identity check identifies nothing.** `cmd_list` puts `stat -c %d`
(the *filesystem's* device number) in each row (`pkgs/cli.sh:377` ordinary rows,
`:403` bound rows); `cmd_remove` compares it at `pkgs/cli.sh:497`. Every
directory on one disk shares it, so the check only catches a change of mount
point. List `proj-A`, `mv` `proj-B` over that path from another terminal,
confirm — exit 0 and `proj-B` is gone. No attacker, no race: a stale panel row
is enough, and the list is polled.

**#10 — the root guard can be switched off silently, four ways.**
`pkgs/cli.sh:472` accepts an empty `--root` and then discards it;
`pkgs/cli.sh:493` silently `continue`s past a root whose path will not resolve;
`Model.js:823-824` calls `rootArgs(roots)` and tests `if (!r) return null`, but
`rootArgs([])` returns `[]`, which is **truthy**, so zero roots builds an argv
with no `--root` at all; and upstream of all of them `DevenvState.qml:267,269`
passes `canonicalRoots` — the roots `list` *managed to resolve* — so an offline
root disappears before the CLI ever sees it.

**#11 — the checks are not immediately before the delete.** Between the last
check (`pkgs/cli.sh:497`) and `rm -rf` (`:518`/`:524`) the command spends up to
ten seconds in `devenv processes list` (`:502`) and then runs `devenv revoke`
(`:510`). Swapping an ancestor directory for a symlink inside that window
redirected the delete into another tree.

## Approved decisions (settled — do not re-decide)

1. **`--dev N` becomes `--ident DEV:INO`.** A **rename, not an extension**, so
   version skew between the packaged plugin and the `nixarchy-devenv` on the
   shell's PATH fails closed in both directions: a new plugin's `--ident`
   against an old CLI hits the `-*)` arm and exits 1; an old plugin's `--dev`
   against the new CLI hits its own explicit arm and exits 1. Keeping `--dev`
   and adding `--inode` would let an old plugin through with no inode check —
   fail-open on exactly the skew a rename makes loud.
2. **Device + inode, never `mtime`.** `mtime` catches nothing device+inode
   misses *for this threat* (a different directory has a different inode), it
   would refuse ordinary work (the list polls at ≥10 s; any edit between the
   poll and the confirmation would read as tampering), and it is `touch`-
   settable. `mtime` **stays in the row** — it is `compareEnvs`' sort key
   (`Model.js:372-379`) — it is simply never a guard.
3. **Checks lifted into one `verify_target()`, called twice**, the second call
   the **last statement before `rm`**. The whole set is re-run, not just the
   identity check, because the ancestor-symlink swap defeats the canonical-path
   check, not the identity check. `devenv revoke` stays *before* the final
   verify — moving it after reopens the window — so a removal refused at the
   final verify may already be revoked; that must be announced, not silent.
4. **`--root` is required for `remove`.** An empty `--root` value is refused; an
   unresolvable root is refused (not skipped); zero roots is refused, in
   **both** `Model.js` and `cli.sh`. `--root` stays optional for `list`, where
   zero roots is a real configuration and nothing is deleted.
5. **`DevenvState.qml` passes the CONFIGURED roots**, unioned with the resolved
   ones — so an offline root reaches the CLI and the CLI refuses it. Duplicate
   `--root` flags are harmless.
6. **One PR** for #9 + #10 + #11.

Non-negotiables carried from AGENTS.md: argv arrays only, never `sh -c`; the
authoritative checks stay in the CLI and `Model.js` pre-checks stay advisory;
`.envrc` is never removed and the `files` tier keeps `.devenv/state`; every
refusal gets a filesystem test and every `Model.js` pre-check a Node test; a
user-visible change updates `docs/usage.md` and the README in the same PR.

### What #8's merge changed under this plan

- `tests/run.js` is **gone**. The model command is
  `node --test 'tests/model/*.test.js'`.
- Baselines on e254c82: **70 model tests** (`ℹ pass 70 / ℹ fail 0`) and
  **`cli: 63 passed, 0 failed`**.
- `Model.js` now has a shared `rootArgs(roots)` (`Model.js:619-627`), used by
  both `listArgv` and `removeArgv`. The zero-roots refusal is therefore **one
  caller check in `removeArgv`**, not two inline loops — this collapses what was
  a two-file edit into one line, so the old step 3 and step 4 are now **merged
  into a single step 3** (five steps instead of six).
  The refusal cannot live inside `rootArgs` itself: `listArgv([])` legitimately
  returns `[CLI, "list", "--json"]`, and listing with zero roots deletes
  nothing.
- `tests/cli.sh` now has `rm_cli() { with_devenv "$cli" remove "$@"; }` with **no
  `STUB_PROCESSES` wrapper** — the stub's own default (`stopped`) applies, and
  the running/unknown cases call `with_devenv env STUB_PROCESSES=… "$cli"
  remove …` directly. The new `slow` test follows that second form.
- `tests/stub/devenv` now carries the `STUB_INIT_NIXPKGS`,
  `STUB_INIT_NOPLACEHOLDER`, `STUB_PROCESSES`, `STUB_LOG` family; the new
  `slow)` arm goes inside the existing `case "${STUB_PROCESSES:-stopped}"` with
  a comment in the same voice as its neighbours.
- `pkgs/cli.sh`'s `splice_preset` is now the `sed -i "$((close - 1))r $file"`
  form. Nothing in this plan touches it; noted only so the file's shape is not a
  surprise.

### Known residue, to be marked in the code

`rm -rf "$dir"` resolves the path again, so microseconds remain between the
final `stat` and the delete, on the `folder` tier only (`files` and `state` are
already bounded: `rm -f` on a symlinked `devenv.nix` removes the link, and
`find` does not follow symlinks). Leave a `ponytail:`-style comment naming the
ceiling and the upgrade path (hold an open fd on the directory across the status
call and compare `stat` on `/proc/self/fd/$fd`; rejected for now because bash
cannot `rm -rf` through an fd, so the delete still takes a path).

## Steps

Five commits, one per step, each citing its step number and the issue. Both
suites are green at every commit: the two tests the spec calls out as failing on
`main` (the #9 reproduction, step 2; the #11 window test, step 4) are added **in
the same commit as their fix**, never before it. Likewise every existing test a
CLI contract change would break is updated inside the commit that makes the
change — steps 2, 3 and 4 each touch `pkgs/cli.sh` and its tests together.

### 1. `pkgs/cli.sh`: lift the target checks into `verify_target()` (pure refactor)

Move `pkgs/cli.sh:482-497` — every check from `--confirm` through the device
comparison — verbatim into a new top-level function defined just above
`cmd_remove` (which starts at `:465`). Bash is dynamically scoped, so the
function reads `cmd_remove`'s locals (`$dir`, `$confirm`, `$dev`,
`${roots[@]}`) without parameters; do not add any.

```sh
# Everything that must be true of the target. Pure reads, microseconds. Called
# once up front so a bad request is refused before any subprocess runs, and
# again as the last statement before anything is deleted -- that second call is
# the authoritative one.
verify_target() {
  [ "$confirm" = "$dir" ] || die 2 "refused: --confirm does not name $dir exactly."
  ...
}
```

`cmd_remove` keeps exactly one call, where the block used to be. Order inside
the function is unchanged, and the device comparison stays last. No behaviour
changes in this commit.

→ verify by
`bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"` —
**`cli: 63 passed, 0 failed`**, identical to e254c82 — and by `git show --stat`
showing `pkgs/cli.sh` as the only file touched.

### 2. The identity token, end to end (#9)

One commit, because the CLI's flag and the plugin's argv are one contract: split
them and the checked-out tree has a plugin whose every removal exits 1.

**`pkgs/cli.sh`**

- Ordinary rows (`:377`): `--argjson dev "$(stat -c %d "$real")"` →
  `--arg ident "$(stat -c '%d:%i' -- "$real")"`.
- Bound rows (`:403`): the same substitution, and in the object literal at
  `:406` `dev: $dev` → `ident: $ident`.
- `cmd_remove`'s locals (`:466`): `dev=""` → `ident=""`.
- The argument loop (`:471`): `--dev) dev=${2:-}; shift ;;` →
  `--ident) ident=${2:-}; shift ;;`, and add, **before** the `-*)` arm, an
  explicit skew arm:
  ```sh
  --dev) die 1 "--dev is gone; the plugin calling this is older than the command. Update the plugin." ;;
  ```
- The usage guard (`:479`): `[[ $dev =~ ^[0-9]+$ ]]` →
  `[[ $ident =~ ^[0-9]+:[0-9]+$ ]]`, and add above it a targeted message so a
  malformed token does not read as a usage error:
  `--ident is DEV:INO, as \`list --json\` reports it.` (exit 1).
- `verify_target`'s last line (was `:497`):
  ```sh
  [ "$(stat -c '%d:%i' -- "$dir")" = "$ident" ] ||
    die 2 "refused: $dir is not the directory that was listed; it has been replaced since. Refresh and try again."
  ```
- Both usage strings — `pkgs/cli.sh:98` (`cmd_help`) and the `die 1` at `:480` —
  become:
  ```
  nixarchy-devenv remove --tier files|state|folder --confirm DIR --ident DEV:INO --root DIR [--root DIR]... DIR
  ```
  (`--root` is shown as required here; step 3 makes it so.)

**`Model.js`**

- `parseList` (`:251`): `dev: typeof r.dev === "number" ? r.dev : -1` →
  `ident: /^[0-9]+:[0-9]+$/.test(str(r.ident)) ? str(r.ident) : ""`, in the same
  allowlist style as the neighbouring `template` field. Leave `mtime` alone.
- `removeRefusal` (`:809`): `if (typeof env.dev !== "number" || env.dev < 0)` →
  `if (!env.ident)`, message unchanged (`"Refresh the list first"`).
- `removeArgv` (`:822`): the same guard; and at `:825`
  `"--dev", String(env.dev)` → `"--ident", env.ident`.

**`tests/harness.js`**: `listRow` (`:33`) `dev: 2049` → `ident: "2049:17"`.

**`tests/model/parsing.test.js`**: `:14` `dev: 2049` → `ident: "2049:17"`, `:26`
`dev: -1` → `ident: ""`; add a test that `parseList` blanks `"5"`, `5` and an
absent `ident`, and still parses `mtime`.

**`tests/model/remove.test.js`**: rename the test at `:44` to ident, asserting
`/Refresh/` for `ident: undefined`, `ident: ""` and `ident: "5"`; at `:56` the
expected argv carries `"--ident", "2049:17"`; `:59`'s
`removeArgv(env({ dev: -1 }), …)` becomes `env({ ident: "" })`.

**`tests/model/rows.test.js`**: add one assertion that `compareEnvs` still sorts
on `mtime` — it must be provably still in the row.

**`tests/cli.sh`**, the `remove` block (from `:268`): `dev_of()` (`:277`) →
`ident_of() { stat -c '%d:%i' -- "$1"; }`; `d=$(dev_of "$p")` (`:282`) →
`i=$(ident_of "$p")`; every `--dev "$d"` → `--ident "$i"` and every
`--dev "$(dev_of X)"` → `--ident "$(ident_of X)"` (lines 283-329, including the
two `with_devenv env STUB_PROCESSES=…` calls at `:307` and `:309`). Then add:

- the **#9 reproduction**: `p=$(mkproj a); q=$(mkproj b); i=$(ident_of "$p")`,
  `rm -rf "$p"; mv "$q" "$p"`, then
  `expect 2 "remove: a different directory now stands at the path" -- rm_cli --tier folder --confirm "$p" --ident "$i" "$p"`, asserting `$p` still holds
  b's `src/main.py`. **This is the test that fails against today's code.**
- **same device, different inode**: two projects on the same temp filesystem,
  removal of one carrying the other's ident → exit 2;
- **an ordinary edit does not block removal**: `touch "$p/devenv.nix"; echo x >>"$p/src/main.py"`, remove with the ident captured *before* the edit →
  exit 0. This pins decision 2 and fails the moment anyone adds `mtime`;
- **malformed `--ident`**: `5`, `a:b`, `""`, `5:` → exit 1 each, `untouched`;
- **skew**: `--dev 2049` → exit 1, stderr naming the plugin.

→ verify by `node --test 'tests/model/*.test.js'` (`ℹ fail 0`; `ℹ pass` rises
from 70 by one per `test()` block added, ≈72) and
`bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
(`0 failed`; from 63 up by one per `expect`, ≈72). Then
`grep -rn '\-\-dev\b' pkgs/ Model.js tests/` must return only the deliberate
skew arm and the test that exercises it.

### 3. The root guard cannot be disarmed, end to end (#10)

Merged from what were two steps: `rootArgs` already exists, so the `Model.js`
half is one line, and the CLI half and the QML half are the same chain — an
offline root must *reach* the CLI for the CLI's refusal to mean anything.

**`pkgs/cli.sh`**

- The argument loop (`:472`), matching what `cmd_list` already does at `:312`:
  ```sh
  --root) [ -n "${2:-}" ] || die 1 "--root needs a directory"; roots+=("$2"); shift ;;
  ```
- After the usage check (`:480`):
  ```sh
  [ ${#roots[@]} -gt 0 ] || die 1 "remove needs at least one --root: with none there is nothing to protect the project roots."
  ```
- Inside `verify_target`, the root loop's silent skip (was `:493`) becomes a
  refusal:
  ```sh
  rc=$(realpath -e -- "$(expand_root "$r")" 2>/dev/null) ||
    die 2 "refused: the project root $r cannot be resolved; it may be on a drive that is not mounted. Removal needs every root to resolve."
  ```

**`Model.js`** — advisory halves:

- `removeArgv` (`:823-824`): `if (!r) return null` → `if (!r || !r.length) return null`, with the comment
  `// the root guard lives in the CLI; never call it disarmed`. Leave
  `rootArgs` and `listArgv` untouched — listing with zero roots is legal.
  The `revoke` early return at `:821` stays above this, so revoke keeps working
  with zero roots and no ident: it deletes nothing.
- `removeRefusal`, before its root loop and after the `revoke` early return:
  ```js
  if (!(roots || []).length) return "No project roots are configured; fix projectRoots and refresh"
  ```

**`DevenvState.qml`** — one new readonly property beside `roots` (`:26`):

```qml
// Removal checks against these. The union of what is configured and what the
// CLI resolved: a root on an unmounted drive drops out of canonicalRoots, and
// it must still reach the CLI so the CLI can refuse the removal.
readonly property var guardRoots: {
    var out = []
    var i
    for (i = 0; i < (roots ? roots.length : 0); i++) out.push(roots[i])
    for (i = 0; i < (canonicalRoots ? canonicalRoots.length : 0); i++)
        if (out.indexOf(canonicalRoots[i]) === -1) out.push(canonicalRoots[i])
    return out
}
```

Index loops, not `.slice()`/`Array.isArray`: `canonicalRoots` (`:87`) is read
through a QObject `var` property and may be a Qt sequence wrapper. Then in
`remove()` replace `root.canonicalRoots` with `root.guardRoots` at **`:267`**
and **`:269`**. Leave `canonicalRoots` itself, `rootMap`, the assignment at
`:341` and `listArgv` alone. No new runtime file, so `flake.nix`'s `files` list
is untouched.

**`tests/model/remove.test.js`**: `removeArgv(env(), "files", [])` → `null`;
`removeRefusal(env(), "files", [], HOME, STOPPED)` matches `/project roots/`; a
non-absolute entry among the roots still → `null`, pinned beside the empty case
(`:59` already covers `["rel"]`); the "revoke is always allowed" test at `:12`
stays green with zero roots.

**`tests/cli.sh`**: every remaining `rm_cli`/`"$cli" remove` call in the block
gains `--root "$R/root"` — the happy paths at `:320`, `:325`, `:329` and the
bound-directory loop at `:303` included — plus

- `--root ""` → exit 1, `untouched`;
- no `--root` at all → exit 1, `untouched` (today this is exit 0 and the
  directory is gone — #10's first route);
- `--root "$R/root" --root /definitely/not/mounted` → exit 2, `untouched`.

→ verify by both suites `0 failed`; by
`grep -n 'remove --tier\|rm_cli --tier' tests/cli.sh | grep -v -- '--root'`
printing only the three deliberate no-root/empty-root cases; and by
`nix flake check` plus `nix build && omarchy plugin validate "$(readlink -f result)"` for the QML change.

### 4. The final verify, and the #11 window test

**`pkgs/cli.sh`**, `cmd_remove`'s body becomes:

```
parse argv; verify_target            # fast, loud refusal before any subprocess
cmd_status  -> stopped / no devenv   # up to 10 s
devenv revoke                        # subprocess
revoked=1; verify_target             # <- authoritative, LAST statement before rm
rm ...
```

The second call is literally the statement before the `case "$tier"` at `:515`
that deletes; nothing may be inserted between them. To keep the announcement out
of the ordinary path, declare `revoked=0` among `cmd_remove`'s locals, set it to
`1` right after the `devenv revoke` block (`:509-511`), and route
`verify_target`'s refusals through a helper it owns:

```sh
refuse() {
  [ "${revoked:-0}" = 1 ] &&
    echo "nixarchy-devenv: $dir was revoked before this refusal; run \`devenv allow\` there if you still want automatic activation." >&2
  die 2 "$1"
}
```

Replace `die 2 "…"` with `refuse "…"` throughout `verify_target` **only** —
`cmd_remove`'s own `die 2`s (the process-state refusals) keep `die`. Add the
residue comment above the `folder` arm's `rm -rf`, naming the microsecond window
and the open-fd upgrade path.

**`tests/stub/devenv`**, a new arm inside the existing
`case "${STUB_PROCESSES:-stopped}"`, in the same commented style as its
neighbours — slow *and* answering "stopped", because today's `hang` answers
"unknown", which already refuses and so proves nothing about this window:

```sh
# slow: the stopped answer, three seconds late. The window between the last
# check and the delete is only observable when the status call is slow AND
# permissive; hang is slow but answers unknown, which refuses on its own.
slow) sleep 3; echo "  x No process manager is running. Start processes first with \`devenv up -d\`" >&2; exit 1 ;;
```

**`tests/cli.sh`**, two tests, each asserting only "exit 2 and the tree is
intact" — never on timing — with the stub's 3 s sleep against a 1 s swap delay,
and each invoked as the existing running/unknown cases are
(`with_devenv env STUB_PROCESSES=slow "$cli" remove …`, since `rm_cli` no longer
carries a `STUB_PROCESSES` wrapper):

- **the window**: launch the removal in the background, `sleep 1`,
  `rm -rf "$p"; mv "$q" "$p"`, `wait` → exit 2, `$p` intact, the stderr carries
  the `devenv allow` line, and `$STUB_LOG` shows the revoke ran;
- **the ancestor-symlink variant**: same shape, but during the sleep replace an
  ancestor directory of `$p` with a symlink to a sibling tree → exit 2 and
  nothing removed in either tree. This covers the canonical-path check being
  re-run, not only the identity check.

Both fail on `main`; they land with the fix, so no commit is red. (`expect`
takes the command after `--`; a backgrounded pipeline needs its exit status
captured by hand rather than through `expect` — assert with `ok`/`bad` in the
same style as the surrounding block.)

→ verify by the CLI suite `0 failed`, by reading the diff (the second
`verify_target` is the last statement before the deleting `case`), and by
running the suite three times to shake out flake:
`for i in 1 2 3; do bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv" || break; done`.

### 5. Docs, in the same PR (AGENTS.md requires it)

- `README.md`, the Safety list (≈`:119-128`): "it is on the device it was listed
  on" → "it is the same directory that was listed (device and inode)"; add "at
  least one project root was passed, and every one of them resolves"; and say
  the checks run twice, the second time immediately before the delete.
- `docs/usage.md`: the `remove` synopsis if present, and the removal prose —
  the same two points.
- `AGENTS.md`, the "Removal is tiered, and bounded where it executes" bullet:
  "unchanged since it was confirmed" → names device+inode, says the checks run
  again as the last statement before the delete, and that `--root` is required.

→ verify by `grep -rn '\-\-dev\b\|device it was listed' README.md docs/ AGENTS.md`
returning nothing, and `nix flake check`.

## Tests

Run from the repo root, after every step:

```bash
node --test 'tests/model/*.test.js'
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
nix flake check
nix flake check --all-systems --no-build
```

Expected output:

| Command | On e254c82 | After step 5 |
| --- | --- | --- |
| `node --test 'tests/model/*.test.js'` | `ℹ pass 70` / `ℹ fail 0` | `ℹ fail 0`, one more `pass` per `test()` block added (≈75) |
| `bash tests/cli.sh …` | `cli: 63 passed, 0 failed` | `cli: 0 failed`, one more pass per `expect` (≈78) |
| `nix flake check` | passes | passes (it runs both suites, plus manifest, entry points, no symlinks, no `pacman`/`yay`, no hex colours) |
| `nix flake check --all-systems --no-build` | passes | passes |

The pass counts are guidance, not a gate. The gate is `fail 0` / `0 failed`, and
that the count never *drops* — a falling count means a test was deleted rather
than ported. `tests/run.js` no longer exists; do not reintroduce it.

`nix run .#templates-check` is untouched by this work (no catalogue change) and
is not required here.

**Live, on a nixarchy desktop**, per AGENTS.md "Verifying live": `nix build`,
`rm -rf ~/.config/omarchy/plugins/nixarchy.devenv`,
`cp -rL result ~/.config/omarchy/plugins/nixarchy.devenv`, `chmod -R u+w` it,
`omarchy-shell shell rescanPlugins`, `omarchy-restart-shell`, wait for
`omarchy-shell shell ping`, then check `qs log -i <instance>` for errors (get the
instance from `qs list --all`). Make sure the rebuilt CLI is the one on the
**shell's** PATH (read it from `/proc/<quickshell pid>/environ`; a
`~/.local/bin` symlink to `nix build .#cli -o <gcroot>` is the usual route) —
with a stale CLI every removal will exit 1, which is the skew behaviour, not a
bug. Then drive the #9 reproduction: create `t1` and `t2` under a `mktemp -d`
root **inside an existing project root** (so no setting changes), list them in
the menu, `mv` `t2` over `t1`'s path from another terminal, confirm the removal
— expect the refusal and both trees intact. Remove `t1`/`t2` through the plugin
when done. Never point a removal test at a real project, and check
`hyprctl layers -j` for `nixarchy-devenv-menu` before any `wtype`.

## Rollback

The branch is five commits on `fix/9-removal-identity`, each self-contained.

- Whole branch: `git revert --no-commit <first>..<last> && git commit`, or drop
  the branch before merge. Nothing outside `pkgs/cli.sh`, `Model.js`,
  `DevenvState.qml`, `tests/` and the three docs files is touched; no settings
  schema, no `flake.nix` `files` list, no catalogue, no state on disk. A revert
  restores the old behaviour exactly — including the three defects.
- Single steps: step 5 (docs), step 4 (final verify + `slow)` arm + its two
  tests) and step 3 (#10) revert cleanly on their own. Step 2 does **not**:
  reverting it alone leaves step 3's and step 4's tests calling `--ident`.
  Revert 4, 3 and 2 in that order, or revert 2 and re-run the CLI suite before
  pushing.

**`--ident` is a CLI contract change — this is the point, not a side effect.**
The packaged plugin and the `nixarchy-devenv` on the shell's PATH are installed
separately, so they can skew:

- **New plugin, old CLI** (plugin updated, the `~/.local/bin` symlink stale):
  the plugin sends `--ident DEV:INO`; the old CLI has no such arm, falls through
  to `-*) die 1 "unknown option --ident"`, exits 1. Nothing is deleted; the
  panel shows the CLI's stderr.
- **Old plugin, new CLI**: the plugin sends `--dev N`; the new CLI's explicit
  skew arm exits 1 with `--dev is gone; the plugin calling this is older than
  the command. Update the plugin.` Nothing is deleted. That arm exists precisely
  so the failure names the cause instead of reading as "unknown option".
- **Either skew, `list` and every other subcommand**: unaffected. Only removal
  stops working, and it stops working by refusing.

Both directions fail closed, and both are fixed by bringing the two halves to
the same revision — rebuild and re-link the CLI (`nix build .#cli -o <gcroot>`)
and re-copy the plugin folder.

`--root` becoming required for `remove` breaks any hand-written script that
called `remove` without one; such a script was deleting with the root guard
disarmed, which is #10. It exits 1 and deletes nothing until a `--root` is
added.
