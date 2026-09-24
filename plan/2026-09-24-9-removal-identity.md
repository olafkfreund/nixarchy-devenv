---
status: draft
issue: 9
spec: spec/2026-09-24-9-removal-identity.md
---

# Plan: removal verifies the directory's identity, and verifies it last

`nixarchy-devenv remove` deletes project directories, and AGENTS.md promises the
CLI performs the authoritative checks "immediately before it deletes", one of
them being that the directory is "unchanged since it was confirmed". Three
defects mean that does not hold. This branch fixes all three and closes #9, #10
and #11 in one PR on `fix/9-removal-identity`.

**#9 — the identity check identifies nothing.** `cmd_list` puts `stat -c %d`
(the *filesystem's* device number) in each row; `cmd_remove` compares it. Every
directory on one disk shares it, so the check only catches a change of mount
point. List `proj-A`, `mv` `proj-B` over that path from another terminal,
confirm — exit 0 and `proj-B` is gone. No attacker, no race: a stale panel row
is enough.

**#10 — the root guard can be switched off silently, three ways.** `cli.sh`
accepts an empty `--root` and then discards it; it silently `continue`s past a
root whose path will not resolve; and `Model.js` treats an empty roots list as
success, building an argv with no `--root` at all. A fourth, upstream of these:
`DevenvState.qml` passes `canonicalRoots` — the roots `list` *managed to
resolve* — so an offline root vanishes before the CLI ever sees it.

**#11 — the checks are not immediately before the delete.** Between the last
check and `rm -rf` the command spends up to ten seconds in `devenv processes
list` and then runs `devenv revoke`. Swapping an ancestor directory for a
symlink inside that window redirected the delete into another tree.

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
   settable. `mtime` **stays in the row** — it is `compareEnvs`' sort key — it
   is simply never a guard.
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

### Known residue, to be marked in the code

`rm -rf "$dir"` resolves the path again, so microseconds remain between the
final `stat` and the delete, on the `folder` tier only (`files` and `state` are
already bounded: `rm -f` on a symlinked `devenv.nix` removes the link, and
`find` does not follow symlinks). Leave a `ponytail:`-style comment naming the
ceiling and the upgrade path (hold an open fd on the directory across the status
call and compare `stat` on `/proc/self/fd/$fd`; rejected for now because bash
cannot `rm -rf` through an fd, so the delete still takes a path).

## Steps

One commit per step, each citing its step number and the issue. Both suites are
green at every commit: the two tests the spec calls out as failing on `main`
(the #9 reproduction, step 2; the #11 window test, step 5) are added **in the
same commit as their fix**, never before it. Likewise every existing test that a
CLI contract change would break is updated inside the commit that makes the
change — steps 2, 3 and 5 each touch `pkgs/cli.sh` and its tests together.

### 1. `pkgs/cli.sh`: lift the target checks into `verify_target()` (pure refactor)

Move `pkgs/cli.sh:496-511` — every check from `--confirm` through the device
comparison — verbatim into a new top-level function defined just above
`cmd_remove`. Bash is dynamically scoped, so the function reads `cmd_remove`'s
locals (`$dir`, `$confirm`, `$dev`, `${roots[@]}`) without parameters; do not
add any.

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

→ verify by `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"` — **62 passed, 0 failed**, byte-identical to `main`, and
`git show --stat` shows one file touched.

### 2. The identity token, end to end (#9)

One commit, because the CLI's flag and the plugin's argv are one contract: split
them and the checked-out tree has a plugin whose removals all exit 1.

**`pkgs/cli.sh`**

- Ordinary rows (line ~391): `--argjson dev "$(stat -c %d "$real")"` →
  `--arg ident "$(stat -c '%d:%i' -- "$real")"`.
- Bound rows (line ~418): the same substitution, and drop `dev` from the object
  literal's key list, adding `ident: $ident`.
- `cmd_remove`'s argument loop: `--dev) dev=${2:-}; shift ;;` →
  `--ident) ident=${2:-}; shift ;;`, and add, **before** the `-*)` arm, an
  explicit skew arm:
  ```sh
  --dev) die 1 "--dev is gone; the plugin calling this is older than the command. Update the plugin." ;;
  ```
- The usage guard: `[[ $dev =~ ^[0-9]+$ ]]` → `[[ $ident =~ ^[0-9]+:[0-9]+$ ]]`,
  with the message `--ident is DEV:INO, as \`list --json\` reports it.`
- `verify_target`'s last line:
  ```sh
  [ "$(stat -c '%d:%i' -- "$dir")" = "$ident" ] ||
    die 2 "refused: $dir is not the directory that was listed; it has been replaced since. Refresh and try again."
  ```
- Both usage strings — `pkgs/cli.sh:98` (`cmd_help`) and the `die 1` at
  `pkgs/cli.sh:494` — become:
  ```
  nixarchy-devenv remove --tier files|state|folder --confirm DIR --ident DEV:INO --root DIR [--root DIR]... DIR
  ```
  (`--root` is shown as required here; step 3 makes it so.)

**`Model.js`**

- `parseList` (line ~258): `dev: typeof r.dev === "number" ? r.dev : -1` →
  `ident: /^[0-9]+:[0-9]+$/.test(str(r.ident)) ? str(r.ident) : ""`, in the same
  allowlist style as the neighbouring `template` field. Leave `mtime` exactly as
  it is.
- `removeRefusal` (line ~812): `if (typeof env.dev !== "number" || env.dev < 0)`
  → `if (!env.ident)`, message unchanged (`"Refresh the list first"`).
- `removeArgv` (line ~825): the same guard, and
  `"--dev", String(env.dev)` → `"--ident", env.ident`.

**`tests/harness.js`**: `listRow`'s `dev: 2049` → `ident: "2049:17"`.

**`tests/model/parsing.test.js`**: the two expected row objects swap `dev: 2049`
→ `ident: "2049:17"` and `dev: -1` → `ident: ""`; add cases that `parseList`
blanks `"5"`, `5` and an absent `ident`, and still parses `mtime`.

**`tests/model/remove.test.js`**: rename the "no device number" test to ident,
asserting `/Refresh/` for `ident: undefined`, `ident: ""` and `ident: "5"`;
`removeArgv` builds `--ident` from `env.ident`; `eq(Model.removeArgv(e({ ident: "" }), "files", ROOTS), null)` replaces the `dev: -1` case.

**`tests/model/rows.test.js`**: add one assertion that `compareEnvs` still sorts
on `mtime` — it must be provably still in the row.

**`tests/cli.sh`**, the `remove` block: `dev_of()` → `ident_of() { stat -c '%d:%i' -- "$1"; }`; every `--dev "$d"` → `--ident "$i"`, every
`--dev "$(dev_of X)"` → `--ident "$(ident_of X)"`. Then add:

- the **#9 reproduction**: `p=$(mkproj a); q=$(mkproj b); i=$(ident_of "$p")`,
  `rm -rf "$p"; mv "$q" "$p"`, then
  `expect 2 "remove: a different directory now stands at the path" -- rm_cli --tier folder --confirm "$p" --ident "$i" "$p"`, and assert `$p` still holds
  b's `src/main.py`. **This is the test that fails against today's code.**
- **same device, different inode**: two projects on the same temp filesystem,
  removal of one carrying the other's ident → exit 2;
- **an ordinary edit does not block removal**: `touch "$p/devenv.nix"; echo x >>"$p/src/main.py"`, remove with the ident captured *before* the edit →
  exit 0. This pins decision 2 and fails the moment anyone adds `mtime`;
- **malformed `--ident`**: `5`, `a:b`, `""`, `5:` → exit 1 each, `untouched`;
- **skew**: `--dev 2049` → exit 1, and the stderr names the plugin.

→ verify by `node --test 'tests/model/*.test.js'` and `node tests/run.js`
(`0 failed`; the count rises from 69 by one per `test()` block added), then
`bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
(`0 failed`; from 62 up by one per `expect`, roughly 62 → 72). Confirm
`grep -rn '\-\-dev\b' pkgs/ Model.js tests/` returns only the deliberate skew
arm and the test that exercises it.

### 3. The root guard cannot be disarmed (#10)

**`pkgs/cli.sh`**

- The argument loop, matching what `cmd_list` already does at line 326:
  ```sh
  --root) [ -n "${2:-}" ] || die 1 "--root needs a directory"; roots+=("$2"); shift ;;
  ```
- After the usage check (line ~493):
  ```sh
  [ ${#roots[@]} -gt 0 ] || die 1 "remove needs at least one --root: with none there is nothing to protect the project roots."
  ```
- Inside `verify_target`, the root loop's silent skip becomes a refusal:
  ```sh
  rc=$(realpath -e -- "$(expand_root "$r")" 2>/dev/null) ||
    die 2 "refused: the project root $r cannot be resolved; it may be on a drive that is not mounted. Removal needs every root to resolve."
  ```

**`Model.js`** — advisory halves, mirroring each other:

- `removeArgv`, immediately after the `revoke` early return and the ident guard,
  before the roots loop:
  ```js
  if (!list.length) return null   // the root guard lives in the CLI; never call it disarmed
  ```
  `revoke` must keep returning its argv with zero roots — it deletes nothing.
- `removeRefusal`, before its root loop:
  ```js
  if (!(roots || []).length) return "No project roots are configured; fix projectRoots and refresh"
  ```
  Placed after the `revoke` early return, for the same reason.

**`tests/model/remove.test.js`**: `removeArgv(e(), "files", [])` → `null`;
`removeRefusal(e(), "files", [], HOME, STOPPED)` matches `/project roots/`;
a non-absolute entry among the roots still → `null`, pinned beside the empty
case; the existing "revoke is always allowed" test stays green with zero roots
and no ident.

**`tests/cli.sh`**: every remaining `rm_cli` call in the block gains
`--root "$R/root"` (the happy paths at the end of the block included), plus

- `--root ""` → exit 1, `untouched`;
- no `--root` at all → exit 1, `untouched` (today this is exit 0 and the
  directory is gone — #10's first route);
- `--root "$R/root" --root /definitely/not/mounted` → exit 2, `untouched`.

→ verify by both suites `0 failed`, and by
`grep -n 'rm_cli' tests/cli.sh | grep -v -e '--root' -e 'rm_cli()'` printing
only the three deliberate no-root/empty-root cases.

### 4. `DevenvState.qml`: pass the configured roots, not only the resolved ones (#10)

Add one readonly property beside `roots` (line ~26):

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

Index loops, not `.slice()`/`Array.isArray`: `canonicalRoots` is read through a
QObject `var` property and may be a Qt sequence wrapper. Then in `remove()`
(lines 265 and 267) replace both uses of `root.canonicalRoots` with
`root.guardRoots`. Leave `canonicalRoots` itself, `rootMap` and `listArgv` alone.

→ verify by `nix flake check` (manifest, entry points, no symlinks, no hex
colours) and `nix build && omarchy plugin validate "$(readlink -f result)"`. No
new runtime file, so `flake.nix`'s `files` list is untouched — confirm with
`git show --stat`.

### 5. The final verify, and the #11 window test

**`pkgs/cli.sh`**, `cmd_remove`'s body becomes:

```
parse argv; verify_target            # fast, loud refusal before any subprocess
cmd_status  -> stopped / no devenv   # up to 10 s
devenv revoke                        # subprocess
revoked=1; verify_target             # <- authoritative, LAST statement before rm
rm ...
```

The second call is literally the statement before the `case "$tier"` that
deletes; nothing may be inserted between them. To keep the announcement out of
the ordinary path, set a local `revoked=0` in `cmd_remove`, set it to `1` right
after the `devenv revoke` block, and route `verify_target`'s refusals through a
small helper it already owns:

```sh
refuse() {
  [ "${revoked:-0}" = 1 ] &&
    echo "nixarchy-devenv: $dir was revoked before this refusal; run \`devenv allow\` there if you still want automatic activation." >&2
  die 2 "$1"
}
```

Replace `die 2 "…"` with `refuse "…"` throughout `verify_target` only. Add the
residue comment above the `folder` arm's `rm -rf`, naming the microsecond window
and the open-fd upgrade path.

**`tests/stub/devenv`**, the `processes)` case — a mode that is slow *and*
answers "stopped" (today's `hang` answers "unknown", which already refuses, so
it cannot prove anything about this window):

```sh
slow) sleep 3; echo "  x No process manager is running. Start processes first with \`devenv up -d\`" >&2; exit 1 ;;
```

**`tests/cli.sh`**, two tests, each asserting only "exit 2 and the tree is
intact" — never on timing — with the stub's 3 s sleep against a 1 s swap delay:

- **the window**: `STUB_PROCESSES=slow rm_cli --tier folder --confirm "$p" --ident "$i" --root "$R/root" "$p" &`, `sleep 1`, `rm -rf "$p"; mv "$q" "$p"`,
  `wait` → exit 2, `$p` intact, and the stderr carries the `devenv allow` line
  while `$STUB_LOG` shows the revoke ran (test 12 of the spec, folded in here);
- **the ancestor-symlink variant**: same shape, but during the sleep replace an
  ancestor directory of `$p` with a symlink to a sibling tree → exit 2 and
  nothing removed in either tree. This one covers the canonical-path check being
  re-run, not only the identity check.

Both fail on `main`; they land with the fix, so no commit is red.

→ verify by the CLI suite `0 failed`, and by reading the diff: the second
`verify_target` is the last statement before the deleting `case`. Run the suite
three times to shake out flake: `for i in 1 2 3; do bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv" || break; done`.

### 6. Docs, in the same PR (AGENTS.md requires it)

- `README.md:123-128`, the Safety list: "it is on the device it was listed on"
  → "it is the same directory that was listed (device and inode)", and add "at
  least one project root was passed, and every one of them resolves". Note the
  checks run twice, the second time immediately before the delete.
- `docs/usage.md`: the CLI section's `remove` synopsis, if present, and the
  removal prose — same two points.
- `AGENTS.md`, the "Removal is tiered, and bounded where it executes" bullet:
  "unchanged since it was confirmed" → names device+inode, and says the checks
  run again as the last statement before the delete, with `--root` required.

→ verify by `grep -rn '\-\-dev\b\|device it was listed' README.md docs/ AGENTS.md`
returning nothing, and `nix flake check`.

## Tests

Run from the repo root, after every step:

```bash
node tests/run.js
node --test 'tests/model/*.test.js'
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
nix flake check
nix flake check --all-systems --no-build
```

Expected output:

| Command | On `main` today | After step 6 |
| --- | --- | --- |
| `node tests/run.js` | `69 passed, 0 failed` | `0 failed`, one more `passed` per `test()` block added (≈74) |
| `node --test 'tests/model/*.test.js'` | all pass | all pass — `# fail 0` |
| `bash tests/cli.sh …` | `cli: 62 passed, 0 failed` | `cli: 0 failed`, one more pass per `expect` (≈77) |
| `nix flake check` | passes | passes (it runs both suites, plus manifest, entry points, no symlinks, no `pacman`/`yay`, no hex colours) |
| `nix flake check --all-systems --no-build` | passes | passes |

The pass counts are guidance, not a gate: the gate is `0 failed`, and that the
count never *drops* — a falling count means a test was deleted rather than
ported.

`nix run .#templates-check` is untouched by this work (no catalogue change) and
is not required here.

**Live, on a nixarchy desktop**, per AGENTS.md "Verifying live": `nix build`,
`cp -rL result ~/.config/omarchy/plugins/nixarchy.devenv`, `chmod -R u+w`,
`omarchy-shell shell rescanPlugins`, `omarchy-restart-shell`, wait for
`omarchy-shell shell ping`, check `qs log -i <instance>` for errors. Then drive
the #9 reproduction: create `t1` and `t2` under a `mktemp -d` root **inside an
existing project root** (so no setting changes), list them in the menu, `mv`
`t2` over `t1`'s path from another terminal, confirm the removal — expect the
refusal and both trees intact. Remove `t1`/`t2` through the plugin when done.
Never point a removal test at a real project, and check `hyprctl layers -j` for
`nixarchy-devenv-menu` before any `wtype`.

## Rollback

The branch is six commits on `fix/9-removal-identity`, each self-contained.

- Whole branch: `git revert --no-commit <first>..<last> && git commit`, or drop
  the branch before merge. Nothing outside `pkgs/cli.sh`, `Model.js`,
  `DevenvState.qml`, `tests/` and the three docs files is touched; no schema,
  no `flake.nix` `files` list, no catalogue, no state on disk. A revert restores
  the old behaviour exactly — including the three defects.
- Single steps: step 6 (docs), step 5 (final verify + stub arm + its two tests)
  and step 4 (`guardRoots`) revert cleanly on their own. Step 3 reverts on its
  own. Step 2 does **not**: reverting it alone leaves step 3's tests calling
  `--ident`. Revert steps 3 and 2 together, or revert 2 and re-run the CLI
  suite before pushing.

**`--ident` is a CLI contract change — this is the point, not a side effect.**
The packaged plugin and the `nixarchy-devenv` on the shell's PATH are installed
separately, so they can skew:

- **New plugin, old CLI** (plugin updated, `~/.local/bin` symlink stale): the
  plugin sends `--ident DEV:INO`; the old CLI has no such arm, falls through to
  `-*) die 1 "unknown option --ident"`, and exits 1. Nothing is deleted. The
  panel shows the CLI's stderr.
- **Old plugin, new CLI**: the plugin sends `--dev N`; the new CLI's explicit
  skew arm exits 1 with `--dev is gone; the plugin calling this is older than
  the command. Update the plugin.` Nothing is deleted. This arm exists precisely
  so the failure names the cause instead of reading as "unknown option".
- **Either skew, `list` and every other subcommand**: unaffected. Only removal
  stops working, and it stops working by refusing.

Both directions fail closed, and both are fixed by bringing the two halves to
the same revision — rebuild and re-link the CLI
(`nix build .#cli -o <gcroot>`) and re-copy the plugin folder.

`--root` becoming required for `remove` breaks any hand-written script that
called `remove` without one; such a script was deleting with the root guard
disarmed, which is #10. It exits 1 and deletes nothing until a `--root` is
added.
