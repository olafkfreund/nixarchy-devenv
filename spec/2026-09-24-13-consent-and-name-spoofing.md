---
status: draft
issue: 13
intent: intent/2026-09-24-13-consent-and-name-spoofing.md
---

# Spec: consent is enforced, and a name cannot lie about itself

## Design

### #13 — wire up `honoursAllow`, mirroring `honoursGit` exactly

**Decision: wire it up. Do not delete it.** See Alternatives rejected for why.

`Model.js` `parseTemplates` (Model.js:281-307) already computes `honoursAllow`
at line 303, symmetric to `honoursGit` at line 302. Nothing downstream reads
it. Three edits, each mirroring the existing `honoursGit` code point one for
one:

1. **`Model.js` `validateForm`** (Model.js:677-715). `honoursGit` forces
   `git = true` when the generator can't turn git off (line 704). `honoursAllow`
   must force the opposite value — `allow = false` — when the generator
   declares it never runs `devenv allow` for itself. Today line 711 reads the
   raw form field directly:
   ```js
   if (f.allow === true) argv.push("--allow")
   ```
   Replace with a checked local, built the same way `git` already is:
   ```js
   var allow = f.allow === true
   if (t && !t.honoursAllow) allow = false
   ...
   if (allow) argv.push("--allow")
   ```
   Insert the `var allow` lines directly after the existing `var git = ...`
   block (Model.js:703-704), so both toggles are resolved in one place before
   the `argv` is built.

2. **`Model.js` `formFields`** (Model.js:731-745). The `git` row already locks
   and re-hints when `!t.honoursGit` (Model.js:739-741). Give the `allow` row
   (Model.js:742-743) the same treatment:
   ```js
   out.push({ key: "allow", kind: "bool", label: "Allow automatic activation",
     hint: t && !t.honoursAllow
       ? "This template never runs devenv allow"
       : "Runs devenv allow: the environment activates when you cd in. Off: use devenv shell.",
     locked: !!(t && !t.honoursAllow) })
   ```
   No QML change is needed: `CreateForm.qml` already reads `locked` and `hint`
   generically off whatever `formFields` returns (CreateForm.qml:109 disables
   the toggle on `f.locked`; CreateForm.qml:267 dims it; CreateForm.qml:349/427
   show `hint`). This is exactly the mechanism that already makes the `git`
   lock work.

3. **`pkgs/cli.sh` `cmd_init`, `generator)` case** (pkgs/cli.sh:213-222). The
   existing guard right above the generator's `nix run` call refuses
   `--no-git` when the generator always runs git:
   ```sh
   if [ "$git" = 0 ] && [ "$(template_field "$tpl" honours_git)" = false ]; then
     die 1 "'$tpl' always runs git init, so --no-git cannot be honoured."
   fi
   ```
   Add the mirror guard for `--allow` in the same block, before `need nix`:
   ```sh
   if [ "$allow" = 1 ] && [ "$(template_field "$tpl" honours_allow)" = false ]; then
     die 1 "'$tpl' never runs devenv allow, so --allow cannot be honoured."
   fi
   ```
   This is the CLI-side repeat of the form's fast refusal, the same
   relationship `honours_git`'s check already has to `validateForm`'s. It is
   the line that actually keeps the AGENTS.md consent rule — "`devenv allow`
   runs only from the create form's toggle or the explicit allow action" —
   true even for a caller that bypasses the QML form and drives the CLI
   directly with `--allow` on a template that must never be auto-trusted.

`pkgs/cli.nix` needs no change: `honours_allow` is already emitted into
`templates.json` (pkgs/cli.nix:57); the defect was that nothing consumed it,
not that it was missing.

No template flips this today — `cloud` is the only generator and it declares
`honours = { git = false; allow = true; }` (data/templates.nix:403-406) — so
this change is inert until a future generator sets `allow = false`. That is
the intended shape: the catalogue's declared capability becomes truthful
immediately, rather than truthful only for `git`.

