---
status: approved
issue: 17
spec: spec/2026-09-24-17-flake-checks.md
---

# Plan: the flake checks enforce the rules they claim to enforce

**Rebased onto main at `e254c82`** (merge of PR #26, `fix/8-remove-dead-code`).
That branch already consolidated the two `pacman|yay` greps the spec found
(the old separate `plugin`-check grep over `${plugin}/*.qml ${plugin}/*.js`
is gone; `flake.nix`'s `repo` check now runs the single grep over
`${self}/*.qml ${self}/*.js ${self}/pkgs ${self}/data`, `flake.nix:167-169`),
which is exactly the follow-up the spec flagged for "whichever branch lands
second" — so step 1 below now widens that one already-consolidated grep
instead of two. It also renamed the test entry point: `tests/run.js` is
deleted, and the `model` check invokes `node --test 'tests/model/*.test.js'`
(`flake.nix:122`) — unaffected by this plan, noted here only because the
Tests section below must not reference the old command.

## Summary of approved decisions (carried from the spec)

- **#17**: the `repo` check's `pacman|yay` grep (now `flake.nix:167-169`,
  after #8's consolidation — see rebase note above) scans
  `${self}/*.qml ${self}/*.js ${self}/pkgs ${self}/data` today. Widen it to
  the whole `${self}` tree, with a narrow, commented, name-based exclusion
  for exactly the files whose job is to *talk about* the rule: `AGENTS.md`
  (states the rule), `flake.nix` itself (carries the grep pattern text and
  doc comments), and the closed `intent/`, `spec/`, `plan/` directories
  (design history that quotes the rule while proposing to change it — this
  spec is itself in `spec/` and does exactly that). Do not reword AGENTS.md's
  rule text to dodge the grep. Do not exclude whole content directories
  (`docs/`, `tests/`, etc.) — only the four self-referential locations,
  confirmed today to be the only matches.
- **#18**: a *reference* check, not a QML parser (no `.qmltypes` exist for
  Quickshell in nixpkgs, and a parser wouldn't catch a missing file anyway —
  the actual defect shape). New `checks.<system>.files`: for every packaged
  `.qml` file, resolve each bare sibling-component reference (Quickshell
  resolves siblings by filename, no `import` line) and each `import "…"`
  string (`Model.js`) against the package (`${plugin}`), using the candidate
  component names from the whole repo (`${self}/*.qml`) so a new file that
  exists at the repo root but was never added to `files` is caught.
- **#19**: evaluate `homeManagerModules.default` inside a check, against a
  minimal two-option stub (`home.file.*.text` only — the module never reads
  any other Home Manager option) via `lib.evalModules`. Pure evaluation, no
  IFD, no network, no `pkgs` dependency. New `checks.<system>.homeManagerModule`
  with two `assert`s: the default keybinding is `"SUPER + ALT + E"`, and the
  substituted `devenv-binds.lua` text contains
  `o.bind("SUPER + ALT + E"`. This does not silence nix's own "unknown flake
  output 'homeManagerModules'" schema warning (nix doesn't know that output
  name; unrelated to whether the value is evaluated) — out of scope per the
  intent, which only asks for evaluation.
- One PR, three commits, one per issue, all inside `flake.nix`'s `checks`
  block. The plugin check's own `pacman|yay` grep (`flake.nix:148`, over
  `${plugin}/*.qml ${plugin}/*.js`) is left alone — now redundant with the
  widened `repo` check, but touching it collides with the in-flight
  `fix/8-remove-dead-code` branch that already consolidates it; note as a
  follow-up for whichever branch lands second.

Verified live against the current tree at `e254c82` (baseline, before any
edit): `nix flake check --all-systems --no-build` passes with 8 checks (cli,
plugin, model, repo × 2 systems) and the pre-existing `unknown flake output
'homeManagerModules'` warning. The widened #17 grep, run standalone against
the working tree, returns nothing (exit 1, no output) — the intent/spec/plan
directories now also hold `2026-09-21-3-*`, `2026-09-21-4-*` and
`2026-09-22-8-*` artifacts alongside the original `2026-09-19-1-*` ones, but
the only matches for `pacman|yay` anywhere in the repo today remain
`flake.nix`, `AGENTS.md`, `intent/2026-09-19-1-devenv-plugin.md` and
`plan/2026-09-19-1-devenv-plugin.md` — all four still covered by the
exclusion, which excludes by directory (`intent/`, `spec/`, `plan/` in full),
not by filename, so it does not need updating as new dated artifacts are
added.

## Steps

