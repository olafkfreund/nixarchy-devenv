---
status: draft
issue: 21
spec: spec/2026-09-24-21-cli-robustness.md
---

# Plan: the CLI degrades honestly when devenv's output is not what we expect

Two independent defects in `pkgs/cli.sh`, fixed as two commits:

- **#21** `splice_preset`'s brace-not-found fallback (`pkgs/cli.sh:111-126`, called at
  `pkgs/cli.sh:175`): when no column-zero `}` exists in the `devenv init`-written
  `devenv.nix`, `close=$(grep -n '^}' devenv.nix | tail -1 | cut -d: -f1)` yields an
  empty string (`cut` exits 0 on empty input). `$((close - 1))` evaluates as `$((-1))`
  (bash treats an empty arithmetic operand as `0`), `head -n -1` is valid GNU syntax
  ("all but the last line") and succeeds silently, so the failure actually surfaces one
  line later at `tail -n +"$close"` → `tail: invalid number of lines: '+'`, which trips
  errexit under `writeShellApplication`'s `set -euo pipefail` and aborts `cmd_init`
  mid-splice, leaving a stray `devenv.nix.new` and an unspliced `devenv.nix`. **On the
  sibling base `fix/8`, the same defect surfaces differently**: that branch uses
  `sed -i "${close}r $file"`-style addressing (`"-1r"` with an empty `close` interpreted
  as `-1`), so the line that actually errors differs — note this so a rebase onto/from
  `fix/8` isn't a surprise, but this plan's diff targets `main`'s `head`/`cat`/`tail`
  shape exactly as shown above.

  Decision (approved, not revisited here): **refuse, do not append at EOF.** Preset
  lines are devenv options valid only inside the top-level attrset devenv's scaffold
  opens; appending after the last line is appending outside that attrset — either a
  Nix parse error or, worse, a file that looks scaffolded but silently doesn't
  evaluate. Refuse instead, reusing the existing "paste these lines by hand" message
  shape (`pkgs/cli.sh:150-161`, the "already exists" refusal), and exit **4** — not 2 —
  because `devenv init` has already mutated the directory by this point (`pkgs/cli.sh:
  173-174`), so this is "the thing we ran/depend on didn't behave" (4), not "refused
  before touching anything" (2). Leave `devenv.nix` exactly as `devenv init` wrote it:
  unspliced but evaluable. `cmd_new`'s existing `rc != 0` cleanup path
  (`pkgs/cli.sh:276-281`) already removes the partial directory for the `new` caller;
  nothing new is needed there.

- **#22** the process-row pattern in `cmd_status` (`pkgs/cli.sh:452`): matches on the
  literal word `restarts:` alone, so `garbage running restarts: nope` (three
  space-separated fields ending in a non-numeric literal) is misread as a real process
  row, making `state: "running"` when AGENTS.md's rule ("only `name status restarts: N`
  rows are processes; anything else is `unknown`, never `running`") says it must not be.

  Decision (approved): require the restart count to be present and numeric, and anchor
  the end of the line: `restarts:[[:space:]]*[0-9]+[[:space:]]*$`. Verified in this task
  against real devenv 2.3.1 on this machine (`devenv processes list` while a real
  `sleep 1000` process ran) — the genuine row `dev                            ready restarts: 0`
  still matches; `garbage running restarts: nope` no longer does; devenv's own progress
  lines (`• Validating lock`, `✓ …`) never matched either pattern. The `jq` `capture()`
  step just below (`pkgs/cli.sh:454-456`) only reads `name`/`status` and is unaffected —
  it only ever sees rows the tightened `grep` already approved, so it needs no change.

Both defects preserve the existing fail-safe classification: anything unrecognised
stays `unknown`, and `unknown` continues to refuse removal (`cmd_status`'s `else`
branch, `pkgs/cli.sh:459-461`, is untouched).

**Out of scope, explicitly:** a standing, automated integration check that asserts real
devenv's `processes list` output shape (open question 3 in the intent). The
real-devenv sample above is reported as manual evidence in the spec, not encoded as a
test — `tests/cli.sh` only runs against the stub, and `nix run .#templates-check`
scaffolds and evaluates presets but never runs `devenv up`/`processes list`. Building
that check means either adding a live process-manager cycle to `templates-check`
(which is explicitly hermetic re: `HOME`/`XDG_*`/`DEVENV_*` and never runs processes
today) or standing up a new integration check with its own network/hermeticity story —
more than this fix needs. File it as a separate follow-up issue after this lands; do
not build it as part of this task.

