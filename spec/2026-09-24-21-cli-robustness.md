---
status: draft
issue: 21
intent: intent/2026-09-24-21-cli-robustness.md
---

# Spec: the CLI degrades honestly when devenv's output is not what we expect

## Design

### #21 — `splice_preset`'s fallback (`pkgs/cli.sh:107-126`)

Current fallback branch:

```sh
close=$(grep -n '^}' devenv.nix | tail -1 | cut -d: -f1)
head -n "$((close - 1))" devenv.nix >devenv.nix.new
cat "$file" >>devenv.nix.new
tail -n +"$close" devenv.nix >>devenv.nix.new
mv devenv.nix.new devenv.nix
```

`close` is meant to be the line number of the scaffold's closing `}` — the
preset's lines get spliced in just above it, landing *inside* the top-level
attrset. When no column-zero `}` exists, `grep -n` prints nothing but `cut`
still exits 0 on empty input, so `close=""` and errexit does not trip there.
`$((close - 1))` then evaluates as `$((-1))` (bash arithmetic treats an empty
operand as `0`). GNU `head -n -1` is itself valid syntax ("all but the last
line"), so `head` does not fail; it silently writes all-but-last-line of
`devenv.nix` into `devenv.nix.new`. The subsequent `tail -n +"$close"` with
`close=""` is what actually errors (`tail: invalid number of lines: '+'`),
which — with `writeShellApplication`'s `set -euo pipefail` wrapping `cli.sh`
— trips errexit and aborts `cmd_init` mid-splice. By that point
`devenv.nix.new` holds all-but-last-line of the scaffold plus the preset
(never renamed over `devenv.nix`, since `mv` never runs), and the original
`devenv.nix` is untouched but has no preset spliced in. `init`, run directly
in an existing directory, exits non-zero and leaves both files behind; `new`
cleans up via `cmd_new`'s `rc != 0` path (`pkgs/cli.sh:276-281`) because it
owns a directory it just created.

The fix does not depend on exactly which of `head`/`tail` trips first — the
underlying defect is the same either way: **`close` must never be allowed to
be empty**, and the recovery from "no column-zero brace" must not be silent
data corruption or a stray `devenv.nix.new` left on disk.

**Decision: refuse, not append at end-of-file.**

Appending at EOF is wrong on its own terms, not just louder-is-better: a
preset's `lines` are devenv *options* — `languages.foo.enable = true;` and
friends — that are only valid Nix inside the top-level attrset devenv's
scaffold opens with `{ pkgs, lib, config, inputs, ... }: { ... }`. The
closing `}` IS the end of that attrset. If there is no column-zero `}` to
splice before, we no longer know where the attrset ends (it could be
reformatted, multi-line, differently indented — anything). Appending text
after the file's last line is appending *outside* the attrset: the result is
either a Nix parse error (extra tokens after the top-level expression) or,
worse, silently valid-but-wrong Nix if the scaffold's shape changed in some
way we can't anticipate. Writing a devenv.nix that doesn't evaluate is worse
than refusing, because the user has already run `devenv init` (mutating their
directory) and the CLI would then hand back a file that looks scaffolded but
breaks on the first `devenv shell`.

So: when the placeholder comment is absent (checked first, unchanged) AND no
column-zero `}` is found, `splice_preset` refuses. `cmd_init` must not leave
the directory worse off than before the splice was attempted: `devenv init`
already ran and wrote `devenv.nix`/`devenv.yaml`/`.gitignore` (see
`tests/stub/devenv`'s `init` case) before `splice_preset` is called
(`pkgs/cli.sh:174-175`). On refusal, print the preset's lines for the user to
paste by hand — exactly the message already used at `pkgs/cli.sh:150-161`
for "a devenv.nix already exists" — and exit 4 (the code used elsewhere in
`cmd_init` for "the thing we ran/depend on didn't behave", e.g.
`pkgs/cli.sh:186`), not 2 (which means "we refused before touching
anything" — here we already wrote devenv.nix via `devenv init`, so 2 is
inaccurate). Leave the unspliced `devenv.nix` in place — it's what `devenv
init` produced, it evaluates fine, it's just missing the preset lines, which
is exactly the same state as the "already exists" refusal case, and the same
message format tells the user how to add them.

**Implementation shape** (illustrative, not final code — the plan writes the
exact diff):

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
    return 1   # signal: no column-zero brace found
  fi
  head -n "$((close - 1))" devenv.nix >devenv.nix.new
  cat "$file" >>devenv.nix.new
  tail -n +"$close" devenv.nix >>devenv.nix.new
  mv devenv.nix.new devenv.nix
}
```

and at the call site (`pkgs/cli.sh:175`):

```sh
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

This keeps `splice_preset` a pure file operation (no subshell string
building, no argv changes) and keeps the "never nowhere" comment true in
spirit: the preset either lands inside the attrset, or the command refuses
and says exactly why, rather than landing outside it or corrupting the file.
`$file` (a store path under `$share/presets`) is read twice on the refusal
path (existence already implied by templates.json/cli.nix producing it), no
new argv shape.

### #22 — process-row pattern (`pkgs/cli.sh:452`, `cmd_status`)

Current:

```sh
rows=$(printf '%s\n' "$out" | grep -E '^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+restarts:' || true)
```

AGENTS.md's rule: "Only `name status restarts: N` rows are processes; anything
else is `unknown`, never `running`." The pattern stops at the literal word
`restarts:` and never looks at what follows, so `garbage running restarts:
nope` (three space-separated fields ending in the literal, non-numeric
`nope`) matches and is counted as a process, making `state: running` even
though there is no numeric restart count after `restarts:`.

**Fix:** require the count to be present and numeric:

```sh
rows=$(printf '%s\n' "$out" | grep -E '^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+restarts:[[:space:]]*[0-9]+[[:space:]]*$')
```

Anchoring the end (`$`) also guards against trailing garbage after the
number, which the current pattern doesn't check either, and is the same
"nothing but a name/status/restarts: N row counts" rule the comment states,
made literal. The `capture()` in the `jq` step just below
(`pkgs/cli.sh:454-456`) already assumes `name` then `status` as the first two
whitespace-separated fields and doesn't touch the restart count, so it needs
no change — tightening the `grep` is sufficient and the two stay in sync
because the `jq` capture only ever sees rows the tightened `grep` already
approved.

**Real-devenv verification, done in this task:** `devenv` is on `PATH` here
(`command -v devenv` → `/run/current-system/sw/bin/devenv`, `devenv version`
→ `devenv 2.3.1 (x86_64-linux)`, matching the version AGENTS.md and the stub
comments already cite). I built a throwaway project under a temp dir
(outside any configured project root, never touched by `nixarchy-devenv`)
with:

```nix
{ pkgs, lib, config, inputs, ... }:
{
  packages = [ pkgs.git ];
  processes.dev.exec = "sleep 1000";
}
```

and a minimal `devenv.yaml` pinning `nixpkgs`. Two real captures:

1. No process manager running: `devenv processes list` → exit 1, stderr:
   `× No process manager is running. Start processes first with \`devenv up -d\``
   — byte-for-byte the message the stub and `cmd_status`'s `stopped` branch
   already expect (`pkgs/cli.sh:457`).
2. After `devenv up -d` and waiting for the process to start:
   `devenv processes list` → exit 0, stdout: `dev                            ready restarts: 0`
   — a real numeric restart count, right-padded name, single status word,
   confirming the pattern's shape (`name`, whitespace, `status`, whitespace,
   `restarts:`, whitespace, digits) against the live binary, not just the
   stub. I then ran `devenv processes down` and deleted the temp directory.

This sample does not, and cannot on its own, prove real devenv never emits a
non-numeric or missing count after `restarts:` — that would require either
reading devenv's source for every code path that writes that line, or a
much larger sampling exercise (mid-crash-loop states, etc.). But it does
confirm the tightened pattern accepts the one real row this task could
produce, which is the concrete risk the constraint calls out ("must not
start rejecting rows real devenv legitimately emits"). Nothing in devenv's
`process-compose`-based table format (name, status word, `restarts: N`)
suggests the count is ever anything but an integer — `process-compose`'s
restart counter is a Go `int`, always formatted as digits — so tightening to
`[0-9]+` is a safe narrowing, not a guess about an unrelated field.

## Alternatives rejected

- **#21: append the preset at end-of-file when no brace is found.** Rejected:
  produces a devenv.nix with option lines outside the top-level attrset —
  either a Nix parse error or, worse, a file that looks scaffolded but does
  not evaluate. Appending "keeps init working" only in the sense that the
  command exits 0; the actual deliverable (a working devenv.nix) is broken,
  which is worse than a clear refusal with paste-by-hand instructions.
- **#21: retry the placeholder-comment path with a looser regex instead of
  falling back to brace-finding at all.** Rejected: out of scope — the
  placeholder match is unrelated to this defect, and loosening it independently
  changes behavior for scaffolds that already splice correctly today.
- **#21: exit 2 (refused) instead of 4 (dependency/tool failure) on the
  brace-not-found path.** Rejected: 2 is documented as "any doubt is a
  refusal, nothing is touched" — but by this point `devenv init` already
  wrote `devenv.nix`, so something *was* touched by a command we ran that
  didn't behave as expected, which is exit 4's meaning per the header comment
  at `pkgs/cli.sh:12`.
- **#22: tighten by requiring the status word to come from a fixed enum
  (e.g. `ready|running|...`).** Rejected: devenv/process-compose status
  words are not enumerated anywhere in this repo or verified exhaustively
  against upstream, and hardcoding a partial list risks the "must not reject
  legitimate rows" constraint in the other direction — a real status word we
  haven't seen would now read as `unknown` instead of a process. Constraining
  the restart count (a stable, structurally-guaranteed integer) is safe;
  constraining the status vocabulary is not, without a much larger sample.
- **#22: block this half of the task entirely, pending "a machine with devenv
  installed."** Not needed: devenv is installed here (`command -v devenv`
  succeeded), so the intent's open question 2 resolves to "not blocked" —
  a real sample was captured in-session, per above.

## Risks

- **#21:** The refusal path is new and untested against upstream devenv
  actually dropping the placeholder comment (that hasn't happened yet — this
  is defense against a hypothetical future scaffold). The test fixture (see
  Verification) simulates it by editing the stub's `init` output; it cannot
  prove real future-devenv's shape matches what we guessed ("no column-zero
  `}` at all" is the only case the code can detect — a devenv that keeps a
  `}` at column zero but reformats everything else still splices via the
  existing brace-based fallback, untouched by this change).
