---
status: approved
issue: 13
spec: spec/2026-09-24-13-consent-and-name-spoofing.md
---

# Plan: consent is enforced, and a name cannot lie about itself

Rebased onto `main` at `e254c82` (post-#8: `tests/run.js` was deleted, the
suite runs on `node:test`; `Model.js` gained a `rootArgs` helper and some
line movement; baselines shifted). Design is unchanged from the approved
spec — this revision only updates line numbers, the exact `sanitize`
snippet (it was refactored to a one-line regex in #8), test commands and
counts.

Two independent fixes, carried over from the approved spec, unchanged:

1. **`honours_allow`**: wire it up, mirroring `honoursGit` exactly. Three
   mechanical edits, each copying an existing checkpoint the `git` toggle
   already has: `Model.js` `validateForm` forces `allow = false` when the
   template can't honour it (mirrors `git = true` there); `Model.js`
   `formFields` locks and re-hints the `allow` row the same way it already
   does for `git`; `pkgs/cli.sh`'s `generator)` case in `cmd_init` refuses
   `--allow` the same way it already refuses `--no-git`. `pkgs/cli.nix`
   already emits `honours_allow` into `templates.json` — no change there.
   No template in the real catalogue sets `honours.allow = false` today
   (`cloud` is the only generator and declares `allow = true`), so this
   ships with zero observable behaviour change until a future generator
   uses the capability. No QML change: `CreateForm.qml` already reads
   `locked`/`hint` generically off whatever `formFields` returns, which is
   exactly the mechanism that already makes the `git` lock work.

2. **bidi controls**: widen `sanitize` (Model.js:99–104) ONLY, to also
   strip the bidi override/isolate ranges U+202A–U+202E and U+2066–U+2069.
   `hasControlChars` (Model.js:95–97) stays byte-for-byte unchanged.
   `sanitize` never calls `hasControlChars` — they are already two separate
   trust boundaries in the current code: `sanitize` is the display/compare
   boundary (every CLI-sourced string a human reads or types a confirmation
   against routes through it, including `parseList`'s `r.name` at
   Model.js:246, which is the discovered-environment path the intent names
   specifically); `hasControlChars` is the argv-safety boundary, used only
   by `isAbsPath` (Model.js:151, gates `env.path` for every argv builder —
   `removeArgv`, `revokeArgv`, `upArgv`, `downArgv`, `updateArgv`,
   `allowArgv`, `enterArgv`, `editArgv`, all via `inDir`/`rootArgs`) and by
   `editorWords`. Widening `hasControlChars` too would make any real
   directory with a bidi character in its path render safely (name
   sanitized) but become permanently inert (every action's argv builder
   returns `null`, silently, with no stated reason) — a worse failure mode
   than the spoofing risk being closed. Paths never reach a shell (argv
   arrays only, per AGENTS.md), so a bidi character in a path cannot spoof
   anything the way one in a displayed/compared name can. This is the
   settled, reconsidered position in the approved spec (option 1 of three
   considered) — do not re-open it.

The two halves touch disjoint code (`sanitize` vs. `validateForm`/
`formFields`/`cli.sh`) and are independent: land in either order, as two
separate commits. Order below does bidi first only because it is the
smaller, self-contained diff (one function); no dependency exists either
way.

**Note on bidi characters in this file:** every bidi code point below is
written as a `\uXXXX` escape in prose and in code snippets — e.g. `\u202E`
— never as a literal control character. Follow the same convention in the
actual test source: paste the escape, never the raw character.

## Steps

Each step is one commit. The tree builds and all existing tests pass after
every step.

1. **`Model.js`** (widen `sanitize`, Model.js:99–104). Current code (post-#8
   refactor to a one-line regex):
   ```js
   function sanitize(value, maxLength) {
     var limit = maxLength > 0 ? maxLength : MAX_FIELD
     var out = str(value).replace(/[\x00-\x1f\x7f-\x9f]/g, "").trim()
     if (out.length > limit) out = out.substring(0, limit - 1) + "…"
     return out
   }
   ```
   Change only the character class in the `replace`, adding the bidi
   override range (U+202A–U+202E) and the bidi isolate range
   (U+2066–U+2069):
   ```js
   function sanitize(value, maxLength) {
     var limit = maxLength > 0 ? maxLength : MAX_FIELD
     var out = str(value).replace(/[\x00-\x1f\x7f-\x9f\u202A-\u202E\u2066-\u2069]/g, "").trim()
     if (out.length > limit) out = out.substring(0, limit - 1) + "…"
     return out
   }
   ```
   Do NOT touch `hasControlChars` (Model.js:95–97) — leave its regex
   `/[\x00-\x1f\x7f-\x9f]/` exactly as is.
   → verify by: `node --test 'tests/model/*.test.js'` still reports
   `pass 70` (no test changed in this step; this step is the production
   change alone — fold it into the same commit as step 2's tests if you
   prefer one commit for the whole bidi half, but do not leave a commit
   where `sanitize` changed with no test covering it).

2. **`tests/model/parsing.test.js`** and **`tests/model/remove.test.js`**:
   add the bidi regression tests (see Tests below for exact assertions).
   → verify by: `node --test 'tests/model/*.test.js'` reports `pass 74`
   (70 + 4 new tests, see Tests section for the breakdown).

3. **`Model.js`** `validateForm` (Model.js:703–712): insert the `allow`
   checkpoint directly after the existing `git` checkpoint, and change line
   711 to use it:
   ```js
   var git = f.git !== false
   if (t && !t.honoursGit) git = true

   var allow = f.allow === true
   if (t && !t.honoursAllow) allow = false

   var ok = true
   for (var k in errors) ok = false
   if (!ok) return { ok: false, errors: errors, argv: null }

   var argv = [CLI, "new"]
   if (allow) argv.push("--allow")
   if (!git) argv.push("--no-git")
   ```
   (Only line 711's `if (f.allow === true)` becomes `if (allow)`; the two
   new `var allow` lines are inserted right after the existing `var git`
   block; everything else is unchanged.)
   → verify by: `node --test 'tests/model/*.test.js'` still passes at
   whatever count step 2 left it at (this step adds no new tests yet — it's
   behaviour-preserving for every fixture template that exists today, since
   `honoursAllow` is `true` everywhere until step 5 adds a fixture that
   differs).

4. **`Model.js`** `formFields` (Model.js:742–743): give `allow` the same
   lock/hint treatment `git` already has:
   ```js
   out.push({ key: "allow", kind: "bool", label: "Allow automatic activation",
     hint: t && !t.honoursAllow
       ? "This template never runs devenv allow"
       : "Runs devenv allow: the environment activates when you cd in. Off: use devenv shell.",
     locked: !!(t && !t.honoursAllow) })
   ```
   → verify by: `node --test 'tests/model/*.test.js'` still passes at the
   same count (no behaviour change for any existing fixture).

5. **`tests/harness.js`**: add a synthetic generator fixture with
   `honours_allow: false` to the shared `TEMPLATES` array (see Tests below
   for the exact fixture and why it must be additive, not a mutation of
   `cloud`). This also requires updating the one existing assertion in
   `tests/model/parsing.test.js`'s `parseTemplates reads each kind and
   keeps generator fields` test that enumerates every fixture id by name
   (see Tests) — do this in the same commit, or that existing test breaks.
   → verify by: `node --test 'tests/model/*.test.js'` still `pass 74` (a
   fixture addition plus an updated existing assertion contributes no new
   test count by itself).

6. **`tests/model/parsing.test.js`, `tests/model/form.test.js`**: add the
   `honoursAllow`/`allow`-locking assertions against the new fixture (see
   Tests below).
   → verify by: `node --test 'tests/model/*.test.js'` reports `pass 77`
   (74 + 3 new: see Tests for the exact breakdown).

7. **`pkgs/cli.sh`** `cmd_init`'s `generator)` case (pkgs/cli.sh:200–210):
   add the mirror guard immediately after the existing `--no-git` guard,
   before `need nix`:
   ```sh
   if [ "$git" = 0 ] && [ "$(template_field "$tpl" honours_git)" = false ]; then
     die 1 "'$tpl' always runs git init, so --no-git cannot be honoured."
   fi
   if [ "$allow" = 1 ] && [ "$(template_field "$tpl" honours_allow)" = false ]; then
     die 1 "'$tpl' never runs devenv allow, so --allow cannot be honoured."
   fi
   need nix
   ```
   → verify by: `nix build .#cli --print-out-paths` succeeds (shellcheck
   runs as part of that build and must stay clean — the added lines are a
   straight copy of the existing guard's shape, so this should not surface
   any new shellcheck finding), then
   `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
   still reports `cli: 63 passed, 0 failed` (see Tests below for why this
   count does NOT change — no real catalogue template can exercise the new
   branch, so no new `tests/cli.sh` assertion is added for it in this
   plan).

Steps 1–2 are the bidi half; steps 3–7 are the `honours_allow` half. They
touch disjoint files/functions and can be reordered as two commits (bidi
first, then honours_allow, or vice versa) without conflict — reorder only
if you also reorder the two halves' Rollback below accordingly.

## Tests

Baseline before any change (confirmed by running both suites against
current `main`, e254c82): `node --test 'tests/model/*.test.js'` →
`pass 70, fail 0`; `bash tests/cli.sh <cli>` → `cli: 63 passed, 0 failed`.

### bidi half — `tests/model/parsing.test.js`

Add these `test(...)` blocks (matching the file's existing style — plain
`node:test` `test(name, fn)`, no `describe`). Use `\u202E`/`\u2066`/
`\u2069` escapes in source, never a literal bidi character:

- `sanitize strips bidi override and isolate controls, keeps the rest`:
  ```js
  test("sanitize strips bidi override and isolate controls, keeps the rest", () => {
    eq(Model.sanitize("na\u202Eexe.pdf", 80), "naexe.pdf")
    eq(Model.sanitize("na\u2066me\u2069", 80), "name")
    eq(Model.sanitize("café \u202Eevil", 80), "café evil")
  })
  ```
  (third assertion pins "must not become ASCII only" — café's é survives.)
- `hasControlChars and isAbsPath are unaffected by bidi controls` (the
  negative regression test the approved decisions require, guarding the
  scope boundary against being re-coupled later):
  ```js
  test("hasControlChars and isAbsPath are unaffected by bidi controls", () => {
    eq(Model.hasControlChars("\u202Eevil"), false)
    eq(Model.isAbsPath("/home/user/Source/na\u202Eme"), true)
  })
  ```
- Extend the `parseList` coverage with one new test exercising the real
  discovered-environment path end to end (not `sanitize` directly), using
  this file's existing `list`/`listRow` helpers:
  ```js
  test("parseList sanitizes a bidi-spoofed discovered name", () => {
    const out = Model.parseList(list([listRow({ name: "\u2066spoof\u2069.pdf" })]))
    eq(out.rows[0].name, "spoof.pdf")
  })
  ```

That is 3 new tests in `parsing.test.js`.

### bidi half — `tests/model/remove.test.js`

Extend the existing "the folder tier needs the name typed exactly" area
with one test proving the confirmation compares like-for-like once
sanitized. This file's helper is `env(o)` (imported from `harness.js`,
already routes through `Model.parseList`):

```js
test("folder-tier confirmation compares the sanitized name, not the raw bidi one", () => {
  const spoofed = env({ name: "\u2066app\u2069" }) // parseList already sanitizes this to "app"
  eq(refuse(Object.assign({}, spoofed), "folder", STOPPED, "app"), "")
  eq(refuse(Object.assign({}, spoofed), "folder", STOPPED, "\u2066app\u2069"), "Type the folder name, app, to confirm")
})
```
Note: `spoofed.name` is already the post-`sanitize` string `"app"` — this
test's point is that a raw string still carrying the override does NOT
match it. 1 new test.

Bidi half total: **3 + 1 = 4 new tests.** Running count after step 2:
70 + 4 = **74**.

### `honours_allow` half — `tests/harness.js`

Add a second generator fixture to `TEMPLATES` (do not mutate the existing
`cloud` entry — every existing test's assertions about `cloud` must keep
passing unchanged):

```js
{ id: "cloud-locked", kind: "generator", group: "Cloud", label: "Cloud (locked)", note: "n",
  flake: "github:o/c", rev: "abc", providers: ["aws"], honours_git: true, honours_allow: false }
