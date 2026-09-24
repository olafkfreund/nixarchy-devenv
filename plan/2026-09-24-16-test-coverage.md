---
status: draft
issue: 16
spec: spec/2026-09-24-16-test-coverage.md
---

# Plan: the refusals and branches the rules require are actually tested

Closes #16, #24. Rebased onto `main` at `e254c82` (merge of #26/#8) — the
base this plan originally targeted no longer exists. Re-verified directly on
that commit before writing this revision:

- `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
  → `cli: 63 passed, 0 failed` (not 62 — #8 added one test of its own, the
  fallback-splice test using `STUB_INIT_NOPLACEHOLDER`).
- `node --test 'tests/model/*.test.js'` → `pass 70` (not 62/70 confusion —
  `tests/run.js` is gone, only the Node suite remains).
- `tests/stub/devenv` already carries `STUB_INIT_NIXPKGS`,
  `STUB_INIT_NOPLACEHOLDER`, `STUB_PROCESSES`, `STUB_LOG` — the stub-hook
  family this plan adds to (`STUB_INIT_FAIL`, `STUB_REVOKE_FAIL`) must slot
  into that existing structure, not reinvent it.
- `rm_cli()` (`tests/cli.sh:278`) is now `with_devenv "$cli" remove "$@"` —
  no default `STUB_PROCESSES` any more (the default removed by #8, as the
  spec anticipated). Every removal test in this plan that needs a specific
  process state sets `STUB_PROCESSES` explicitly, so none of them relied on
  the old default.
- No #8 test covers any of the branches this plan targets — #8's new
  coverage is entirely the fallback-splice path (`STUB_INIT_NOPLACEHOLDER`),
  which is unrelated to Group A's removal refusals or Group B's dispatch /
  personal-template / missing-`nix` / revoke-failure / `.devenv`-symlink
  branches. Nothing here is now redundant.

Two independent groups land as separate commits in `tests/cli.sh` (plus two
stub files and one helper change for Group B), no production code changes:

- **Group A** (standalone, first): the four `cmd_remove` refusals AGENTS.md's
  "every refusal has a filesystem test" rule requires and today lacks —
  `devenv.nix` is a symlink, the target contains `$HOME` (ancestor case, not
  the exact-match case already tested), the target does not exist, the
  target is `/`. No stub or `mkproj` changes.
- **Group B** (after Group A): the #24 dispatch/usage-error branches, two
  personal-template branches, the missing-`nix` generator path, and three
  removal branches that need a new stub failure hook (`devenv init`,
  `devenv revoke`, and the generator's `nix run`, each a per-behaviour
  boolean matching the existing `STUB_PROCESSES`/`STUB_INIT_NIXPKGS`/
  `STUB_INIT_NOPLACEHOLDER` family) plus a `mkproj` parameter for a
  symlinked `.devenv`.

All new stub behaviour defaults to unset = today's honest-success path,
verified inert by re-running the suite unchanged after each stub/helper
edit, before any test that flips a flag is added.

**A note on the count below.** Re-deriving the verification arithmetic
line-by-line from the spec's own numbered list (tests 5–16) gives **16** new
`expect` calls in Group B (1+3+1+4+1+1+1+1+1+1+1+0), not the "17" the spec's
Verification section states — the spec's own per-test breakdown sums to 16;
"17" appears to be an arithmetic slip in that section, not a different test
count. This plan uses the recomputed 16, on top of the **re-verified 63**
baseline (not the spec's 62, which was `main`'s count before #8 merged), so
the final target is **83 passed** (63 + 4 Group A + 16 Group B) — note this
now happens to equal the spec's old (wrong-derivation) number for a
different reason; don't take that as confirmation, the count has moved
twice for two unrelated reasons (rebase, then arithmetic). **Treat the
actual `cli: N passed, M failed` line as ground truth over any number in
this plan or the spec** — if a commit's real count differs from the one
given here, stop and diff against the expected new `expect` call-sites
before continuing, don't just edit the number and move on.

## Steps

1. **`tests/cli.sh`, Group A — four removal refusals.** Insert after the
   existing `expect 2 "remove: dev mismatch" ...` line (currently line 295,
   right before `mkdir -p "$R/root/plain"`), using the already-defined `$R`,
   `mkproj`, `dev_of`:
   ```sh
   s=$(mktemp -d "$R/root/s.XXXX")
   ln -s /nonexistent-target "$s/devenv.nix"
   expect 2 "remove: devenv.nix is a symlink" -- rm_cli --tier files --confirm "$s" --dev "$(dev_of "$s")" "$s"
   grep -q "has no devenv.nix of its own" "$root/err" || bad "remove: devenv.nix symlink names the refusal"
   [ -L "$s/devenv.nix" ] || bad "remove: devenv.nix symlink: the link itself untouched"

   expect 2 "remove: target contains HOME" -- rm_cli --tier files --confirm "$root" --dev "$(dev_of "$root")" "$root"
   grep -q "contains your home directory" "$root/err" || bad "remove: target contains HOME names the refusal"

   missing="$R/root/does-not-exist-$$"
   expect 2 "remove: target does not exist" -- rm_cli --tier files --confirm "$missing" --dev 0 "$missing"
   grep -q "does not exist" "$root/err" || bad "remove: target does not exist names the refusal"

   expect 2 "remove: target is /" -- rm_cli --tier folder --confirm / --dev "$(dev_of /)" /
   grep -q "refused: /\." "$root/err" || bad "remove: target is / names the refusal"
   ```
   Refusal text and check order verified directly against current
   `pkgs/cli.sh:465-497` (`cmd_remove`): symlink refusal at line 496
   ("has no devenv.nix of its own"), HOME-ancestor refusal at line 490
   ("contains your home directory"), missing-target refusal at line 484
   ("does not exist"), `/`-refusal at line 486 ("refused: /.") — and that
   `[ "$dir" != / ]` (486) runs before the HOME checks (489-490), the root
   checks (491-494), the `devenv.nix` check (496), `cmd_status` (502), and
   `devenv revoke` (509-510), so test 4 is safe (see Safety).
   Verify by: `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
   prints `cli: 67 passed, 0 failed` (63 + 4). `node --test 'tests/model/*.test.js'`
   is untouched, still `pass 70`.
   Commit: `test(cli): the four missing removal refusals (#16, step 1)`.