### #15 — bidi override/isolate characters are stripped from display and comparison text; paths stay untouched

**Decision: widen `sanitize` only. Leave `hasControlChars` exactly as it is
today.** This is option 1 of the three the reviewer laid out: the
argv-safety gate and the display sanitizer are two different trust
boundaries, and only one of them is where #15 actually lives.

`sanitize` (Model.js:99-111) is the one function every CLI-sourced *display*
string is already routed through before it is shown or compared: `r.name` in
`parseList` (Model.js:253), `r.from` (Model.js:260), warnings (Model.js:274),
error text (Model.js:559), template `note`/`label` (Model.js:298-299),
status process names (Model.js:350), and more. `hasControlChars`
(Model.js:95-97) is a *different* function, used only twice, and neither use
is on display text: `isAbsPath` (Model.js:160) gates whether a path is safe
to put in an argv slot, and `editorWords` (Model.js:603) gates whether an
`$EDITOR` word is safe to put in an argv slot. `sanitize` never calls
`hasControlChars` — they already are two independent boundaries in the
current code; the original draft of this spec was wrong to widen both
identically as if they were one.

Widen only `sanitize`'s per-character loop (Model.js:103-107) to also strip
the bidi control ranges named in the intent — U+202A–U+202E (LRE, RLE, PDF,
LRO, RLO) and U+2066–U+2069 (LRI, RLI, FSI, PDI); all eight code points are
in the BMP, so `charCodeAt` reaches them directly, no surrogate-pair
handling needed:
```js
for (var i = 0; i < text.length; i++) {
  var code = text.charCodeAt(i)
  if (code < 0x20 || code === 0x7F || (code >= 0x80 && code <= 0x9F) ||
      (code >= 0x202A && code <= 0x202E) || (code >= 0x2066 && code <= 0x2069)) continue
  out += text.charAt(i)
}
```
`hasControlChars` (Model.js:95-97) is **not edited** — it keeps matching
only `\x00-\x1f\x7f-\x9f`, exactly as today.

Because `parseList` already routes `r.name` through `sanitize(..., 80)`
(Model.js:253) to build `out.rows[i].name`, this one change is sufficient to
fix the discovered-name path end to end: the `name` used for the row
(`rowsFor`, Model.js:436-456), for the removal confirmation compare
(`removeRefusal`'s `trim(typedName) !== env.name`, Model.js:817), for
sorting (`compareEnvs`, Model.js:377-381) and filtering (`filterEnvs`,
Model.js:387-397), and for the `--name`-shaped display everywhere else, is
the same stripped string. There is no second code path to fix, and no new
predicate function is needed — `hasControlChars` was never part of the name
pipeline to begin with.

**Why `hasControlChars`/`isAbsPath` must stay untouched, spelled out.** The
reviewer traced the consequence precisely: `env.path` is the real, canonical
path on disk (`parseList` never sanitizes it — it only checks `isAbsPath` at
Model.js:250, and displays it separately via `displayPath`/`tildePath`,
Model.js:417-425), and every argv builder — `removeArgv`, `revokeArgv`,
`upArgv`, `downArgv`, `updateArgv`, `allowArgv`, `enterArgv`, `editArgv`, all
via `inDir`/`isAbsPath` — depends on that path staying byte-exact and being
accepted. Had `hasControlChars` been widened, a directory that legitimately
exists on disk with a bidi character anywhere in its path would still be
*listed* (its sanitized name renders safely) but every action on it would
silently return `null` from its argv builder and do nothing — no revoke, no
enter, no update, no way out except deleting the directory outside the
plugin. That is a worse failure mode than the spoofing risk being closed: it
is not "the name is visually corrected," it is "the row is inert with no
stated reason." It would also be a second kind of defect (a silent dead
control) layered on top of fixing the first (a lying name).