## Steps

1. `pkgs/cli.sh`: in `splice_preset` (lines 111-126), change the `else` branch's
   brace-not-found case from silently underflowing into a corrupt splice, to returning
   failure (`return 1`) when `close` is empty, leaving `devenv.nix` untouched:

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
       head -n "$((close - 1))" devenv.nix >devenv.nix.new
       cat "$file" >>devenv.nix.new
       tail -n +"$close" devenv.nix >>devenv.nix.new
       mv devenv.nix.new devenv.nix
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
     head -n "$((close - 1))" devenv.nix >devenv.nix.new
     cat "$file" >>devenv.nix.new
     tail -n +"$close" devenv.nix >>devenv.nix.new
     mv devenv.nix.new devenv.nix
   }
   ```

   Then change the call site (currently `pkgs/cli.sh:175`, inside the `preset)` case
   of `cmd_init`) to check the return value and refuse:

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

   Verify by: `bash -n pkgs/cli.sh` (syntax), then the new stub-driven tests in step 3.

2. `tests/stub/devenv`: add a `STUB_INIT_NO_BRACE=1` mode to the `init` case, following
   the existing `STUB_INIT_NIXPKGS=1` convention, that writes a `devenv.nix` with no
   placeholder comment and no column-zero `}` (put the closing brace indented, so the
   file still parses as a here-doc but has zero column-zero `}` lines to grep):

   Before (inside `case "$1" in init) … esac`, right after the existing `cat >devenv.nix`
   heredoc and before the `STUB_INIT_NIXPKGS` line):
   ```sh
   init)
     cat >devenv.nix <<'NIX'
   { pkgs, lib, config, inputs, ... }:

   {
     packages = [ pkgs.git ];

     # https://devenv.sh/languages/
     # languages.rust.enable = true;

     # processes.dev.exec = "ls";
   }
   NIX
   ```

   After:
   ```sh
   init)
     if [ "${STUB_INIT_NO_BRACE:-}" = 1 ]; then
       cat >devenv.nix <<'NIX'
   { pkgs, lib, config, inputs, ... }: { packages = [ pkgs.git ];
     # processes.dev.exec = "ls";
     }
   NIX
     else
       cat >devenv.nix <<'NIX'
   { pkgs, lib, config, inputs, ... }:

   {
     packages = [ pkgs.git ];

     # https://devenv.sh/languages/
     # languages.rust.enable = true;

     # processes.dev.exec = "ls";
   }
   NIX
     fi
   ```

   (The `STUB_INIT_NO_BRACE` scaffold has neither the placeholder comment nor a `}` at
   column zero — its closing `}` is indented two spaces — so it exercises exactly the
   "no column-zero brace" path.) The rest of `init)` (writing `devenv.yaml`,
   `STUB_INIT_NIXPKGS`, `.gitignore`) is unchanged and still runs for both branches.

   Verify by: `bash -n tests/stub/devenv`.

## Tests

Both changes are covered in `tests/cli.sh` (run as
`bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`).
Current pass count before this change: every `expect`/`bad` call in the file counts
as one assertion via `ok`/`bad`; there is no single printed total today (the script
just reports `FAIL: …` lines and a nonzero exit on any failure) — the check here is
"no new `FAIL:` lines, same as before, plus N more `ok` calls from the added
assertions," not a specific numeric total.

**#21 — add after the existing `init twice refuses` block (around `tests/cli.sh:112`,
right after the `android` preset section, so it sits with the other `init` edge
cases, before the `# ---- new ----` section):**