2. **`tests/stub/devenv` — add the failure hooks, no behaviour change yet.**
   Current file already has `STUB_INIT_NIXPKGS` and `STUB_INIT_NOPLACEHOLDER`
   checks inside the `init)` arm and a combined `allow | revoke | version) ;;`
   arm at the end. Add `STUB_INIT_FAIL` as the very first line of the
   `init)` arm, before the `cat >devenv.nix` heredoc (matching the shape of
   the two existing `init`-scoped flags, just checked earliest since it
   short-circuits everything else in the arm):
   ```sh
   init)
     if [ "${STUB_INIT_FAIL:-}" = 1 ]; then echo "stub devenv: init failed" >&2; exit 1; fi
     cat >devenv.nix <<'NIX'
   ```
   Split `revoke` out of the combined arm at the end:
   ```sh
   revoke)
     if [ "${STUB_REVOKE_FAIL:-}" = 1 ]; then echo "stub devenv: revoke failed" >&2; exit 1; fi
     ;;
   allow | version) ;;
   ```
   Both flags read with `${VAR:-}` so unset stays exactly today's path; the
   `$STUB_LOG` write (line 5, `echo "$PWD :: $*" >>"$STUB_LOG"`) stays
   first, ahead of every flag check including the two pre-existing ones and
   both new ones, so a forced failure still logs an attempted call (needed
   by steps 9 and 11's assertions later — do not reorder this).
   Verify by: re-run the full suite with no new tests yet — must still
   print `cli: 67 passed, 0 failed` (unchanged from step 1; this step is
   additive and inert with both new vars unset).
   Commit: `test(cli): add STUB_INIT_FAIL and STUB_REVOKE_FAIL to the devenv stub (#24, step 2)`.

3. **`tests/stub/nix` — add `STUB_RUN_FAIL`, no behaviour change yet.** In
   the `*" run "*)` arm, insert as its first line, before the `printf '{ }\n'
   >devenv.nix`:
   ```sh
   *" run "*)
     if [ "${STUB_RUN_FAIL:-}" = 1 ]; then echo "stub nix: run failed" >&2; exit 1; fi
     printf '{ }\n' >devenv.nix
   ```
   Same rule: the `$STUB_LOG` write (line 5) stays first.
   Verify by: still `cli: 67 passed, 0 failed`.
   Commit: `test(cli): add STUB_RUN_FAIL to the nix stub (#24, step 3)`.

4. **`tests/cli.sh` — `mkproj` takes an optional second arg.** Replace the
   current `mkproj()` (currently lines 269–276):
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
   Every existing single-argument call (`mkproj a`, `mkproj b`, `mkproj c`,
   `mkproj d`) is byte-identical to before — same files, same
   `.devenv/state/db/x`, same `.devenv/profile`. No new call site yet.
   Verify by: still `cli: 67 passed, 0 failed` — confirms the refactor
   changed nothing observable for `dir` (the default).
   Commit: `test(cli): mkproj takes an optional dir|symlink second arg (#24, step 4)`.

5. **`tests/cli.sh` — dispatch and usage-error branches (spec tests 5–8).**
   Add near the top of the test body, after the `fresh()` helper definition
   (line 49) and before the `# ---- templates ----` section, since these
   need only `$cli` and no fixtures:
   ```sh
   # ---- dispatch -----------------------------------------------------------------

   expect 0 "no args prints help" -- "$cli"
   grep -q "nixarchy-devenv init" "$root/out" || bad "no args: help text on stdout"

   for h in help -h --help; do
     expect 0 "$h" -- "$cli" "$h"
     grep -q "Templates:" "$root/out" || bad "$h: prints templates"
   done

   expect 1 "unknown command" -- "$cli" bogus
   grep -q "unknown command 'bogus'." "$root/err" || bad "unknown command: names it"

   expect 1 "init unknown option" -- with_devenv "$cli" init --bogus python
   grep -q "unknown option --bogus" "$root/err" || bad "init: unknown option named"

   p2=$(fresh)
   expect 1 "new unknown option" -- with_devenv "$cli" new --bogus --parent "$p2" --name z python
   grep -q "unknown option --bogus" "$root/err" || bad "new: unknown option named"

   expect 1 "list unknown option" -- "$cli" list --json --bogus
   grep -q "unknown argument --bogus" "$root/err" || bad "list: unknown argument named"

   expect 1 "remove unknown option" -- with_devenv "$cli" remove --bogus --tier files --confirm x --dev 1 x
   grep -q "unknown option --bogus" "$root/err" || bad "remove: unknown option named"
   ```
   Wording verified against current line numbers: `list` says "unknown
   argument" (`pkgs/cli.sh:312`), `init`/`new`/`remove` say "unknown option"
   (`pkgs/cli.sh:131`, `250`, `473`) — match each site's actual string, they
   differ on purpose.
   9 new `expect` calls (1 + 3 + 1 + 4).
   Verify by: `cli: 76 passed, 0 failed` (67 + 9).
   Commit: `test(cli): cover the dispatch and usage-error branches (#24, step 5)`.

6. **`tests/cli.sh` — personal template keeps an existing `devenv.yaml`
   (spec test 9).** Add after the existing personal-templates block (the
   "templates with personal" / skip-warning assertions, currently ending at
   line 81), before the `# ---- init ----` section:
   ```sh
   d=$(fresh)
   echo 'already: here' >"$d/devenv.yaml"
   expect 0 "init personal keeps existing devenv.yaml" -- bash -c "cd '$d' && '$cli' init --no-git mine"
   grep -q 'already: here' "$d/devenv.yaml" || bad "personal: existing devenv.yaml untouched"
   grep -q 'kept the existing devenv.yaml' "$root/err" || bad "personal: says so"
   [ -f "$d/devenv.nix" ] || bad "personal: devenv.nix still copied"
   ```
   Needs the `mine` personal template already set up by the templates
   section (has both `devenv.nix` and `devenv.yaml`, at lines 69–76), and
   the refusal text checked against `pkgs/cli.sh:194`
   ("kept the existing devenv.yaml"). +1 `expect`.
   Verify by: `cli: 77 passed, 0 failed`.
   Commit: `test(cli): personal init keeps an existing devenv.yaml (#24, step 6)`.

7. **`tests/cli.sh` — personal template, valid JSON, wrong version (spec
   test 10).** Add as its own `templates --json` call, right after step 6's
   test (or anywhere after the templates section, before it disturbs
   nothing already asserted there):
   ```sh
   mkdir -p "$XDG_CONFIG_HOME/nixarchy-devenv/templates/oldver"
   echo '{ }' >"$XDG_CONFIG_HOME/nixarchy-devenv/templates/oldver/devenv.nix"
   echo '{"version":2,"label":"Old"}' >"$XDG_CONFIG_HOME/nixarchy-devenv/templates/oldver/template.json"
   expect 0 "templates with wrong-version personal" -- "$cli" templates --json
   jq -e 'map(select(.id=="oldver")) == []' "$root/out" >/dev/null || bad "wrong version: not listed"
   ```
   Do not also assert a warning for `oldver` — `jq`'s `select(.version == 1)`
   exits 0 with empty output on a non-match, so the "not version 1 JSON"
   `echo` at `pkgs/cli.sh:65` is dead code; pin the observed behaviour
   (silently dropped), not the comment's claim. Leave that as a Risk, do not
   fix it here (see Risks). +1 `expect`.
   Verify by: `cli: 78 passed, 0 failed`.
   Commit: `test(cli): a wrong-version personal template is silently dropped (#24, step 7)`.

8. **`tests/cli.sh` — generator path when `nix` is missing (spec test
   11).** Add in the init section, right after the "init cloud aws gcp"
   test block (currently lines 141–145), before "init personal" (147–150):
   ```sh
   mkdir -p "$root/nonix"
   ln -s "$here/stub/devenv" "$root/nonix/devenv"
   with_no_nix() { PATH="$root/nonix:$base_path" "$@"; }
   d=$(fresh)
   expect 3 "generator without nix" -- with_no_nix bash -c "cd '$d' && '$cli' init cloud aws"
   grep -q "nix is not installed" "$root/err" || bad "generator: names nix as missing"
   ```
   `need()`'s generic branch (`pkgs/cli.sh:33`, `*) die 3 "$1 is not
   installed, and this needs it."`) is what fires for `nix` (only `devenv`
   gets the special-cased message) — exit code 3, message contains "nix is
   not installed". `with_no_nix` is built by hand (only `devenv` symlinked
   in) rather than trimming `with_devenv`'s PATH at call time — `base_path`
   (`tests/cli.sh:28`) only ever holds the fixed tool list
   (`tests/cli.sh:25`), which has no `nix` or `devenv` in it, so this is
   nix-free by construction, not by omission. This does **not** touch or
   loosen the existing `base_path`/`with_devenv` PATH guarantee — it only
   adds a third, narrower PATH variant alongside them. +1 `expect`.
   Verify by: `cli: 79 passed, 0 failed`.
   Commit: `test(cli): the generator path when nix is missing (#24, step 8)`.