```

This adds a 6th id to `TEMPLATES`. The existing assertion in
`parsing.test.js`'s `parseTemplates reads each kind and keeps generator
fields` test —
```js
eq(t.map(x => x.id), ["python", "flutter", "ml", "cloud", "mine"])
```
— MUST be updated in this same commit to
`["python", "flutter", "ml", "cloud", "mine", "cloud-locked"]`, or that
existing test breaks. This is not a new test, it's an update to an
existing one — do not double-count it.

### `honours_allow` half — `tests/model/parsing.test.js`

One new test:
```js
test("parseTemplates: honoursAllow is false only when the generator says so", () => {
  const t = templates()
  eq(Model.templateById(t, "cloud-locked").honoursAllow, false)
  eq(Model.templateById(t, "cloud").honoursAllow, true)
})
```

### `honours_allow` half — `tests/model/form.test.js`

Two new tests, mirroring the existing git-lock tests exactly:
```js
test("a generator that never runs devenv allow never gets --allow", () => {
  const r = v({ template: "cloud-locked", providers: ["aws"], allow: true })
  eq(r.ok, true)
  ok(r.argv.indexOf("--allow") === -1)
})

test("formFields locks allow where the generator cannot honour it", () => {
  const locked = Model.formFields(templates(), "cloud-locked")
  eq(locked.find(f => f.key === "allow").locked, true)
  eq(Model.formFields(templates(), "cloud").find(f => f.key === "allow").locked, false)
})
```

### Hostile-input row (AGENTS.md: "any new field needs its own rule and a
hostile-input test row")

No new form field is added — `allow` already exists as a `bool`, and bools
have no string-shaped hostile-input surface (the existing `every field
refuses hostile input` test in `form.test.js` already iterates `HOSTILE`
— which already includes `"\u202Eevil"` — against `name`/`template`/
`providers`/`parent`; it does not need an `allow` row because `allow` is
never parsed as a string). The hostile-input coverage this plan actually
owes is on the bidi/`sanitize` side, and it is the two tests above
(`sanitize strips bidi...` and `hasControlChars and isAbsPath are
unaffected...`), which is exactly the negative-regression row the approved
decisions call for.

`honours_allow` half total: **1 (parsing) + 2 (form) = 3 new tests**, plus
the 1 existing assertion updated (not counted as new).

### Running totals

- After bidi half (steps 1–2): `node --test 'tests/model/*.test.js'` →
  **pass 74, fail 0**.
- After `honours_allow` half (steps 3–6): `node --test
  'tests/model/*.test.js'` → **pass 77, fail 0** (74 + 3).
- `bash tests/cli.sh <cli>` stays **`cli: 63 passed, 0 failed`** through
  every step, including step 7 — see below.

### `tests/cli.sh`: no new assertion for the `--allow` guard, and why

`tests/cli.sh` runs against the real, built CLI, whose `templates.json` is
baked at build time from `data/templates.nix` (`pkgs/cli.nix`, the
`index = writeText "templates.json" ...` line) with no test-time override
hook — `pkgs/cli.nix` prepends `share=<store path>` to `cli.sh` as a
literal shell assignment; there is no env var or flag to point it at an
alternate index. The existing `--no-git` guard is exercised at
`tests/cli.sh:135` only because the real `cloud` template already sets
`honours_git: false`. No real template sets `honours_allow: false` (by
design — the spec is explicit that this ships inert until a future
generator needs it), so there is no fixture through which `tests/cli.sh`
can reach the new branch without adding a template to `data/templates.nix`
solely for the test, which would misrepresent the catalogue and contradicts
the spec's own "no template flips this today." Do not add one. The guard
is verified by: (a) `nix build .#cli`'s shellcheck pass (step 7), (b) it
being a byte-for-byte structural mirror of the already-tested `--no-git`
guard three lines above it, and (c) the `Model.js`-level tests
(`honours_allow` half above), which are what AGENTS.md's "logic goes in
`Model.js` with a Node test" already asks for — `cli.sh`'s guard is the
CLI-side repeat of that same check, not a second place new logic is
invented. If a future generator actually sets `honours.allow = false`, add
the `tests/cli.sh` assertion then, mirroring `tests/cli.sh:135`'s shape
against that real template.