1. `flake.nix`: replace the `repo` check's grep
   (currently `flake.nix:167-169`, already the single grep #8 consolidated
   from the old plugin-check + repo-check pair) —

   ```nix
   # was:
           if grep -rnwE 'pacman|yay' ${self}/*.qml ${self}/*.js ${self}/pkgs ${self}/data; then
             echo "Arch package manager reference above" >&2; exit 1
           fi
   # becomes:
           # Excludes only the files whose job is to talk *about* the rule:
           # flake.nix carries this pattern's own text and doc comments,
           # AGENTS.md states the rule, and intent/spec/plan hold design
           # history that quotes it while proposing to change it. Nothing
           # else may mention either word, not even in a comment.
           if grep -rnwE 'pacman|yay' ${self} \
               --exclude-dir=.git --exclude-dir=result \
               --exclude=flake.nix --exclude=AGENTS.md \
               --exclude-dir=intent --exclude-dir=spec --exclude-dir=plan; then
             echo "Arch package manager reference above" >&2; exit 1
           fi
   ```

   → verify by: `grep -rnwE 'pacman|yay' . --exclude-dir=.git --exclude-dir=result --exclude=flake.nix --exclude=AGENTS.md --exclude-dir=intent --exclude-dir=spec --exclude-dir=plan` from the repo root returns nothing (exit 1), then `nix flake check --all-systems --no-build` passes.

2. `flake.nix`: add `checks.<system>.files`, after the `plugin` check (currently ends `flake.nix:153`, before the `repo` check at `flake.nix:157`) —

   ```nix
   # Every local component a packaged .qml references (Quickshell resolves
   # siblings by bare filename, no import line) or imports by path (Model.js)
   # must itself be in the package. Candidate names come from the whole repo
   # (${self}/*.qml), not just what's packaged (${plugin}/*.qml): that's what
   # catches a new file that was referenced but never added to flake.nix's
   # files list.
   files = let plugin = self.packages.${system}.plugin; in
     pkgs.runCommand "nixarchy-devenv-files-check" { } ''
       fail=0
       for f in ${plugin}/*.qml; do
         base=$(basename "$f" .qml)
         for other in ${self}/*.qml; do
           obase=$(basename "$other" .qml)
           [ "$obase" = "$base" ] && continue
           if grep -qw "$obase" "$f" && [ ! -f "${plugin}/$obase.qml" ]; then
             echo "$base.qml references $obase, but $obase.qml is not in flake.nix's files list" >&2
             fail=1
           fi
         done
         for imp in $(grep -ohE 'import "[^"]+"' "$f" | sed -E 's/import "(.*)"/\1/'); do
           [ -f "${plugin}/$imp" ] || {
             echo "$base.qml imports \"$imp\", which is not in flake.nix's files list" >&2
             fail=1
           }
         done
       done
       [ "$fail" -eq 0 ] || exit 1
       touch "$out"
     '';
   ```

   Insert it as a new attribute in the `checks` set (order among sibling
   attributes doesn't matter to Nix; place it directly after `plugin` to keep
   the two "package contents" checks adjacent).

   → verify by: `nix flake check --all-systems --no-build` passes, and
   `checks.<system>.files` appears in the output for both systems.

3. `flake.nix`: add `checks.<system>.homeManagerModule`, after the `model` check (currently ends `flake.nix:124`, before the `plugin` check at `flake.nix:128`) —

   ```nix
   # Forces homeManagerModules.default to actually be evaluated by
   # `nix flake check` on every system, which is the defect (#19 says "never
   # evaluated", not "wrong today"). The stub declares only what the module
   # touches: home.file.*.text. It does not, and is not meant to, silence
   # nix's own "unknown flake output 'homeManagerModules'" schema warning --
   # that's nix not recognising the output name, unrelated to evaluation.
   homeManagerModule =
     let
       stub = { lib, ... }: {
         options.home.file = lib.mkOption {
           type = with lib.types; attrsOf (submodule { options.text = lib.mkOption { type = str; }; });
           default = { };
         };
       };
       evaluated = nixpkgs.lib.evalModules {
         modules = [ stub self.homeManagerModules.default ];
       };
       fileText = evaluated.config.home.file.".config/hypr/devenv-binds.lua".text;
     in
     assert nixpkgs.lib.assertMsg
       (evaluated.config.programs.nixarchy-devenv.keybinding == "SUPER + ALT + E")
       "homeManagerModules.default's default keybinding changed; update this check, devenv-binds.lua's placeholder and AGENTS.md together if that's intended";
     assert nixpkgs.lib.assertMsg
       (nixpkgs.lib.hasInfix ''o.bind("SUPER + ALT + E"'' fileText)
       "homeManagerModules.default stopped substituting the keybinding into devenv-binds.lua's o.bind(...) line";
     pkgs.runCommand "nixarchy-devenv-hm-module-check" { } "touch $out";
   ```

   → verify by: `nix flake check --all-systems --no-build` passes (the two
   `assert`s must not throw during evaluation — a thrown assert fails the
   whole flake eval, not just this check), and
   `checks.<system>.homeManagerModule` appears in the output for both
   systems.

## Tests

All commands run from the repo root, after each corresponding commit unless
noted. `git stash` / the exact revert command undoes each plant before moving
on — never leave a planted violation committed.

**#17 — widened `repo` grep**

```
nix build .#checks.x86_64-linux.repo -L   # passes before the plant
```