9. **`tests/cli.sh` — `devenv init` failing (spec test 12).** Add in the
   init section, right after the "no devenv" test block (currently lines
   136–139), before "init cloud aws gcp" (141–145), using the
   `STUB_INIT_FAIL` hook from step 2:
   ```sh
   d=$(fresh)
   expect 4 "devenv init fails" -- with_devenv env STUB_INIT_FAIL=1 bash -c "cd '$d' && '$cli' init --no-git python"
   grep -q "devenv init failed" "$root/err" || bad "init: names the failure"
   [ ! -e "$d/devenv.nix" ] || bad "init failure: nothing scaffolded"
   ```
   Matches `pkgs/cli.sh:171` (`devenv init || die 4 "devenv init failed."`).
   +1 `expect`.
   Verify by: `cli: 80 passed, 0 failed`.
   Commit: `test(cli): devenv init failing is a refusal, nothing scaffolded (#24, step 9)`.

10. **`tests/cli.sh` — generator flake run failing (spec test 13).** Add
    right after step 9's test (or anywhere in the generator tests), using
    `STUB_RUN_FAIL` from step 3:
    ```sh
    d=$(fresh)
    expect 4 "generator flake run fails" -- with_devenv env STUB_RUN_FAIL=1 bash -c "cd '$d' && '$cli' init cloud aws"
    grep -q "the 'cloud' generator failed" "$root/err" || bad "generator: names the failure"
    [ ! -e "$d/devenv.nix" ] || bad "generator failure: nothing scaffolded"
    ```
    Matches `pkgs/cli.sh:211-212`. +1 `expect`.
    Verify by: `cli: 81 passed, 0 failed`.
    Commit: `test(cli): a failing generator flake run scaffolds nothing (#24, step 10)`.

