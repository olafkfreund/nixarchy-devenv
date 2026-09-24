---
status: approved
issue: 17
intent: intent/2026-09-24-17-flake-checks.md
---

# Spec: the flake checks enforce the rules they claim to enforce

## Design

One PR, three commits, one per issue, all inside `flake.nix`'s `checks`
block (`flake.nix:90-175`). The intent already bundles #17/#18/#19 under one
slug and closes all three, so splitting into three PRs would just mean
rebasing the same eleven lines three times for no isolation benefit — see
"One PR or three?" below.

### #17 — widen the grep, exclude by name, don't reword the rule

Today there are two `pacman|yay` greps: `flake.nix:148` scans
`${plugin}/*.qml ${plugin}/*.js` (the packaged copies) and `flake.nix:170`
scans `${self}/pkgs ${self}/data`. Nothing scans `devenv-binds.lua`, `docs/`,
`share/*.jsonc`, `tests/`, `README.md`, `CLAUDE.md`, `manifest.json`, or
`AGENTS.md` itself.

**The trap, confirmed by running it:**

```
$ grep -rlwE 'pacman|yay' --exclude-dir=.git --exclude-dir=result .
flake.nix
AGENTS.md
intent/2026-09-19-1-devenv-plugin.md
plan/2026-09-19-1-devenv-plugin.md
```

Four files, and every one is a legitimate mention, not a violation:

- `flake.nix` — the grep's own pattern text (`'pacman|yay'`) and the doc
  line `# both, + manifest, entry points, no symlinks, no pacman/yay, no hex
  colours` (`flake.nix:66` is actually in `AGENTS.md`'s Commands table, but
  `flake.nix` carries the equivalent phrase in its check comments).
- `AGENTS.md:138` — the rule statement itself: `` No `pacman` or `yay`, not
  even in comments. ``
- `intent/2026-09-19-1-devenv-plugin.md:118` and
  `plan/2026-09-19-1-devenv-plugin.md:291,471` — the original plan for issue
  #1 quoting the rule while designing the very check this spec is now
  changing.

**Resolution: widen the scope, then carve out an explicit, narrow, commented
exclusion for exactly the files whose job is to talk *about* the rule —
`AGENTS.md`, `flake.nix` itself, and the closed `intent/`, `spec/`, `plan/`
directories.** Not rewording AGENTS.md: the rule's whole value is a human
maintainer reading it and knowing, in plain words, which two commands are
banned. Obscuring `pacman`/`yay` behind a paraphrase to dodge a grep pattern
makes the governing document worse at its one job in order to make a shell
script simpler — backwards. Not narrowing the rule text either (the other
option the intent raised): the rule already says "not even in comments",
and the actual gap is real — `README.md`, `docs/`, `share/*.jsonc`,
`tests/`, `CLAUDE.md`, `manifest.json` and `devenv-binds.lua` are exactly
the kind of file a stray Arch-specific instruction could land in (a code
sample in `docs/usage.md`, a comment in `tests/cli.sh`), and none of them
have any business quoting the rule back at itself.

Concretely, replace the `repo` check's grep (`flake.nix:170-172`) with:

```nix
if grep -rlwE 'pacman|yay' ${self} \
    --exclude-dir=.git --exclude-dir=result \
    --exclude=flake.nix --exclude=AGENTS.md \
    --exclude-dir=intent --exclude-dir=spec --exclude-dir=plan; then
  echo "Arch package manager reference above" >&2; exit 1
fi
```

`.git` and `result` are never present in `${self}` (flakes copy only
git-tracked paths, and `result` is untracked), so those two excludes are
belt-and-braces for anyone who later copies this pattern somewhere `self`
isn't the source. Verified today: with this exact command run against the
working tree, output is empty and the check passes — the four hits above
are exactly the four excluded paths, nothing else in the repo matches.

`CLAUDE.md` needs no exclusion: it is one line, `@AGENTS.md`, so it already
passes; it was just never scanned before. `spec/` currently has no hits, but
gets the same exclusion as `intent/`/`plan/` for the same reason (a
`spec/*.md` written for a future issue could legitimately quote the rule
while proposing to change it — this very file does, four paragraphs up).

