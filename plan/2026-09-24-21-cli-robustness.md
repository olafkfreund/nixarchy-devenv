---
status: approved
issue: 21
spec: spec/2026-09-24-21-cli-robustness.md
---

# Plan: the CLI degrades honestly when devenv's output is not what we expect

Rebased onto `main` at `e254c82` (post-#8 merge). #8 changed `splice_preset`'s
fallback from a `head`/`cat`/`tail` rewrite to a single `sed -i "${close}-1r $file"`-
style insert — the mechanism this plan fixes is the *current* main shape, not the
older head/tail one.

Two independent defects in `pkgs/cli.sh`, fixed as two commits:

- **#21** `splice_preset`'s brace-not-found fallback (`pkgs/cli.sh:111-123`, called
  bare — no `||` — at `pkgs/cli.sh:172`, inside `cmd_init`'s `preset)` case):

  ```sh
  splice_preset() {
    local file=$1 placeholder close
    placeholder='^[[:space:]]*# languages\.[a-z0-9]+\.enable = true;[[:space:]]*$'
    if grep -qE "$placeholder" devenv.nix; then
      sed -i -E "/$placeholder/{
        r $file
        d
      }" devenv.nix
    else
      close=$(grep -n '^}' devenv.nix | tail -1 | cut -d: -f1)
      sed -i "$((close - 1))r $file" devenv.nix
    fi
  }
  ```

  When no column-zero `}` exists, `grep -n '^}'` prints nothing but `cut` still
  exits 0 on empty input, so `close=""`. `$((close - 1))` evaluates as `$((-1))`
  (bash treats an empty arithmetic operand as `0`), so `sed -i "-1r $file" devenv.nix`
  runs. Because the script argument starts with `-`, GNU sed's getopt reparses it
  as options instead of a script — confirmed on this machine (`sed -i "-1r
  /tmp/t.nix" /tmp/t.nix`): exit 1, `sed: invalid option -- '1'` plus a usage
  dump, never reaching the `r`/insert behavior at all. `sed` exits non-zero,
  which trips errexit under `writeShellApplication`'s `set -euo pipefail` and
  aborts `cmd_init` mid-splice. `devenv.nix` is whatever `devenv init` wrote,
  untouched by the failed `sed -i` (sed operates on a temp file and only replaces
  the original on success), so there is no corruption today — but the command dies
  with an opaque sed error instead of a clear message, and (per the call site,
  below) the wrong exit code.

  Decision (approved, carried over unchanged): **refuse, do not append at EOF.**
  Preset lines are devenv options valid only inside the top-level attrset devenv's
  scaffold opens; appending after the last line would be appending outside that
  attrset — either a Nix parse error or, worse, a file that looks scaffolded but
  silently doesn't evaluate. Refuse instead, reusing the existing "paste these
  lines by hand" message shape (`pkgs/cli.sh:150-161`, the "already exists"
  refusal), and exit **4** — not 2 — because `devenv init` has already mutated the
  directory by this point (`pkgs/cli.sh:169-170`), so this is "the thing we
  ran/depend on didn't behave" (4), not "refused before touching anything" (2).
  Leave `devenv.nix` exactly as `devenv init` wrote it: unspliced but evaluable.
  `cmd_new`'s existing cleanup path (`pkgs/cli.sh:266-273`) already removes the
  partial directory for the `new` caller and already preserves the inner exit
  code (`cmd_init` runs inside a subshell, `(cd "$dir" && cmd_init ...) || rc=$?`,
  so `cmd_init`'s `exit 4` becomes the subshell's exit status, captured as
  `rc=4`, then re-raised via `die "$rc" ...`) — nothing new is needed there,
  confirmed by reading `cmd_new` (`pkgs/cli.sh:243-273`).

  **Call site must change too.** `splice_preset "$share/presets/$tpl.nix"` is
  called bare, no `||`, at `pkgs/cli.sh:172`. Under `set -e`, a function
  returning non-zero as the last command of a simple statement (not part of an
  `if`/`&&`/`||`/`!`) DOES trigger errexit — so today, if `splice_preset` failed,
  the script would already abort right there with the function's own exit
  status (whatever `sed`'s failure produced, not our intended 4). The fix must
  wrap the call in an `if ! splice_preset ...; then` so (a) errexit does not fire
  on the bare call and (b) the refusal path controls its own exit code (4) and
  message instead of leaking `sed`'s.

- **#22** the process-row pattern in `cmd_status` (`pkgs/cli.sh:434-438`): matches
  on the literal word `restarts:` alone —

  ```sh
  rows=$(printf '%s\n' "$out" | grep -E '^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+restarts:' || true)
  ```

  — so `garbage running restarts: nope` (three space-separated fields ending in a
  non-numeric literal) is misread as a real process row, making `state:
  "running"` when AGENTS.md's rule ("only `name status restarts: N` rows are
  processes; anything else is `unknown`, never `running`") says it must not be.

  Decision (approved, unchanged): require the restart count to be present and
  numeric, and anchor the end of the line:
  `restarts:[[:space:]]*[0-9]+[[:space:]]*$`. Verified in this task against real
  devenv 2.3.1 on this machine (`devenv processes list` while a real `sleep 1000`
  process ran) — the genuine row `dev  ready restarts: 0` still matches;
  `garbage running restarts: nope` no longer does; devenv's own progress lines
  (`• Validating lock`, `✓ …`) never matched either pattern. The `jq` `capture()`
  step just below (`pkgs/cli.sh:439-441`) only reads `name`/`status` and is
  unaffected — it only ever sees rows the tightened `grep` already approved, so
  it needs no change.

Both defects preserve the existing fail-safe classification: anything
unrecognised stays `unknown`, and `unknown` continues to refuse removal
(`cmd_status`'s final `else` branch is untouched).

**Out of scope, explicitly:** a standing, automated integration check that
asserts real devenv's `processes list` output shape (open question 3 in the
intent). The real-devenv sample above is reported as manual evidence in the
spec, not encoded as a test — `tests/cli.sh` only runs against the stub, and
`nix run .#templates-check` scaffolds and evaluates presets but never runs
`devenv up`/`processes list`. Building that check means either adding a live
process-manager cycle to `templates-check` (explicitly hermetic re:
`HOME`/`XDG_*`/`DEVENV_*`, and never runs processes today) or standing up a new
integration check with its own network/hermeticity story — more than this fix
needs. File it as a separate follow-up issue after this lands; do not build it
as part of this task.

## Steps

1. `pkgs/cli.sh`: in `splice_preset` (lines 111-123), make the brace-not-found
   case return failure instead of feeding an empty `close` to `sed`:

   Before:
   ```sh
   splice_preset() {
     local file=$1 placeholder close
     placeholder='^[[:space:]]*# languages\.[a-z0-9]+\.enable = true;[[:space:]]*$'
     if grep -qE "$placeholder" devenv.nix; then
       sed -i -E "/$placeholder/{
         r $file
         d
       }" devenv.nix
     else
       close=$(grep -n '^}' devenv.nix | tail -1 | cut -d: -f1)
       sed -i "$((close - 1))r $file" devenv.nix
     fi
   }
   ```

   After:
   ```sh
   splice_preset() {
     local file=$1 placeholder close
     placeholder='^[[:space:]]*# languages\.[a-z0-9]+\.enable = true;[[:space:]]*$'
     if grep -qE "$placeholder" devenv.nix; then
       sed -i -E "/$placeholder/{
         r $file
         d
       }" devenv.nix
       return 0
     fi
     close=$(grep -n '^}' devenv.nix | tail -1 | cut -d: -f1) || true
     if [ -z "$close" ]; then
       return 1
     fi
     sed -i "$((close - 1))r $file" devenv.nix
   }
   ```

   Then change the call site (`pkgs/cli.sh:172`, inside `cmd_init`'s `preset)`
   case) from a bare call to a checked one:

   Before:
   ```sh
       devenv init || die 4 "devenv init failed."
       splice_preset "$share/presets/$tpl.nix"
   ```

   After:
   ```sh
       devenv init || die 4 "devenv init failed."
       if ! splice_preset "$share/presets/$tpl.nix"; then
         {
           echo "nixarchy-devenv: devenv init wrote a devenv.nix nixarchy-devenv doesn't recognise (no closing '}' at column zero)."
           echo "Add the '$tpl' lines by hand:"
           echo
           sed 's/^/  /' "$share/presets/$tpl.nix"
         } >&2
         exit 4
       fi
   ```

   Verify by: `bash -n pkgs/cli.sh` (syntax), then the new stub-driven tests in
   step 2/Tests.

2. `tests/stub/devenv`: add a `STUB_INIT_NO_BRACE=1` mode to the `init` case,
   matching the file's existing `STUB_INIT_NOPLACEHOLDER`/`STUB_INIT_NIXPKGS`
   convention (a post-processing `sed`/`printf` step on the same heredoc output,
   not a second heredoc branch) — strip the placeholder AND rewrite the closing
   `}` so it is no longer at column zero:

   Before (the two existing post-processing lines, right after the `devenv.yaml`
   heredoc):
   ```sh
     # STUB_INIT_NOPLACEHOLDER=1: a scaffold without the commented language
     # line, so the preset takes the splice's fallback path.
     if [ "${STUB_INIT_NOPLACEHOLDER:-}" = 1 ]; then sed -i '/# languages\.rust\.enable/d' devenv.nix; fi
     if [ "${STUB_INIT_NIXPKGS:-}" = 1 ]; then printf 'nixpkgs:\n  allow_broken: false\n' >>devenv.yaml; fi
   ```

   After (new line added alongside them, same style):
   ```sh
     # STUB_INIT_NOPLACEHOLDER=1: a scaffold without the commented language
     # line, so the preset takes the splice's fallback path.
     if [ "${STUB_INIT_NOPLACEHOLDER:-}" = 1 ]; then sed -i '/# languages\.rust\.enable/d' devenv.nix; fi
     # STUB_INIT_NO_BRACE=1: neither the placeholder nor a '}' at column
     # zero, so the splice has nowhere safe to land and must refuse.
     if [ "${STUB_INIT_NO_BRACE:-}" = 1 ]; then
       sed -i -e '/# languages\.rust\.enable/d' -e 's/^}$/  }/' devenv.nix
     fi
     if [ "${STUB_INIT_NIXPKGS:-}" = 1 ]; then printf 'nixpkgs:\n  allow_broken: false\n' >>devenv.yaml; fi
   ```

   (Indenting the closing `}` by two spaces removes the only column-zero `}` in
   the scaffold — `grep -n '^}'` then matches nothing — while keeping the file's
   own shape otherwise identical to the ordinary scaffold, so the test isolates
   exactly the "no column-zero brace" condition and nothing else.)

   Verify by: `bash -n tests/stub/devenv`.

## Tests

Current baseline (confirmed on this `main`): `cli: 63 passed, 0 failed`
(`tests/cli.sh`) and `node --test 'tests/model/*.test.js'` → 70 pass (unaffected —
no `Model.js` change in this task; `tests/run.js` no longer exists on this main).

**#21 — add right after the existing fallback-splice test block
(`tests/cli.sh:94-99`, the `STUB_INIT_NOPLACEHOLDER` block), before the
`expect 2 "init twice refuses"` line:**

```sh
# A scaffold with neither the placeholder nor a column-zero '}' must refuse,
# not hand devenv.nix to sed with an empty address.
d3=$(fresh)
expect 4 "init refuses when devenv writes no column-zero brace" -- \
  with_devenv env STUB_INIT_NO_BRACE=1 bash -c "cd '$d3' && '$cli' init --no-git python"
grep -q "no closing '}' at column zero" "$root/err" || bad "no-brace refusal names the problem"
grep -q 'languages.python' "$root/err" || bad "no-brace refusal prints the lines to paste"
! grep -q 'languages.python' "$d3/devenv.nix" || bad "no-brace refusal: preset lines were not spliced in"
grep -q '^  }$' "$d3/devenv.nix" || bad "no-brace refusal: devenv.nix left exactly as devenv init wrote it"

# new's existing cleanup-on-failure path removes the partial directory too.
p3=$(fresh)
expect 4 "new under no-brace stub removes the partial directory" -- \
  with_devenv env STUB_INIT_NO_BRACE=1 "$cli" new --no-git --parent "$p3" --name bad python
[ ! -e "$p3/bad" ] || bad "no-brace refusal via new: partial directory removed"
grep -q "removed the partial directory" "$root/err" || bad "no-brace refusal via new: says so"
```

Assertions added: 2 `expect` calls (exit 4 each) + 5 `bad`-guarded checks = 7 new
assertions. (No duplicate of #8's `STUB_INIT_NOPLACEHOLDER` success-path test —
that one already pins the *working* fallback splice; this covers only the new
*refusal* path, a disjoint stub mode.)

**#22 — extend the existing `status` block. Current running-row assertion is at
`tests/cli.sh:251-252`:**

```sh
expect 0 "status running" -- with_devenv env STUB_PROCESSES=running "$cli" status --json "$S"
jq -e '.state == "running" and (.processes | map(.name) == ["web","db"])' "$root/out" >/dev/null || bad "status: running parsed"
```

Add directly after it:

```sh
expect 0 "status: malformed restarts is not a running process" -- with_devenv env STUB_PROCESSES=malformed "$cli" status --json "$S"
jq -e '.state == "unknown"' "$root/out" >/dev/null || bad "status: malformed row classified unknown, not running"
```

and add a `malformed` case to `tests/stub/devenv`'s `processes)` block, alongside
the existing `running`/`noise`/`stopped`/`hang`/`fail` cases:

```sh
malformed) printf 'garbage                        running restarts: nope\n' ;;
```

This reproduces exactly the malformed case named in the intent/spec (`garbage
running restarts: nope`), exit 0, shaped like a real row except for the
non-numeric count. The existing `STUB_PROCESSES=running` assertion at
`tests/cli.sh:251-252` is the genuine-row regression check — `web ready restarts:
0` / `db running restarts: 1` must still classify `running` after tightening;
both rows already end in a digit, so no change needed there, just confirm it
still passes.

Assertions added: 1 `expect` (exit 0) + 1 `bad`-guarded check = 2 new assertions.

**Run after each commit:**

```sh
bash -n pkgs/cli.sh tests/stub/devenv tests/cli.sh
node --test 'tests/model/*.test.js'            # unaffected — must still show 70 pass
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"   # 65 passed, 0 failed after commit 1; 66 passed, 0 failed after commit 2 (baseline 63 + 2 + 1... see below)
nix flake check                                # shellcheck over cli.sh via writeShellApplication must stay clean
```

Exact expected counts: baseline is `63 passed, 0 failed`. Commit 1 (#21) adds 7
assertions → `70 passed, 0 failed`. Commit 2 (#22) adds 2 more → `72 passed, 0
failed`. (`tests/cli.sh`'s own pass/fail counter increments once per `ok`/`bad`
call, matching the assertions listed above one-for-one — recount from the
script's own `pass=$((pass + 1))` calls if these totals drift before
implementation, since another change could land on `main` first.)

## Rollback

Two commits, independent, either revertible alone without affecting the other:

- **Commit 1 (#21):** `git revert` the commit touching `pkgs/cli.sh`'s
  `splice_preset` function and its `cmd_init` call site, `tests/stub/devenv`'s
  `STUB_INIT_NO_BRACE` mode, and the two new `tests/cli.sh` assertions.
  Reverting restores the pre-fix behavior (a bare `sed -i "-1r $file"` call that
  fails with an opaque sed error and the wrong exit code on an unbraced
  scaffold) with no effect on #22's fix or tests — disjoint lines
  (`splice_preset`/`cmd_init`'s preset case vs. `cmd_status`'s `grep` pattern).
- **Commit 2 (#22):** `git revert` the commit touching `cmd_status`'s `grep`
  pattern in `pkgs/cli.sh`, `tests/stub/devenv`'s `malformed` mode, and the new
  `tests/cli.sh` assertion. Reverting restores the pre-fix loose pattern with no
  effect on #21.

No data migration, no schema, no lockfile changes in either commit — a plain
`git revert <sha>` per commit is sufficient and complete.