11. **`tests/cli.sh` — `devenv revoke` failing, removal still proceeds
    (spec test 14).** Add in the remove section, after the existing
    successful-removal tests (after "remove: without devenv" at line
    328–330, before the closing `echo "cli: $pass passed..."`), using
    `STUB_REVOKE_FAIL` from step 2. Uses `mkproj f` (a fresh, ordinary
    project, `dir` kind — the default):
    ```sh
    p=$(mkproj f)
    expect 0 "remove: revoke fails, removal still proceeds" -- \
      with_devenv env STUB_PROCESSES=stopped STUB_REVOKE_FAIL=1 "$cli" remove --tier files --confirm "$p" --dev "$(dev_of "$p")" "$p"
    grep -q "devenv revoke failed; continuing" "$root/err" || bad "revoke failure: warned, not fatal"
    [ ! -e "$p/devenv.nix" ] || bad "revoke failure: removal still happened"
    ```
    `rm_cli` (`tests/cli.sh:278`) no longer defaults `STUB_PROCESSES` (that
    default was removed by #8), so calling this test through the plain
    `with_devenv env ... "$cli" remove ...` form shown above (not through
    `rm_cli`) is correct either way — `STUB_PROCESSES=stopped` is set
    explicitly regardless. Matches `pkgs/cli.sh:510`
    ("devenv revoke failed; continuing"). +1 `expect`.
    Verify by: `cli: 82 passed, 0 failed`.
    Commit: `test(cli): a failed devenv revoke warns but does not block removal (#24, step 11)`.

12. **`tests/cli.sh` — `.devenv` is a symlink (spec test 15).** Add
    alongside step 11, using the `mkproj ... symlink` variant from step 4:
    ```sh
    p=$(mkproj e symlink)
    expect 0 "remove: files tier with .devenv symlink" -- rm_cli --tier files --confirm "$p" --dev "$(dev_of "$p")" "$p"
    [ ! -L "$p/.devenv" ] || bad "removal: the symlink itself is gone"
    [ -d "$R/elsewhere/e.devenv-target" ] || bad "removal: the symlink's target is untouched"
    ```
    `mkproj e symlink` can safely be called through the plain `rm_cli`
    helper (`with_devenv "$cli" remove "$@"`) since this test doesn't need a
    forced stub failure — it needs the normal (unset) `STUB_PROCESSES`
    default, which `cmd_status` treats as `stopped` regardless of `rm_cli`
    no longer forcing it (the stub's own `${STUB_PROCESSES:-stopped}`
    default, `tests/stub/devenv`, still applies when the caller sets
    nothing at all). +1 `expect`.
    Verify by: `cli: 83 passed, 0 failed`.
    Commit: `test(cli): removing a project with .devenv as a symlink spares the target (#24, step 12)`.

13. **`tests/cli.sh` — extend the existing "status fail" assertion (spec
    test 16).** No new `expect` call; add one `jq` assertion to the
    existing `expect 0 "status fail" ...` block (currently lines 259–260):
    ```sh
    jq -e '.detail | test("boom")' "$root/out" >/dev/null || bad "status: fail detail names the stderr"
    ```
    Matches `pkgs/cli.sh:446` (`cmd_status`'s `detail` is `tail -n 3` of the
    stub's `error: boom` stderr from the `fail` case,
    `tests/stub/devenv:45`). +0 `expect` calls (extends an existing one).
    Verify by: still `cli: 83 passed, 0 failed` (same call count, one more
    assertion inside it — if it were going to fail it would show as the
    existing "status fail" test failing, not a new failure line).
    Commit: `test(cli): pin cmd_status's detail field to the stderr tail (#24, step 13)`.

## Tests

Run after every commit:
```sh
node --test 'tests/model/*.test.js'
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
```
Expected `node` result throughout: `pass 70`, `fail 0` (no `Model.js` changes
anywhere in this plan; `tests/run.js` no longer exists on this base).

Expected `cli:` line after each step:

| Step | Change | `cli: N passed, 0 failed` |
| --- | --- | --- |
| baseline (re-verified on `e254c82`) | — | 63 |
| 1 | Group A (4 refusals) | 67 |
| 2 | stub devenv hooks (inert) | 67 |
| 3 | stub nix hook (inert) | 67 |
| 4 | mkproj param (inert) | 67 |
| 5 | dispatch/usage-error (9) | 76 |
| 6 | personal keeps devenv.yaml | 77 |
| 7 | wrong-version personal | 78 |
| 8 | generator without nix | 79 |
| 9 | devenv init fails | 80 |
| 10 | generator run fails | 81 |
| 11 | revoke fails | 82 |
| 12 | .devenv symlink | 83 |
| 13 | status detail (no new `expect`) | 83 |

**Final: `cli: 83 passed, 0 failed`** (63 baseline + 4 Group A + 16 Group B).
`fail` must be `0` at every step — if a step reports any failure, stop and
fix that step before moving to the next; do not accumulate failing tests
across commits.

Also run once, after the last commit, to confirm nothing else regressed:
```sh
nix flake check
```
This re-runs both suites plus the manifest/entry-point/no-symlink/no-hex-colour
checks; no template, manifest, or QML file is touched by this plan, so only
the two suites above are actually at risk. `nix run .#templates-check` is out
of scope — nothing here touches `data/templates.nix`.

## Rollback

Each step is its own commit touching one file (steps 1, 5–13: `tests/cli.sh`
only; step 2: `tests/stub/devenv`; step 3: `tests/stub/nix`; step 4:
`tests/cli.sh`). To roll back any single step, `git revert` that commit —
every later commit in this plan only *appends* `expect` calls or extends an
existing assertion, it never depends on the specific line positions of an
earlier step's new tests, so a revert from the top of the stack down is
always safe, and a revert of an early step (e.g. step 2) requires first
reverting any later step that uses the hook it added (steps 9 and 11 use
`STUB_INIT_FAIL`/`STUB_REVOKE_FAIL` from step 2; step 10 uses `STUB_RUN_FAIL`
from step 3; steps 6/7/9/10/11/12 all sit after step 5 but do not depend on
it, so step 5 can be reverted independently of them).

Steps 2–4 (the stub hooks and `mkproj` parameterisation) are additive and
inert on their own: every existing call site is unchanged, and both new stub
flags default unset, reading `${VAR:-}` so an unset flag is indistinguishable
from today's stub (which already reads `${STUB_INIT_NIXPKGS:-}` and
`${STUB_INIT_NOPLACEHOLDER:-}` the same way). Reverting steps 2–4 alone
(without reverting steps 9–12, which use them) would break the build —
always revert the consuming test step first, or revert the whole stack from
the top down.

