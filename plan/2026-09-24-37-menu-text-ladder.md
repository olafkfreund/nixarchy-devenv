---
status: draft
issue: 37
spec: spec/2026-09-24-37-menu-text-ladder.md
---

# Plan: the menu reads larger by climbing the theme's ladder

Self-contained. Closes #37, the regression #12 left in `main`.

## The approved decisions, restated

`DevenvView.qml` gains a `large` flag and five named font roles. Every direct
`Style.font.*` read in the five drawing files moves to the matching role.
`Menu.qml` sets `large: true`; `Panel.qml` sets nothing, so the bar popup must
come out byte-identical.

| Role | Base rung | `large` rung |
| --- | --- | --- |
| `fontRow` | `Style.font.caption` | `Style.font.title` |
| `fontLabel` | `Style.font.body` | `Style.font.heading` |
| `fontGlyph` | `Style.font.iconSmall` | `Style.font.title` |
| `fontIcon` | `Style.font.icon` | `Style.font.heading` |
| `fontHero` | `Style.font.display` | `Style.font.displayLarge` |

Roles pass to children explicitly, as `foreground` and `fontFamily` already do,
and only where used. `flake.nix` gains a guard against multipliers, including a
bare `scale:` transform that the sibling's version misses.

**Correction to the approved spec.** Its table says 39 sites and 26 `caption`.
Counted from source it is **41 sites and 28 `caption`** — `body` 6, `iconSmall`
5, `icon` 1, `display` 1. The design is unchanged; only the arithmetic was
wrong. The per-site table below is authoritative and was generated from the
files, not from the spec.

## Steps

### 1. `DevenvView.qml`: declare the ladder, and move its own 16 sites

Add beside the existing `foreground` and `fontFamily` (`:13-14`):

```qml
// A full-screen surface is read from further away than a bar popup, so the
// menu is bigger -- by picking larger tokens, never by a factor. Every rung
// derives from the theme's [font] base-size, so both surfaces move together
// when the desktop's text size changes, and a theme that pins a token is
// honoured. A multiplier would do neither, and `nix flake check` forbids one.
property bool large: false

readonly property int fontRow:   large ? Style.font.title        : Style.font.caption
readonly property int fontLabel: large ? Style.font.heading      : Style.font.body
readonly property int fontGlyph: large ? Style.font.title        : Style.font.iconSmall
readonly property int fontIcon:  large ? Style.font.heading      : Style.font.icon
readonly property int fontHero:  large ? Style.font.displayLarge : Style.font.display
```

Then replace each site below with `root.<role>`. `Style.font.family` at `:14`
is untouched.

| Line | Was | Becomes |
| --- | --- | --- |
| 353 | `display` | `root.fontHero` |
| 488 | `body` | `root.fontLabel` |
| 500 | `caption` | `root.fontRow` |
| 534 | `iconSmall` | `root.fontGlyph` |
| 548 | `caption` | `root.fontRow` |
| 561 | `iconSmall` | `root.fontGlyph` |
| 574 | `caption` | `root.fontRow` |
| 592 | `caption` | `root.fontRow` |
| 608 | `caption` | `root.fontRow` |
| 618 | `caption` | `root.fontRow` |
| 668 | `body` | `root.fontLabel` |
| 678 | `caption` | `root.fontRow` |
| 714 | `caption` | `root.fontRow` |
| 724 | `caption` | `root.fontRow` |
| 752 | `caption` | `root.fontRow` |
| 765 | `caption` | `root.fontRow` |

→ verify by `grep -c 'Style\.font\.' DevenvView.qml` returning **1** (the
family line), and `nix build && omarchy plugin validate "$(readlink -f result)"`.

### 2. The four children: declare and consume

Each child declares only the roles it uses, defaulted to its current token so
the file still renders correctly if instantiated bare:

```qml
property int fontRow:   Style.font.caption
property int fontLabel: Style.font.body
property int fontGlyph: Style.font.iconSmall
```

| File | Roles to declare | Sites to move |
| --- | --- | --- |
| `EnvList.qml` | `fontRow`, `fontLabel`, `fontGlyph` | 178 `body`→`fontLabel`, 191 `caption`→`fontRow`, 203 `caption`→`fontRow`, 228 `iconSmall`→`fontGlyph` |
| `CreateForm.qml` | `fontRow`, `fontLabel`, `fontGlyph` | 203 `iconSmall`→`fontGlyph`, 212 `body`→`fontLabel`, 300 `body`→`fontLabel`, 315/328/337/368/397/420/436/455 `caption`→`fontRow` |
| `LogView.qml` | `fontRow`, `fontLabel`, `fontGlyph` | 71 `iconSmall`→`fontGlyph`, 81 `body`→`fontLabel`, 91/114/127 `caption`→`fontRow` |
| `ShortcutSheet.qml` | `fontRow`, `fontIcon` | 64 `icon`→`fontIcon`, 73/115/128/144 `caption`→`fontRow` |