The plugin check's own grep (`flake.nix:148`, over `${plugin}/*.qml
${plugin}/*.js`) is left as is. It is now strictly redundant — the widened
`repo` check already scans those same files before they're copied into the
package — but removing it touches the same lines the still-open `fix/8-remove-dead-code`
branch already rewrites (its spec explicitly consolidates these two greps
into one), and merging that dedup here would create an avoidable conflict
with an in-flight branch for a change this issue doesn't need. Leave the
harmless duplication; note it as a follow-up for whichever branch lands
second.

### #18 — a reference check, not a QML parser

**Investigated the parser option and it doesn't fit.** `qt6.qtdeclarative`
is in nixpkgs and its `dev` output carries `qmllint`, but this plugin's QML
is Quickshell QML: every packaged file imports `Quickshell`,
`Quickshell.Hyprland`, `Quickshell.Io`, or `Quickshell.Wayland`
(`Panel.qml:2-3`, `Menu.qml:2-4`, `DevenvState.qml:4-5`), plus the shell's
own `qs.Ui`/`qs.Commons` modules (`CreateForm.qml:3-4` and every other
file). `qmllint` has no `.qmltypes` for Quickshell — it isn't in nixpkgs,
and pulling it in as a check dependency means either a new flake input
(network, against the constraint) or vendoring its type stubs, which is
more machinery than the defect being closed. A parser check would also only
catch *syntax* errors, not the actual failure mode in #18, which is a
*missing file* — syntactically valid QML that imports a sibling component
nobody remembered to add to `files`. A syntax check doesn't see that at all.

**So: a reference check**, resolving each local component tag and each
`import "…"` string in the packaged QML against the package contents.
Verified this catches the real defect shape and produces zero false
positives on the current tree:

```
$ for f in *.qml; do base=$(basename "$f" .qml)
    for other in *.qml; do obase=$(basename "$other" .qml)
      [ "$obase" = "$base" ] && continue
      grep -qw "$obase" "$f" && echo "$f references $obase"
    done; done
DevenvView.qml references CreateForm
DevenvView.qml references DevenvState
DevenvView.qml references EnvList
DevenvView.qml references LogView
DevenvView.qml references ShortcutSheet
Menu.qml references DevenvState
Menu.qml references DevenvView
Panel.qml references DevenvState
Panel.qml references DevenvView
Panel.qml references Menu
```

Every one of those ten pairs is already in `files` (`flake.nix:15-29`), so
the check is a no-op today, as it should be. The quoted-import half is
needed separately because Quickshell resolves sibling `.qml` components by
bare filename (no `import` line — that's why the ten pairs above have no
matching `import` statement), but `Model.js` is pulled in explicitly:
`import "Model.js" as Model` appears in every file (`grep -ohE 'import
"[^"]+"' *.qml` returns exactly `import "Model.js"`, deduplicated). Both
forms need checking or the JS half of the same defect goes uncaught.

New check, `checks.<system>.files`, added after `plugin` (`flake.nix:156`):

```nix
files = let plugin = self.packages.${system}.plugin; in
  pkgs.runCommand "nixarchy-devenv-files-check" { } ''
    fail=0
    # Every local component a packaged .qml references (Quickshell
    # resolves siblings by bare filename) must itself be packaged.
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
      # And every explicit import "path" (Model.js today).
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

The candidate component names come from `${self}/*.qml` (the whole repo),
not `${plugin}/*.qml` (only what's packaged) — that's the difference that
actually catches drift: a new `NewWidget.qml` created at the repo root and
referenced from `DevenvView.qml` but never added to the `files` list exists
in `${self}` but not `${plugin}`, so the loop finds the reference, looks for
`${plugin}/NewWidget.qml`, doesn't find it, and fails. No IFD (both `self`
and `plugin` are ordinary flake/package references already used the same
way by the `repo` and `plugin` checks), no new build inputs, and it's a
handful of `grep`/`basename` calls over eight small files — negligible
runtime next to the existing checks.

### #19 — evaluate against a minimal stub, inside a check

**Untestable-in-a-flake-check was the fallback option; a stub turned out to
work and was verified live.** The module (`flake.nix:54-70`) touches exactly
two pieces of the real Home Manager surface: it *defines* its own option
(`config.programs.nixarchy-devenv.keybinding`) and it *sets*
`home.file."<path>".text`. It never reads any other Home Manager option, so
the stub only has to declare `home.file` with a `text` field — nothing else
of Home Manager needs to exist. Confirmed by running it standalone:

```
$ nix eval --impure --expr 'let
    flake = builtins.getFlake "/mnt/data/Source-home/nixarchy-devenv";
    lib = flake.inputs.nixpkgs.lib;
    stub = { lib, ... }: {
      options.home.file = lib.mkOption {
        type = with lib.types; attrsOf (submodule { options.text = lib.mkOption { type = str; }; });
        default = { };
      };
    };
    evaluated = lib.evalModules { modules = [ stub flake.homeManagerModules.default ]; };
  in {
    defaultBind = evaluated.config.programs.nixarchy-devenv.keybinding;
    fileText = evaluated.config.home.file.".config/hypr/devenv-binds.lua".text;
  }'
{ defaultBind = "SUPER + ALT + E"; fileText = "-- nixarchy.devenv: open Dev environments from the keyboard.\n...\no.bind(\"SUPER + ALT + E\", \"Dev environments\", \"omarchy-shell shell toggle nixarchy.devenv '{}'\")\n"; }
```

That matches `devenv-binds.lua`'s real content with the placeholder
substituted, confirming the intent's "hand-evaluation shows it is correct
today" and giving a concrete pass/fail assertion to pin. `lib.evalModules`
is pure Nix evaluation (no derivation involved, so no IFD), it needs no
network (only `nixpkgs.lib`, already an input), and it's system-independent
(`lib.evalModules` doesn't touch `pkgs`), so it's cheap to run once per
`forAll` iteration.

New check, `checks.<system>.homeManagerModule`, added after `model`
(`flake.nix:124`):

```nix
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

This forces `self.homeManagerModules.default` to be evaluated by every
`nix flake check` / `--all-systems --no-build` run, on every system, which
is the actual defect (#19 says the output is "never evaluated", not "wrong
today"). It does not, and cannot without depending on Home Manager itself
(a new, network-fetched input), make nix's own "unknown flake output
'homeManagerModules'" schema warning go away — that warning is nix
checking the output name against its built-in flake schema, which doesn't
know the name `homeManagerModules` (Home Manager isn't part of Nix), and is
orthogonal to whether the value is evaluated. The intent's proposed outcome
only asks for evaluation, not for the warning's removal, so this is in
scope; making the warning disappear is not, and would cost a real
dependency to buy silence on a message that's accurate (nix genuinely
doesn't recognize the output).

### One PR or three?

One. The intent document is already the single point that ties #17, #18 and
#19 together (`intent: intent/2026-09-24-17-flake-checks.md`, "Closes #17,
#18, #19") — the artifact workflow already decided this at the intent
stage. All three changes sit in the same ~20-line region of one file
(`flake.nix:90-175`), touch nothing else, and don't depend on each other, so
one commit per issue inside one PR gives full per-issue revertability
(`git revert` any one commit) without three rounds of rebasing the same
lines. Three PRs would only pay off if reviewers needed to approve them on
different timelines, which nothing here suggests.

## Alternatives rejected

- **Reword AGENTS.md so its rule text never contains `pacman`/`yay` literally.**
  Rejected above — it defeats the rule's purpose as a document a person
  reads to learn what's banned, in exchange for letting a grep pattern stay
  simpler.
- **Exclude whole directories (`docs/`, `tests/`, etc.) instead of naming the
  four self-referential files.** That's the same mistake the current code
  already made once (narrowing scope to dodge a specific false positive) —
  it would silently re-open the exact gap #17 reports. The exclusion list
  names files by what they *are* (the rule statement and its own design
  history), not by where they happen to live.
- **A real QML/Quickshell parser for #18.** No `.qmltypes` for Quickshell
  exist in nixpkgs; building or vendoring them is disproportionate to a
  missing-file defect, and a parser wouldn't catch a missing file anyway —
  see the Design section above.
- **Add Home Manager as a flake input to evaluate #19 for real, against its
  actual `home.file` implementation.** Violates the no-network constraint
  for `nix flake check`, and the module only touches one field of one
  option (`home.file.*.text`), so a full Home Manager closure buys nothing
  the two-line stub doesn't already give.
- **Leave #19 untestable in-repo, cover it from nixarchy's side instead.**
  Rejected once the stub was shown to work live (see #19 above) — nixarchy
  can still smoke-test the built Home Manager config as a separate,
  complementary check, but there's no reason to give up catching a broken
  module at the source repo when a two-option stub does it in a few lines.
- **Three separate PRs.** Rejected above (One PR or three?) — no benefit
  found, and the intent already bundles the three issues.

## Risks

- **The exclusion list in the `repo` check (`AGENTS.md`, `flake.nix`,
  `intent/`, `spec/`, `plan/`) is itself a place future narrowing could hide
  a real violation**, same as the original #8 narrowing did. Mitigated by
  keeping the list to exactly the files whose *purpose* is to talk about the
  rule, each with an inline comment saying why, and by this spec's
  Verification section planting a violation in a file that is *not*
  excluded (`docs/usage.md`) to prove the boundary is where it's claimed to
  be.
- **The #18 reference check is a heuristic, not a real parser**: a component
  name matched only inside a string literal or a comment (not an actual QML
  tag) would produce a false failure. None of the eight current files do
  this (verified above — the ten hits are all genuine component uses), and
  a false positive fails loud and obviously at `nix flake check` time rather
  than silently passing, which is the safer direction to be wrong in for a
  check whose job is catching drift.
- **The #19 stub can drift from real Home Manager** if `home.file`'s actual
  option type gains behaviour this module implicitly relies on (it
  currently doesn't — it only ever writes `.text`). If a future edit to the
  module starts using another `home.file.*` field (e.g. `.source`), the stub
  needs a one-line addition alongside it; the assert failing with a clear
  "stub doesn't know about X" style message is the signal to do that, not a
  silent gap.
- **Two `pacman`/`yay` greps still exist** (`flake.nix:148` and the widened
  `flake.nix:170`) until the `fix/8-remove-dead-code` branch's own
  consolidation lands. Purely a duplication cost, not a correctness one —
  both are correct, one is now redundant.
- **Hosts:** none of the three changes touch runtime behaviour; all three
  are check-only.

## Verification

Baseline — everything currently passes and stays fast:

```
node tests/run.js
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
nix flake check
nix flake check --all-systems --no-build
```

**#17**, planting a violation in a file the old check never scanned:

```
echo '<!-- pacman -S devenv works too -->' >> docs/usage.md
nix flake check --no-build            # now fails: "Arch package manager reference above"
git checkout -- docs/usage.md
nix flake check --no-build            # passes again
```

And prove the exclusion is exactly as narrow as claimed — the check must
still pass with `AGENTS.md`, `flake.nix`, `intent/`, `spec/`, `plan/`
present and unmodified, containing their existing mentions:

```
grep -rlwE 'pacman|yay' --exclude-dir=.git --exclude-dir=result \
  --exclude=flake.nix --exclude=AGENTS.md \
  --exclude-dir=intent --exclude-dir=spec --exclude-dir=plan .
# → no output
```

**#18**, planting a component that's referenced but never packaged:

```
cp EnvList.qml PlantedWidget.qml
sed -i '1a\    PlantedWidget {}' DevenvView.qml   # reference it without touching flake.nix's files list
nix flake check --no-build            # now fails: "DevenvView.qml references PlantedWidget, but PlantedWidget.qml is not in flake.nix's files list"
git checkout -- DevenvView.qml && rm PlantedWidget.qml
nix flake check --no-build            # passes again
```

**#19**, planting a broken substitution so the stub eval catches it:

```
sed -i 's/"SUPER + ALT + E"\] \[ cfg.keybinding \]/"SUPER + ALT + E "] [ cfg.keybinding ]/' flake.nix   # typo the match string
nix flake check --no-build            # now fails: assertion "homeManagerModules.default stopped substituting..."
git checkout -- flake.nix
nix flake check --no-build            # passes again
```

And confirm the output is no longer silently skipped — before this change
`nix flake check --no-build 2>&1 | grep homeManagerModule` shows only nix's
own schema warning; after, it also shows `checking derivation
checks.<system>.homeManagerModule...`, proof the value was actually forced.

Final check for every change: `nix flake check --all-systems --no-build`
still evaluates cleanly on `aarch64-linux`, and a fresh-clone
`omarchy plugin validate` still passes (none of these changes touch the
packaged files or introduce a symlink).