- **#22:** Tightening the pattern is verified against exactly one real
  `running` sample (`ready ... restarts: 0`) and the stub's two rows,
  not against every state process-compose can report (crash-looping,
  restarting, etc.). If a real state ever spells `restarts:` differently
  (e.g. a locale-dependent thousands separator on a large count — unlikely,
  process-compose is not observed to localize numbers, but not proven here),
  the row would newly read as `unknown` rather than `running`. That is the
  fail-safe direction the constraints require, so it is an acceptable
  residual risk, not a regression to guard against further in this task.

## Verification

- `tests/cli.sh` (stub-driven, `pkgs/cli.sh` behavior):
  - **#21:** add a stub `devenv init` mode (a new `STUB_INIT_NO_BRACE=1`
    env var, following the existing `STUB_INIT_NIXPKGS=1` convention in
    `tests/stub/devenv`) that writes a `devenv.nix` with no placeholder
    comment and no column-zero `}` (e.g. everything on one line, or the
    closing brace indented). Assert `nixarchy-devenv init <preset>` under
    that stub mode exits 4, prints the preset's lines to stderr (matching the
    existing "already exists" message shape), and leaves the stub's
    `devenv.nix` byte-identical to what `devenv init` wrote (proving no
    partial/corrupt rewrite happened).
  - Existing brace-fallback case (placeholder absent, ordinary trailing `}`)
    must still pass unchanged — no regression test needed beyond what
    already exercises it, if any; if none exists today, add one alongside
    the new failure-mode test so the working fallback path is also pinned.
  - `cmd_new`'s cleanup-on-failure path (`pkgs/cli.sh:276-281`) already
    covers directory removal on any non-zero `cmd_init` exit; confirm (test)
    that `new` under the same no-brace stub mode removes the created
    directory and reports the "creating DIR failed; removed the partial
    directory" message with the underlying refusal text.
  - **#22:** add a stub `processes` mode (e.g. `STUB_PROCESSES=malformed`)
    that prints a row like `garbage running restarts: nope` (and/or
    `restarts:` with no trailing number at all) instead of a valid row.
    Assert `nixarchy-devenv status --json DIR` reports `{"state":"unknown",
    ...}`, not `"running"`, under that stub mode. Also assert the existing
    `running`/`stopped`/`noise` stub modes still classify correctly
    (regression coverage for the tightened pattern against the rows it must
    keep accepting).