There is also no security reason to gate `env.path` on bidi characters:
paths never reach a shell — every argv is an array, built with `env -C DIR
...` (Model.js:619-622, per the "argv arrays only, never `sh -c`" rule in
AGENTS.md) — so a bidi character in a path cannot do anything a bidi
character in a name can (make a destructive confirmation, or a row's label,
render as something other than what it is). The vulnerability in #15 is
specifically about *text a human reads and compares against*, not about
argv safety, which `isAbsPath`'s existing checks (control chars, `.`/`..`
segments, length) already cover for its own, different, threat model.

**Model.js:603 (`editorWords`'s `candidates` loop): no knock-on, checked and
confirmed unaffected.** Since `hasControlChars` is not edited, `editorWords`
behaves exactly as it does today — a `$EDITOR` setting containing a control
character still falls back to `["nvim"]` (Model.js:601-609), unchanged by
this spec. That fallback was already a safe failure mode before this change
(a wrong default editor, not a silently broken action), so even if a future
change did widen `hasControlChars`, `editorWords`' fallback-on-reject
pattern would degrade gracefully — unlike `isAbsPath`'s callers, which
degrade to a silently disabled action. That asymmetry is itself a reason
`isAbsPath` cannot be treated the same way `editorWords` could be.

No `pkgs/cli.sh` change. `list --json` keeps emitting the directory's real
`name` and real `path`; the CLI's job is to enumerate what is on disk, not
to decide what is safe to render — that decision already lives in
`Model.js`'s `sanitize`, and the constraint in the intent pins logic to
`Model.js` with a Node test. A project directory with a bidi character in
its name is still a real, existing, fully manageable project under this
design: its row renders safely and every action on it keeps working,
because the path used to act on it was never the spoofed string.

## Alternatives rejected

**Delete `honours_allow` instead of wiring it up.** Rejected. AGENTS.md
already documents the catalogue contract in the plural: "A `generator` entry
... states which form toggles it honours" (AGENTS.md, Catalogue entries
declare capabilities). Deleting `honours_allow` would mean rewriting that
rule to singular, dropping the field from `cli.nix`'s `entry` function
(pkgs/cli.nix:56-58), dropping it from every generator template's `honours`
attrset (data/templates.nix:403-406), and losing the ability for a future
generator to say "never allow me" at all — a real thing a generator can
need, e.g. one whose own init script already manages trust, or one that
must never activate automatically for security reasons. The wiring is three
small, mechanical edits that each copy an existing, working, tested pattern
(`honoursGit`'s three checkpoints) — it is not "more code for a capability
nothing uses," it is the same amount of code the sibling toggle already
carries, now made to do what the catalogue already claims it does.

**Bidi in a discovered name: replace with a visible placeholder instead of
stripping.** Rejected. `sanitize` already strips (not replaces) every other
control character silently, and every caller of `sanitize`/`name` already
tolerates a shortened, control-character-free string — there is no existing
"here is a placeholder for a removed character" convention anywhere in
`Model.js` to be consistent with, and inventing one is more code for the
same outcome (a name that no longer renders differently from what it is,
since the deceptive character is gone either way). A placeholder character
also has to be chosen carefully to not itself be spoofable, which is exactly
the class of problem being fixed.

**Bidi in a discovered name: refuse the folder-deletion tier on such a
row.** Rejected. It only patches the one caller the intent happened to
notice (`removeRefusal`'s folder tier), not the row's `name` everywhere else
it is shown or compared — the `list` filter (`filterEnvs`, Model.js:387-397),
sorting by name (`compareEnvs`, Model.js:377-381), and the row label itself
all still carry the un-stripped string. Fixing `sanitize` once, at the point
every one of those already reads through, is the smaller and more complete
diff, and it does not need a new refusal branch or its own test row in
`removeRefusal`.

**Move the bidi fix into `list` (`pkgs/cli.sh`) instead of `Model.js`.**
Rejected, and reconsidered specifically in light of the isAbsPath
discussion above (the reviewer asked for this reconsideration as option 3).
Rejecting the row at the shell layer would sidestep the inert-row problem
entirely — a directory `cmd_list` refuses to report never reaches an argv
builder to be silently defeated by. But it trades that for a strictly worse
failure mode of its own: it makes a real, existing, user-created environment
*disappear from the list altogether*, with no row, no name, and no way to
manage it from the plugin at all — worse than "row renders safely, every
action works," which is what widening only `sanitize` already delivers with
no inert state to explain. It also contradicts AGENTS.md's "a state we
cannot verify... is shown as... never guessed": a bidi character in a
directory name is not an unverifiable state, it is a fully verifiable one
that the fix already handles correctly by sanitizing rather than hiding.
And it would mean duplicating the same character-class logic in `bash` with
no test harness for it (`tests/cli.sh` runs against stub `devenv`/`nix`, not
a Node unit test), against the intent's explicit constraint that this logic
goes in `Model.js` with a Node test. The `sanitize`-only fix above has no
inert-row problem to trade away, so there is nothing left for the CLI-side
option to buy.

## Risks

- **Widening `sanitize` touches every caller of `sanitize`, not just
  names.** `from`, warnings, `errorText`, template `note`/`label`, and
  status process names now also strip bidi controls. This is desired (same
  defect class, same existing boundary, everywhere display text crosses
  it) and has no inert-state risk, because none of `sanitize`'s callers
  gate an action the way `isAbsPath` does — they are all display-only
  strings already. `hasControlChars` is deliberately **not** widened (see
  Design), which is what keeps `isAbsPath`/`editorWords` — and every action
  that depends on `isAbsPath` accepting `env.path` — unaffected.
- **Non-ASCII names must still work.** `sanitize`'s stripped set gains
  exactly 8 code points (the bidi controls named in the intent), on top of
  the existing C0/C1 ranges; it does not touch any other Unicode range, so
  CJK, Cyrillic, accented Latin, emoji, etc. in a discovered name are
  untouched. Verification below adds an explicit non-ASCII-survives test to
  guard against a future edit accidentally widening the range further
  ("must not become ASCII only," per the intent's constraint).
- **A path containing a bidi character stays fully actionable, by
  deliberate scope limit.** This is the resolved consequence of not
  widening `hasControlChars` (see Design): `isAbsPath(env.path)` continues
  to accept it, so `removeArgv`/`revokeArgv`/`upArgv`/`downArgv`/
  `updateArgv`/`allowArgv`/`enterArgv`/`editArgv` all keep working on such a
  row exactly as they do on any other. The row's displayed *name* is
  sanitized (the actual spoofing surface); its *path*, which the user never
  reads as a trust signal and which never reaches a shell, is left alone on
  purpose. Verification below adds a regression test pinning `isAbsPath` to
  accept a bidi-bearing path, so a future change cannot silently reintroduce
  the inert-row failure mode by widening `hasControlChars` again.
- **`honoursAllow` enforcement is currently a no-op.** No template sets
  `allow = false` today, so this ships with zero observable behavior change
  until a future generator uses the capability — the risk is entirely in
  correctness-under-future-use, which the new tests below cover with a
  synthetic `honours.allow = false` fixture (mirroring how `cloud`'s
  `honours.git = false` is already exercised in `tests/harness.js:69` and
  `tests/model/parsing.test.js:61`, `tests/model/form.test.js:68`).
- **`pkgs/cli.sh`'s new guard is unreachable from the QML form once
  `formFields` locks the toggle**, same as the existing `--no-git` guard is
  for `git`. Both guards exist for the same reason: a caller driving the CLI
  directly (a script, `nixarchy dev`, a future integration) is not bound by
  the form's lock, so the CLI must refuse on its own, per AGENTS.md's rule
  that the CLI performs the authoritative checks, not just the form.

## Verification

**`tests/model/parsing.test.js`** (extends the existing
`parseTemplates reads each kind and keeps generator fields` test and its
neighbors):
- Add a generator fixture with `honours_allow: false` (alongside the
  existing `honours_git: false` cloud fixture pattern in
  `tests/harness.js:69`) and assert `Model.templateById(t, id).honoursAllow
  === false`.
- Add `sanitize` unit tests (new `describe`-free `test(...)` blocks, matching
  this file's existing style; use `"\u202E"` / `"\u2066"`/`"\u2069"` escapes
  in the test source rather than literal characters, so the diff stays
  readable):
  - `Model.sanitize("na\u202Eexe.pdf", 80)` strips the override and leaves
    `"naexe.pdf"` (the classic bidi filename-spoofing shape from the RLO
    CVE class this issue is modeled on); same shape for one isolate pair,
    e.g. `Model.sanitize("na\u2066me\u2069", 80)` leaves `"name"`.
  - `Model.sanitize("café \u202Eevil", 80)` leaves `"café evil"` —
    non-ASCII survives; only the control range is removed (guards the
    "must not become ASCII only" constraint).
  - Extend the existing `parseList keeps well-formed rows and types every
    field`-style test with a row whose `name` contains
    `"\u2066spoof\u2069"` and assert `out.rows[0].name` contains none of
    the bidi characters — this is the "discovered-environment path
    specifically" the intent asks for, exercised through the real
    `parseList` entry point rather than `sanitize` directly.
- Add an explicit **negative** test pinning the scope decision:
  `Model.hasControlChars("\u202Eevil")` is still `false`, and
  `Model.isAbsPath("/home/user/Source/na\u202Eme")` is still `true` —
  proving a bidi character does not make a real path unusable, and guarding
  against a future edit re-coupling `hasControlChars` to the bidi ranges by
  accident.

**`tests/model/remove.test.js`** (extends the existing "the folder tier
needs the name typed exactly" test at line 39):
- Build an `env` (via the existing `env(...)` harness helper) whose `name`
  is a `parseList`-sanitized name derived from a raw name containing a bidi
  override, and assert `removeRefusal(env, "folder", ..., typedName)`
  accepts only the plain string the user would actually type (the sanitized
  name), and refuses the raw string with the override character still in
  it — proving the confirmation compares like-for-like once #15 is fixed.

**`tests/model/form.test.js`** (extends the existing "a generator that
always runs git init never gets --no-git" test at line 25, and the "every
field refuses hostile input" test's `cloud` checks around line 34):
- Using the same synthetic `honours.allow = false` fixture as above: assert
  `validateForm({ ..., template: <that id>, allow: true })` produces an
  `argv` with no `--allow`, mirroring the existing no-`--no-git` assertion
  exactly.
- Extend the `formFields` locking test (`tests/model/form.test.js:68`,
  `eq(cloud.find(f => f.key === "git").locked, true)`) with the equivalent
  assertion on `allow` for the new fixture template.

**`tests/cli.sh`** (extends the existing generator assertions around line
65): add a stub generator fixture (or reuse `cloud` if a `honours_allow:
false` stub template is added to `tests/stub`) and assert that
`nixarchy-devenv new --allow --parent ... --name ... <tpl> <provider>`
exits non-zero with the "never runs devenv allow" message, mirroring the
existing `--no-git` refusal coverage for `cloud`.

**Existing suites that must still pass unchanged**, since nothing about
`cloud`'s behavior changes (`honours.allow = true` there, so `--allow` still
flows through): `tests/model/form.test.js`'s current `cloud` assertions,
`tests/cli.sh`'s current `honours_git == false` assertion (line 65), and
`node tests/run.js` / `bash tests/cli.sh` as a whole. `nix flake check`
picks up both once the Node/CLI suites are extended; no manifest, color, or
symlink rule is touched by this change.