```sh
# A scaffold with no column-zero '}' must refuse, not corrupt the file.
d=$(fresh)
expect 4 "init refuses when devenv writes no column-zero brace" -- \
  with_devenv env STUB_INIT_NO_BRACE=1 bash -c "cd '$d' && '$cli' init --no-git python"
grep -q "no closing '}' at column zero" "$root/err" || bad "no-brace refusal names the problem"
grep -q 'languages.python' "$root/err" || bad "no-brace refusal prints the lines to paste"
grep -qE '^\{ pkgs, lib, config, inputs, \.\.\.\}: \{ packages' "$d/devenv.nix" || bad "no-brace refusal: devenv.nix left as devenv init wrote it"
! grep -q 'languages.python' "$d/devenv.nix" || bad "no-brace refusal: preset lines were not spliced in"
[ ! -e "$d/devenv.nix.new" ] || bad "no-brace refusal: no stray devenv.nix.new left behind"

# new's existing cleanup-on-failure path removes the partial directory too.
p=$(fresh)
expect 4 "new under no-brace stub removes the partial directory" -- \
  with_devenv env STUB_INIT_NO_BRACE=1 "$cli" new --no-git --parent "$p" --name bad python
[ ! -e "$p/bad" ] || bad "no-brace refusal via new: partial directory removed"
grep -q "removed the partial directory" "$root/err" || bad "no-brace refusal via new: says so"
```

Assertions added: `init refuses when devenv writes no column-zero brace` (exit 4),
plus 4 `bad`-guarded checks (message names the problem, message prints preset lines,
`devenv.nix` untouched, no splice happened, no stray `.new` file), and
`new under no-brace stub removes the partial directory` (exit 4) plus 2 more checks
(directory gone, cleanup message present). 8 new assertions total.

Also confirm the **existing** brace-fallback (placeholder absent, ordinary trailing
`}` at column zero) still passes unchanged — no new fixture needed for it today: no
existing template's preset lines omit the `# languages.*.enable = true;` placeholder,
so the brace-fallback's *success* path currently has no dedicated test to pin. Do not
add one speculatively here (it is not part of what #21 touches); if a future template
needs it, add it then.

**#22 — extend the existing `status` block (`tests/cli.sh:244-256`):**

```sh
expect 0 "status: malformed restarts is not a running process" -- with_devenv env STUB_PROCESSES=malformed "$cli" status --json "$S"
jq -e '.state == "unknown"' "$root/out" >/dev/null || bad "status: malformed row classified unknown, not running"
```

placed directly after the existing `STUB_PROCESSES=running` block (line 245) so both
the genuine-row and malformed-row cases sit together. Requires a `malformed` mode in
`tests/stub/devenv`'s `processes)` case (added alongside `running`/`noise`/`stopped`):

```sh
malformed) printf 'garbage                        running restarts: nope\n' ;;
```

This exercises exactly the malformed case from the intent/spec (`garbage running
restarts: nope`) with exit 0 and a row shaped like a real one except for the
non-numeric count.

The **existing** `STUB_PROCESSES=running` assertion at `tests/cli.sh:245` already is
the genuine-row regression test — `web ready restarts: 0` / `db running restarts: 1`
must still classify as `running` after the pattern is tightened; no new fixture
needed, just confirm it still passes (it will, since both rows end in a digit).

Assertions added: `status: malformed restarts is not a running process` (exit 0) plus
1 `bad`-guarded check (`state == "unknown"`). 2 new assertions total.

**Run after each commit:**

```sh
bash -n pkgs/cli.sh tests/stub/devenv tests/cli.sh
node tests/run.js                              # unaffected (no Model.js change) — must still show 0 failures
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"   # 0 new FAIL: lines
nix flake check                                # shellcheck over cli.sh via writeShellApplication must stay clean
```

## Rollback

Two commits, independent, either revertible alone without affecting the other:

- **Commit 1 (#21):** `git revert` the commit touching `pkgs/cli.sh`'s `splice_preset`/
  call-site and `tests/stub/devenv`'s `STUB_INIT_NO_BRACE` mode plus the two new
  `tests/cli.sh` assertions. Reverting restores the pre-fix silent-underflow behavior
  (the known bug) with no effect on #22's fix or tests, since they touch disjoint lines
  (`splice_preset`/`cmd_init`'s preset case vs. `cmd_status`'s `grep` pattern).
- **Commit 2 (#22):** `git revert` the commit touching `cmd_status`'s `grep` pattern in
  `pkgs/cli.sh`, `tests/stub/devenv`'s `malformed` mode, and the new `tests/cli.sh`
  assertion. Reverting restores the pre-fix loose pattern with no effect on #21.

No data migration, no schema, no lockfile changes in either commit — a plain `git
revert <sha>` per commit is sufficient and complete.
