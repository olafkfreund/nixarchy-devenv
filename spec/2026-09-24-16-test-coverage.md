---
status: draft
issue: 16
intent: intent/2026-09-24-16-test-coverage.md
---

# Spec: the refusals and branches the rules require are actually tested

Baseline confirmed by running the suites read-only: `node --test 'tests/model/*.test.js'`
passes 7/7 files (all Model.js assertions green), and
`bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
prints `cli: 62 passed, 0 failed` on this machine (`HOSTTYPE` is not
`x86_64`, so the Android template — and the count in the intent — is one
lower here; the delta is expected, not a regression).

## Design

Two independent groups of new tests, landed as two changes (see "ordering"
below). All new tests live in `tests/cli.sh`; no new files, no new harness.

### Group A — the four #16 refusals (no stub changes)

Added next to the existing removal-refusal block, `tests/cli.sh:276-303`,
right after "remove: a root given as a symlink" (line 287) or "remove: dev
mismatch" (line 288) — anywhere in that run of `expect 2 "remove: ..."`
lines, since each is independent and uses the already-built `$R`, `mkproj`,
`dev_of`, `rm_cli`.

1. **`remove: devenv.nix is a symlink`**
   ```sh
   s=$(mktemp -d "$R/root/s.XXXX")
   ln -s /nonexistent-target "$s/devenv.nix"
   expect 2 "remove: devenv.nix is a symlink" -- rm_cli --tier files --confirm "$s" --dev "$(dev_of "$s")" "$s"
   ```
   Assert: `grep -q "has no devenv.nix of its own" "$root/err"` (the exact
   refusal text at `pkgs/cli.sh:510`) and `[ -L "$s/devenv.nix" ]` (the link
   itself untouched — this refusal must fire before anything is deleted).
   This is the one the intent calls out explicitly: today only "absent" is
   tested (`pkgs/cli.sh:510`'s `[ -f ... ] && [ ! -L ... ]` has two failure
   shapes and only one has a test).

2. **`remove: target contains HOME`**
   The check at `pkgs/cli.sh:504` (`case "$home/" in "$dir"/*)`) fires when
   `$dir` is an *ancestor* of `$HOME`, not merely a substring. In the harness
   `$HOME` is `$root/home`, so `$root` itself is such an ancestor, and it is
   safe to point the CLI at it because the refusal fires (see the ordering
   note below) before any `rm`:
   ```sh
   expect 2 "remove: target contains HOME" -- rm_cli --tier files --confirm "$root" --dev "$(dev_of "$root")" "$root"
   ```
   Assert: `grep -q "contains your home directory" "$root/err"`.
   This exercises a different line from the existing "remove: HOME" test
   (`tests/cli.sh:281`, which is the `$dir == $home` exact-match branch at
   `pkgs/cli.sh:503`) — the ancestor branch has never run.

3. **`remove: target does not exist`**
   ```sh
   missing="$R/root/does-not-exist-$$"
   expect 2 "remove: target does not exist" -- rm_cli --tier files --confirm "$missing" --dev 0 "$missing"
   ```
   Assert: `grep -q "does not exist" "$root/err"` (`pkgs/cli.sh:498`,
   `realpath -e` failing). No fixture is created; the directory must not
   exist for the test to mean anything.

4. **`remove: target is /`**
   ```sh
   expect 2 "remove: target is /" -- rm_cli --tier folder --confirm / --dev "$(dev_of /)" /
   ```
   Assert: `grep -q "refused: /\." "$root/err"` (`pkgs/cli.sh:500`). This is
   safe to actually run: the `[ "$dir" != / ]` check is the very first thing
   after the confirm/canon checks, ahead of the HOME check, the root check,
   the devenv.nix check, `cmd_status`, and `devenv revoke` — nothing that
   touches the filesystem runs before it refuses. See Risks for why this
   ordering matters to the test's safety and must not silently change.

### Group B — the #24 branches (needs the stub hook + one `mkproj` change)

**Stub failure hook.** Single variable, `STUB_FAIL`, naming the *operation*
that should fail — not one variable per subcommand. In `tests/stub/devenv`,
insert right after the existing log line (`tests/stub/devenv:5`) and before
the `case "$1" in`:
```sh
if [ "${STUB_FAIL:-}" = "$1" ]; then
  echo "stub devenv: $1 failed" >&2
  exit 1
fi
```
The call is still logged to `$STUB_LOG` before the check (the log line stays
first), so a forced failure still shows up as an attempted call, matching
real command behaviour. `STUB_FAIL=revoke` fails `devenv revoke` while
`devenv processes list` (status, called from inside `cmd_remove`) keeps
answering whatever `$STUB_PROCESSES` says; `STUB_FAIL=init` fails `devenv
init` before it writes any files.

In `tests/stub/nix`, same variable, but nix's `$1` is a flag
(`--extra-experimental-features`), not the operation name, so the check
reuses the existing `case " $* " in *" run "*)` matching already used for
the success path (`tests/stub/nix:6`):
```sh
if [ "${STUB_FAIL:-}" = run ]; then
  case " $* " in
    *" run "*) echo "stub nix: run failed" >&2; exit 1 ;;
  esac
fi
```
Both defaults are `unset`, so the default stub is unchanged: every existing
test that never sets `STUB_FAIL` sees exactly today's success path. Nothing
about the PATH construction changes, so the "never reach the real
devenv/nix" guarantee is untouched — this only adds a branch *inside* the
fake binaries tests already control.

**`mkproj` parameterisation for a symlinked `.devenv`.** Today (`tests/cli.sh:262-269`)
`mkproj` always makes `.devenv` a real directory. Add an optional second
argument, defaulting to today's behaviour, so no existing call site (all of
which pass one argument) changes:
```sh
mkproj() {
  local d="$R/root/$1" devkind="${2:-dir}"
  mkdir -p "$d/src"
  echo '{ }' >"$d/devenv.nix"; echo 'inputs: {}' >"$d/devenv.yaml"; echo '{}' >"$d/devenv.lock"
  echo python >"$d/.devenv-template"; echo code >"$d/src/main.py"
  echo 'use devenv' >"$d/.envrc"
  case "$devkind" in
    dir)
      mkdir -p "$d/.devenv/state/db" "$d/.devenv/profile"
      echo data >"$d/.devenv/state/db/x"
      ;;
    symlink)
      mkdir -p "$R/elsewhere/$1.devenv-target"
      ln -s "$R/elsewhere/$1.devenv-target" "$d/.devenv"
      ;;
  esac
  echo "$d"
}
```
`mkproj a` (or any single-argument call) is byte-identical to today. `mkproj
e symlink` is the new shape, used only by the new test below.

**New tests:**

5. **`no args prints help`** — dispatch's `"${1:-help}"` (`pkgs/cli.sh:555`).
   ```sh
   expect 0 "no args prints help" -- "$cli"
   grep -q "nixarchy-devenv init" "$root/out" || bad "no args: help text on stdout"
   ```

6. **`help`**, **`-h`**, **`--help`** — three separate `expect 0` calls
   (`$cli help`, `$cli -h`, `$cli --help`), each asserting
   `grep -q "Templates:" "$root/out"`. Kept as three tests, not one, because
   they are three distinct tokens matched by one `case` arm
   (`pkgs/cli.sh:562`) and a future edit could drop one of the three without
   the others noticing.

7. **`unknown command`**
   ```sh
   expect 1 "unknown command" -- "$cli" bogus
   grep -q "unknown command 'bogus'." "$root/err" || bad "unknown command: names it"
   ```
   (`pkgs/cli.sh:563`.)

8. **Unknown `-*` option, one per subcommand** — four tests, each its own
   `die 1` call site:
   ```sh
   expect 1 "init unknown option" -- with_devenv "$cli" init --bogus python
   grep -q "unknown option --bogus" "$root/err" || bad "init: unknown option named"
   ```
   ```sh
   p2=$(fresh)
   expect 1 "new unknown option" -- with_devenv "$cli" new --bogus --parent "$p2" --name z python
   grep -q "unknown option --bogus" "$root/err" || bad "new: unknown option named"
   ```
   ```sh
   expect 1 "list unknown option" -- "$cli" list --json --bogus
   grep -q "unknown argument --bogus" "$root/err" || bad "list: unknown argument named"
   ```
   (Note the wording differs on purpose: `pkgs/cli.sh:134`/`253`/`487` say
   "unknown option", `pkgs/cli.sh:327` says "unknown argument" — the
   assertions must match each site's actual string, not a shared one.)
   ```sh
   expect 1 "remove unknown option" -- with_devenv "$cli" remove --bogus --tier files --confirm x --dev 1 x
   grep -q "unknown option --bogus" "$root/err" || bad "remove: unknown option named"
   ```
   One flag per subcommand, not a matrix of bogus flags — four cheap,
   independent branch-coverage tests, not a fuzz suite (see Alternatives
   rejected).

9. **Personal template: `devenv.yaml` already exists**
   ```sh
   d=$(fresh)
   echo 'already: here' >"$d/devenv.yaml"
   expect 0 "init personal keeps existing devenv.yaml" -- bash -c "cd '$d' && '$cli' init --no-git mine"
   grep -q 'already: here' "$d/devenv.yaml" || bad "personal: existing devenv.yaml untouched"
   grep -q 'kept the existing devenv.yaml' "$root/err" || bad "personal: says so"
   [ -f "$d/devenv.nix" ] || bad "personal: devenv.nix still copied"
   ```
   Exercises `pkgs/cli.sh:196-198`, the branch the existing "init personal"
   test (`tests/cli.sh:141`) never reaches because its target directory
   starts empty.

10. **Personal template: valid JSON, wrong version** — run as its own
    `templates --json` call, after the existing personal-templates block, so
    it doesn't disturb the counts and warning-grep the existing test
    already asserts (`tests/cli.sh:77-81`):
    ```sh
    mkdir -p "$XDG_CONFIG_HOME/nixarchy-devenv/templates/oldver"
    echo '{ }' >"$XDG_CONFIG_HOME/nixarchy-devenv/templates/oldver/devenv.nix"
    echo '{"version":2,"label":"Old"}' >"$XDG_CONFIG_HOME/nixarchy-devenv/templates/oldver/template.json"
    expect 0 "templates with wrong-version personal" -- "$cli" templates --json
    jq -e 'map(select(.id=="oldver")) == []' "$root/out" >/dev/null || bad "wrong version: not listed"
    ```
    Do **not** also assert a warning is printed for `oldver` — see Risks:
    `jq`'s `select(.version == 1)` on a non-matching document exits 0 with
    no output, so the `|| echo … not version 1 JSON` warning at
    `pkgs/cli.sh:65` is dead code as written; the template is silently
    dropped. The test pins the *observed* behaviour (silently absent from
    the list), not the comment's claimed behaviour.

11. **Generator path when `nix` is missing**
    ```sh
    mkdir -p "$root/nonix"
    ln -s "$here/stub/devenv" "$root/nonix/devenv"
    with_no_nix() { PATH="$root/nonix:$base_path" "$@"; }
    d=$(fresh)
    expect 3 "generator without nix" -- with_no_nix bash -c "cd '$d' && '$cli' init cloud aws"
    grep -q "nix is not installed" "$root/err" || bad "generator: names nix as missing"
    ```
    `with_no_nix` is built by hand (only `devenv` symlinked in, not `nix`)
    rather than by trimming `with_devenv`'s PATH at call time, so it can't
    accidentally include a real `nix` from `base_path` — `base_path` only
    ever has the fixed tool list at `tests/cli.sh:25`, which does not
    include `nix` or `devenv` (confirmed by reading that line), so this is
    already safe by construction.

12. **`devenv init` failing**
    ```sh
    d=$(fresh)
    expect 4 "devenv init fails" -- bash -c "cd '$d' && STUB_FAIL=init PATH='$here/stub:$base_path' '$cli' init --no-git python"
    grep -q "devenv init failed" "$root/err" || bad "init: names the failure"
    [ ! -e "$d/devenv.nix" ] || bad "init failure: nothing scaffolded"
    ```
    (`pkgs/cli.sh:174`.) `STUB_FAIL` is set inline on the `bash -c`, not via
    the `with_devenv` function, because `env VAR=x some_function` does not
    export into a shell function's later `PATH=... "$@"` the way it does for
    an external command — the variable has to be in scope for the `bash -c`
    subshell directly.

13. **Generator flake run failing**
    ```sh
    d=$(fresh)
    expect 4 "generator flake run fails" -- bash -c "cd '$d' && STUB_FAIL=run PATH='$here/stub:$base_path' '$cli' init cloud aws"
    grep -q "the 'cloud' generator failed" "$root/err" || bad "generator: names the failure"
    [ ! -e "$d/devenv.nix" ] || bad "generator failure: nothing scaffolded"
    ```
    (`pkgs/cli.sh:214-215`.)

14. **Removal: `.devenv` is a symlink**
    ```sh
    p=$(mkproj e symlink)
    expect 0 "remove: files tier with .devenv symlink" -- rm_cli --tier files --confirm "$p" --dev "$(dev_of "$p")" "$p"
    [ ! -L "$p/.devenv" ] || bad "removal: the symlink itself is gone"
    [ -d "$R/elsewhere/e.devenv-target" ] || bad "removal: the symlink's target is untouched"
    ```
    (`pkgs/cli.sh:536-537`.) The target must still exist afterward — that's
    the actual thing this branch protects against (a naive `rm -rf
    "$dir/.devenv"` would instead delete through the link).

15. **`cmd_status`'s `detail` content** — extend the existing "status fail"
    block (`tests/cli.sh:252-253`) rather than add a new `expect`, since the
    branch is already exercised:
    ```sh
    jq -e '.detail | test("boom")' "$root/out" >/dev/null || bad "status: fail detail names the stderr"
    ```
    The stub's `fail` case prints `error: boom` to stderr
    (`tests/stub/devenv:45`); `cmd_status`'s `detail` is `tail -n 3` of that
    output (`pkgs/cli.sh:460`), so this is a direct, stable assertion on
    content, not just the `state == "unknown"` branch shape.

### Ordering

Group A lands first, on its own: it needs no stub changes, no `mkproj`
change, and it is what the existing AGENTS.md rule ("every refusal has a
filesystem test") already requires today — closing it doesn't wait on any
design decision. Group B lands second, since it depends on the stub hook and
`mkproj` change being reviewed and in place.

### Are the dispatch/usage-error branches worth testing?

Yes, keep them in scope — tests 5-8. They're one-line assertions each (no
fixtures, no stub involvement for 5-7; one flag for 8), and they pin the
exact exit codes (0 vs 1) and messages the QML plugin's own error handling
would otherwise silently drift under refactoring. The "boilerplate" framing
undersells them: `help`/`-h`/`--help`/bare-invocation is the same one-line
`case` arm collapsing three tokens into one behaviour, and an unintentional
edit dropping one of the three tokens is exactly the kind of regression a
documented rule exists to catch, just like the four #16 refusals. Writing
them off in AGENTS.md would need its own justification for *why* dispatch
is exempt from "every refusal has a filesystem test" when it plainly has
refusals (`die 1` on bad usage) — there isn't a good one. Recommendation:
test them, don't write anything off.

## Alternatives rejected

- **One env var per failing subcommand** (`STUB_REVOKE_FAIL`,
  `STUB_INIT_FAIL`, …). Rejected: doesn't scale (a new var for every future
  failure path this suite wants to reach), and duplicates the same
  one-line gate per var for no benefit over a single variable naming the
  operation.
- **Making the stub fail `revoke`/`allow`/`version` unconditionally**, so
  tests have to opt into success instead of failure. Rejected: violates the
  intent's explicit constraint that "the default stub stays honest about the
  success path," and would touch nearly every existing removal test that
  currently relies on `revoke` quietly succeeding.
- **Fuzzing every subcommand with many different bogus flags.** Rejected:
  one flag per subcommand already exercises the distinct `-*)` (or
  `*)`) branch at each call site; more flags exercise the same line
  repeatedly and add nothing but noise, which the team lead flagged as a
  real cost to weigh.
- **Writing off the dispatch/usage-error branches in AGENTS.md as exempt
  boilerplate.** Rejected (see "Are the dispatch/usage-error branches worth
  testing?" above) — they are cheap and are real refusals.
- **Reaching a genuine failure via the real `devenv`/`nix`** (e.g. a
  deliberately broken pinned generator revision) instead of a stub hook.
  Rejected: breaks the "tests must never reach the real devenv or nix" and
  "runnable without network" constraints outright.
- **A dangling (target-less) symlink for the `.devenv` symlink test.**
  Rejected: the point of the test is to prove the *target* survives
  (nothing followed through the link and deleted it); a dangling symlink
  can't demonstrate that.

## Risks

- **The "not version 1 JSON" warning in `personal_json` (`pkgs/cli.sh:56-66`)
  looks unreachable as written.** Verified directly: `jq -c 'select(.version
  == 1) | {...}'` against a document whose `.version` is not `1` exits `0`
  with empty output — it does not fail, so the `|| echo … "not version 1
  JSON"` branch never runs. Test 10 asserts the *actual* behaviour (silently
  dropped from the list, not necessarily warned about) rather than the
  comment's claimed behaviour. This is a real discrepancy between the code
  and its own comment; flagging it here is in scope for a WHAT-level spec,
  fixing it is not — a maintainer should decide separately whether the
  warning is meant to fire and, if so, file that as its own issue.
- **The `STUB_LOG` write happens before the new `STUB_FAIL` gate in both
  stubs**, so a forced failure still appears in the log as an attempted
  call. This is deliberate (a real failing command still ran) and any
  future edit to the stubs must keep the log line first, or tests 12-13
  silently stop proving what they claim to prove.
- **Test 4 (`remove: target is /`) actually invokes the CLI with `/` as an
  argument.** It is safe only because the `[ "$dir" != / ]` check
  (`pkgs/cli.sh:500`) runs before the HOME check, the root check, the
  devenv.nix check, `cmd_status`, and `devenv revoke` — nothing mutating
  runs first. If a future edit reorders `cmd_remove`'s checks so something
  else runs before the `/` guard, this test would need re-auditing before
  it can be trusted to still be inert; call this out in review of that
  future change, not something to guard against now.
- **Test 2 (`remove: target contains HOME`) reuses `$root` itself** (the
  suite's own temp root, holding `home/`, `bin/`, every `p.XXXX` fixture
  directory created so far) as the refused target. Safe only because the
  refusal fires before any mutation (same ordering argument as above) — it
  must not be converted into a positive (non-refusing) test later without
  moving off `$root`.
- **`with_no_nix` (test 11) must not accidentally pick up a real `nix`.**
  Verified by reading `tests/cli.sh:25` (`base_path`'s fixed tool list) —
  it contains no `nix` or `devenv`, so a PATH of `$root/nonix:$base_path`
  with only `devenv` symlinked in is nix-free by construction, not by
  omission.

## Verification

- `node --test 'tests/model/*.test.js'` — unaffected by this change (no
  `Model.js` edits), must stay green.
- `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
  — must print `cli: N passed, 0 failed` where `N` is today's count (62 on
  this machine, 63 on `x86_64`) plus the 19 new assertions' `expect` calls
  added here (4 in Group A, 15 in Group B — test 6 counts as three `expect`
  calls, test 8 as four; test 15 adds an assertion to an existing `expect`
  and does not add to the count). `fail` must be `0`.
- `nix flake check` — must still pass (runs both suites plus the manifest,
  entry-point, no-symlink and no-hex-colour checks); no template, manifest,
  or QML file changes are made, so only the two test-suite runs above are
  actually at risk.
- `nix run .#templates-check` is out of scope: nothing here touches
  `data/templates.nix` or the preset catalogue.