- `node tests/run.js`: no changes — this defect is entirely in `cli.sh`, not
  `Model.js`.
- `nix flake check`: must still pass (shellcheck over `cli.sh` via
  `pkgs/cli.nix`'s `writeShellApplication`), confirming the new refusal
  branch and tightened regex are shell-clean.
- **Not covered by this task's tests, and not blocked either:** the
  real-devenv sample above was captured manually in this session and is
  reported here as evidence, not encoded as an automated check — `tests/cli.sh`
  runs only against the stub (`tests/stub/devenv`), and `nix run
  .#templates-check` scaffolds presets for evaluation but does not assert
  anything about `devenv processes list` output shape. Whether the real-devenv
  assumption behind the `restarts:[0-9]+` pattern should become a standing,
  automated check (e.g. extending `templates-check` or a new integration
  check that runs `devenv processes list` against a real scaffold and asserts
  the row shape) is left as a separate follow-up, not part of this task's
  scope: doing it here would mean either running a live `devenv up`/`processes
  list` cycle inside `templates-check` (which today only scaffolds and
  evaluates, never runs processes, and is explicitly hermetic re: `HOME`/
  `XDG_*`/`DEVENV_*`) or standing up a new integration check with its own
  network/hermeticity story. That is more than this fix needs and belongs in
  its own issue, per the intent's open question 3.