## Safety

- Every removal test in this plan (steps 1, 11, 12) points only at
  directories under the suite's own `mktemp -d` root (`$root`, `$R`, and
  paths under `$R/root`/`$R/elsewhere`) or at the harness's own `$HOME`
  (itself `$root/home`, never the invoking user's `$HOME` —
  `tests/cli.sh:15` exports it) — never at a real project. Test 4 in step 1
  (`remove: target is /`) is the one case that names `/` directly as the
  CLI's target; it is safe only because `pkgs/cli.sh:486`'s
  `[ "$dir" != / ]` check runs before every other check in `cmd_remove` —
  the HOME check (489-490), the root check (491-494), the `devenv.nix`
  check (496), `cmd_status` (502), and `devenv revoke` (509-510) — so
  nothing mutating runs first, verified by reading the current function top
  to bottom. This ordering is load-bearing for the test's safety; if a
  future change to `cmd_remove` reorders those checks, this test needs
  re-auditing before it can be trusted to stay inert.
- **The stub PATH guarantee is not loosened anywhere in this plan.** All
  three test binaries (`bash`, `env`, and the fixed tool list at
  `tests/cli.sh:25`) plus `$here/stub/devenv` and `$here/stub/nix` are the
  only things ever on `$PATH` during a test; step 8's `with_no_nix` adds a
  third PATH variant (`$root/nonix:$base_path`, `devenv` stubbed, `nix`
  absent) built the same way `with_devenv` already is, not by trimming or
  widening either existing one. `base_path` (`tests/cli.sh:28`) never
  contains `nix` or `devenv`, confirmed by reading its tool list
  (`tests/cli.sh:25`), so "no devenv"/"no nix" tests are nix/devenv-free by
  construction in every case in this plan, not by omission.