Plant (a bare word, not inside the four excluded paths):
```
echo 'pacman' >> docs/usage.md
```
Prove it now fails:
```
nix build .#checks.x86_64-linux.repo -L
# expected: "Arch package manager reference above", exit 1
```
Revert the plant:
```
git checkout -- docs/usage.md
```

**#18 — `files` reference check**

```
nix build .#checks.x86_64-linux.files -L   # passes before the plant
```
Plant a reference to a file that isn't packaged (the failure shape #18
describes: a new component referenced but never added to `files`):
```
echo 'FooWidget {}' >> DevenvView.qml
```
Prove it now fails:
```
nix build .#checks.x86_64-linux.files -L
# expected: "DevenvView.qml references FooWidget, but FooWidget.qml is not
# in flake.nix's files list" -- note: this also requires a sibling
# FooWidget.qml to exist at the repo root for the loop to find it as a
# candidate name; the minimal planted violation is:
git stash   # undo the first plant, use this one instead
printf '// placeholder\n' > FooWidget.qml
echo 'FooWidget {}' >> DevenvView.qml
nix build .#checks.x86_64-linux.files -L
# expected: fails, "FooWidget.qml is not in flake.nix's files list"
```
Revert the plant:
```
git checkout -- DevenvView.qml
rm -f FooWidget.qml
```

**Correction, found while implementing.** The planted violation above does not
fire as written. A flake's `${self}` contains only git-**tracked** files, so an
untracked `FooWidget.qml` never enters the source and the candidate loop cannot
see it — the check passes and the plant proves nothing. The plant must be:

```
printf '// placeholder\n' > FooWidget.qml
echo 'FooWidget {}' >> DevenvView.qml
git add FooWidget.qml            # <- the missing step
nix build .#checks.x86_64-linux.files -L
# fails: "DevenvView.qml references FooWidget, but FooWidget.qml is not in
#         flake.nix's files list"
```

Revert with `git rm -f --cached FooWidget.qml && rm -f FooWidget.qml &&
git checkout -- DevenvView.qml`.

This is also the check's real boundary, worth stating: it catches a component
that is tracked but missing from `files`, which is the case that actually
happens — you `git add` a new component and forget the flake. A component that
is neither tracked nor packaged is invisible to Nix and cannot be caught here.

**#19 — `homeManagerModule` stub eval**

```
nix build .#checks.x86_64-linux.homeManagerModule -L   # passes before the plant
```
Plant a change to the default keybinding (simulates the module silently
changing without the check, docs or binds file being updated together):
```
sed -i 's/"SUPER + ALT + E"/"SUPER + ALT + F"/' flake.nix
```
(This edits both the `default =` line and the `builtins.replaceStrings`
source string in the module, since both must move together for the module
itself to stay internally consistent — but the check's own hardcoded
expectation of `"SUPER + ALT + E"` no longer matches.)
Prove it now fails:
```
nix flake check --all-systems --no-build
# expected: eval error, "homeManagerModules.default's default keybinding
# changed; update this check, devenv-binds.lua's placeholder and AGENTS.md
# together if that's intended"
```
Revert the plant:
```
git checkout -- flake.nix
```

**Whole-flake and packaging, after all three commits**

```
nix flake check --all-systems --no-build
```
Expect: `all checks passed!`, 12 checks total (cli, plugin, model, repo,
files, homeManagerModule × 2 systems), the pre-existing `unknown flake
output 'homeManagerModules'` warning still present (out of scope, per spec),
no other warnings.

Fresh-clone plugin validation (the `result` symlink makes validating `.`
fail once anything has been built — clone to a temp dir and strip `.git`
per AGENTS.md's "Verifying live" procedure):
```
d=$(mktemp -d) && git clone -q . "$d/p" && rm -rf "$d/p/.git" && omarchy plugin validate "$d/p"
```
Expect: validation passes (no symlinks, entry points present, manifest
schema intact — untouched by this change).

## Rollback

Per-commit revert, in reverse order (each commit is independently
`git revert`-able since the three checks don't depend on each other):

- **Commit 3 (#19, `homeManagerModule`)**: `git revert <commit-3-sha>` —
  removes the new check attribute only; `flake.nix` returns to having
  `homeManagerModules.default` unevaluated by `nix flake check` (the
  pre-existing, documented gap), no other check affected.
- **Commit 2 (#18, `files`)**: `git revert <commit-2-sha>` — removes the new
  check attribute only; package-contents drift goes back to being caught
  only by the plugin failing to load at runtime.
- **Commit 1 (#17, widened `repo` grep)**: `git revert <commit-1-sha>` —
  restores the narrow `${self}/pkgs ${self}/data` grep; the scanning gap
  (Lua, docs, tests, README, etc.) reopens.

After any revert: `nix flake check --all-systems --no-build` must still pass
(each commit leaves the flake in a fully green state, so any suffix of
reverts is safe, not just a full rollback to the branch point).