Inside each child the reference is the child's own property (`root.fontRow` in
its scope), not `DevenvView`'s.

→ verify by `grep -c 'Style\.font\.' <file>` returning exactly the count of its
`family` uses plus its role **defaults** (3, 3, 3, 2 respectively, plus 1
family each), and by the build.

### 3. `DevenvView.qml`: bind the roles at each instantiation site

Eleven bindings, beside the `foreground:`/`fontFamily:` already there:

- `EnvList`: `fontRow: root.fontRow`, `fontLabel: root.fontLabel`, `fontGlyph: root.fontGlyph`
- `CreateForm`: the same three
- `LogView`: the same three
- `ShortcutSheet`: `fontRow: root.fontRow`, `fontIcon: root.fontIcon`

→ verify by the build, and by confirming each instantiation site carries the
roles its child declares.

### 4. `Menu.qml`: set the flag

Add `large: true` to the `DevenvView` inside the `Flickable` added by #12.
`Panel.qml` is not touched.

→ verify by `grep -n 'large' Menu.qml Panel.qml` showing one hit, in `Menu.qml`.

### 5. `flake.nix`: forbid multipliers

Into the `plugin` check, after the hardcoded-colour grep:

```sh
# The desktop already has one text-size control: [font] base-size, which
# every Style.font.* and Style.space() scales from. A multiplier on top keeps
# this plugin a fixed percentage above every other surface at every setting,
# and silently overrides a theme that pins a token. A surface that wants to
# be bigger picks a larger token.
if grep -nwE 'textScale|uiScale' ${plugin}/*.qml; then
  echo "text multiplier above; pick a larger Style.font.* token" >&2; exit 1
fi
if grep -n 'px(' ${plugin}/*.qml; then
  echo "px() multiplier above; pick a larger Style.font.* token" >&2; exit 1
fi
if grep -nE '(pixelSize|fontSize|iconSize):' ${plugin}/*.qml \
   | grep -vE '(pixelSize|fontSize|iconSize): *(Style\.font\.[A-Za-z]+|root\.font[A-Z][A-Za-z]*)( |$)'; then
  echo "font size above is neither a Style.font.* token nor a font* role" >&2; exit 1
fi
# The sibling's three greps catch a multiplier by NAME. #12's defect was a
# `scale:` transform, and a bare one slips past all three -- verified. It
# magnifies after layout, so wrapping and eliding are computed at one size
# and stretched to another.
if grep -nE '^[[:space:]]*scale:' ${plugin}/*.qml; then
  echo "scale: transform above; it magnifies after layout, so text is laid out at the wrong size" >&2; exit 1
fi
```

→ verify by the planted violations under Tests.

## Tests

Nothing here changes behaviour the suites observe; they run to show no
regression.

```
node --test 'tests/model/*.test.js'                                            76 pass, 0 fail
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"   93 passed, 0 failed
nix flake check --all-systems --no-build                                       all checks passed
nix build && omarchy plugin validate "$(readlink -f result)"                   exit 0
```

Each new guard proven by planting a violation in `DevenvView.qml`, running
`nix build .#checks.x86_64-linux.plugin -L`, confirming the named message, then
`git checkout -- DevenvView.qml`:

| Plant | Expected message |
| --- | --- |
| `readonly property real uiScale: 1.2` | `text multiplier above` |
| `font.pixelSize: px(12)` | `px() multiplier above` |
| `font.pixelSize: 18` | `neither a Style.font.* token nor a font* role` |
| `scale: 1.2` | `scale: transform above` |

The bar popup is the thing at risk and nothing automated can see it, so it is
checked by reading: every base rung in the table above must be the token that
site uses on `main` today. `git diff main -- Panel.qml` must be empty.

On a real display, **together with #12's outstanding verification** — that
check was never done, and this change alters what it would look at:

1. The menu reads larger than the bar popup, and looks like larger type rather
   than a magnified picture: sharp glyph edges, no stretched wrapping.
2. `omarchy display text size` up and down: both surfaces move together, the
   menu staying a rung above rather than a fixed percentage.
3. A short or portrait screen, and a compositor scale other than 1: nothing
   clipped, the view scrolls when it does not fit.
4. `?` opens the shortcut sheet and it scrolls rather than overflowing — the
   component most likely to look cramped at `large`.
5. `hyprctl layers -j` read into a variable, never piped to `grep -q`: under
   `pipefail` that SIGPIPEs `hyprctl` and reads as "closed" while the menu is
   up. That false reading was #6.
6. `qs log -i <instance>` clean.

## Rollback

Per-commit `git revert`, in reverse order; each commit leaves the tree green.

- **Step 5** — removes the guard. Multipliers become possible again, which is
  how #12's regression happened, so this is the last one to revert.
- **Step 4** — the menu returns to bar-popup text size: back to the #37 state,
  still without the clipping #12 fixed.
- **Steps 3, 2, 1** — revert together. Reverting step 1 alone leaves the
  children binding roles nothing declares.

Reverting all five returns to `main` as it stands: #12's fix intact, #37 open.