## Risks (carried from the spec, not fixed here)

- `pkgs/cli.sh:56-66`'s "not version 1 JSON" warning in `personal_json` is
  dead code as written (`jq`'s `select(.version == 1)` exits 0 with no
  output on a non-match, so the `|| echo … not version 1 JSON` branch never
  runs). Step 7's test pins the actual behaviour (silently dropped from the
  list) rather than the comment's claim. Fixing the dead branch is out of
  scope for this plan — flag it as a follow-up issue if a maintainer wants
  the warning to actually fire.
- The `STUB_LOG` write in both stubs must stay the first line, ahead of the
  existing `STUB_INIT_NIXPKGS`/`STUB_INIT_NOPLACEHOLDER` gates and the new
  `STUB_INIT_FAIL`/`STUB_REVOKE_FAIL`/`STUB_RUN_FAIL` gates (steps 2–3 keep
  it that way) — any future edit to either stub that moves the log write
  after a gate silently breaks the "a forced failure still shows up in the
  log as an attempted call" property steps 9, 10 and 11 rely on.
- This plan was written and verified against `main` at `e254c82`. If `main`
  moves again before implementation starts, re-run both suites and re-diff
  the touched line numbers before trusting any number or line reference in
  this plan — it has already had to be corrected once for exactly this
  reason.