### Final full-suite check

After all 7 steps: `node --test 'tests/model/*.test.js'` →
`pass 77, fail 0`;
`bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
→ `cli: 63 passed, 0 failed`; `nix flake check` clean (covers both suites
plus manifest/entry-point/no-symlink/no-hex-colour checks, none of which
this change touches).

## Rollback

The two halves are independent; each can be reverted without touching the
other.

- **bidi half** (steps 1–2): `git revert` the commit(s) touching
  `Model.js`'s `sanitize` and the two changed test files
  (`parsing.test.js`, `remove.test.js`). `sanitize` returns to stripping
  only C0/C1 controls; `hasControlChars` was never touched, so nothing
  else moves. No data migration, no CLI rebuild required beyond the
  ordinary `nix build` picking up the reverted `Model.js` (it is copied as
  a real file per the `files` list in `flake.nix`, not evaluated at
  runtime by anything else).
- **`honours_allow` half** (steps 3–7): `git revert` the commits touching
  `Model.js` (`validateForm`, `formFields`), `pkgs/cli.sh`, and
  `tests/harness.js` + the two test files it added assertions to. Because
  no template in the real catalogue sets `honours_allow: false`, this
  revert is behaviourally a no-op for every existing user the moment
  before a future generator would have used the capability — same as
  before this plan shipped. If a future generator has by then already set
  `honours.allow = false` in `data/templates.nix`, reverting this half
  would silently re-break consent enforcement for that generator (allow
  would flow through unchecked again) — check `data/templates.nix` for any
  `honours.allow = false` entries before rolling back this half, and if one
  exists, roll back only after confirming with the template's owner that
  reintroducing the gap is acceptable, or revert the template's entry
  instead of this half.
