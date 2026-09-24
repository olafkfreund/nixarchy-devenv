---
status: draft
issue: 37
intent: intent/2026-09-24-37-menu-text-ladder.md
---

# Spec: the menu reads larger by climbing the theme's ladder

## Design

### The ladder

`DevenvView.qml` gains a `large` flag and five named font roles, each a rung
higher when it is set. Every call site that reads `Style.font.*` directly moves
to the matching role.

The five roles were derived from what this view actually draws, not copied from
the sibling. Counting every `Style.font.*` use across the five drawing files
(39, excluding `family`, which is already threaded separately):

| Role | Base rung | `large` rung | Sites | Where |
| --- | --- | --- | --- | --- |
| `fontRow` | `caption` | `title` | 26 | row text, hints, field labels, key labels |
| `fontLabel` | `body` | `heading` | 6 | headers, the filter field, the log's title |
| `fontGlyph` | `iconSmall` | `title` | 5 | inline glyphs beside text |
| `fontIcon` | `icon` | `heading` | 1 | `ShortcutSheet`'s sheet glyph |
| `fontHero` | `display` | `displayLarge` | 1 | `DevenvView:353`, the empty-state glyph |

That is the same five roles `nixarchy.distrobox` settled on, and the same
mapping. Worth stating because the intent flagged it as an open question: the
distribution here is dominated by `caption` (26 of 39), but it still decomposes
into exactly those five, so there is no reason to diverge.

`large` is set in one place, `Menu.qml`'s `DevenvView`. `Panel.qml` sets
nothing and keeps the base rungs, so the bar popup is byte-identical.

### How the roles reach the children

`DevenvView` already hands `foreground` and `fontFamily` to each drawing
component it instantiates. The roles follow that existing pattern rather than
introducing a second one: each child declares the roles it uses as
`property int`, and `DevenvView` binds them at the instantiation site.

Only what each child actually uses is passed, which keeps the wiring to eleven
bindings rather than twenty:

| Child | Roles it needs |
| --- | --- |
| `EnvList` | `fontRow`, `fontLabel`, `fontGlyph` |
| `CreateForm` | `fontRow`, `fontLabel`, `fontGlyph` |
| `LogView` | `fontRow`, `fontLabel`, `fontGlyph` |
| `ShortcutSheet` | `fontRow`, `fontIcon` |

The alternative — passing `large` down and letting each child map its own
rungs — is less wiring but puts five copies of the ladder in five files, where
a later edit can make one surface disagree with another. The ladder is the
thing worth keeping in one place.

### The check that stops it coming back

A new guard in `flake.nix`'s `plugin` check, ported from
`nixarchy.distrobox:108-126` with one addition. Three of its greps port
verbatim:

1. `textScale|uiScale` by name;
2. `px(`, a multiplying helper;
3. any `pixelSize|fontSize|iconSize:` whose value is neither a `Style.font.*`
   token nor a `root.font*` role — this is the strong one, since it makes every
   font size in the package either a token or a named rung.

The addition: a bare `scale:` transform on an `Item`. Tested against all three
of distrobox's greps, `scale: 1.45` with no named property **is missed by every
one of them** — they catch the multiplier by its name, which would have caught
#12's code but not an anonymous transform. Since a `scale:` transform is the
precise defect this exists to prevent, and is what #12 actually had, the guard
has to name it:

```sh
if grep -nE '^[[:space:]]*scale:' ${plugin}/*.qml; then
  echo "scale: transform above; it magnifies after layout, so wrapping and eliding are computed at the wrong size" >&2; exit 1
fi
```

## Alternatives rejected

- **Leave it as #12 left it.** The menu works and nothing is clipped, but the
  deliberate difference between a full-screen surface and a bar popup is gone.
  The multiplier was wrong; what it was for was not.
- **Restore a multiplier, applied to token values rather than as a transform.**
  Avoids the layout-then-stretch problem but keeps the rest: still a fixed
  percentage above every other surface at every text size, and still overrides
  a theme that pins a token. The new check forbids it precisely because it looks
  reasonable.
- **Let each child map its own rungs from a `large` flag.** Less wiring, five
  copies of the ladder. Rejected above.
- **Port distrobox's check verbatim.** Rejected on evidence: it misses a bare
  `scale:` transform, which is the defect in question.
- **A `scale:` guard alone, without the other three greps.** Would have caught
  #12 but not a flat multiplier applied to sizes, which is the more tempting
  wrong answer once a transform is forbidden.

## Risks

- **The bar popup changing by accident.** It must be byte-identical. The base
  rungs are exactly the tokens each site uses today, so a site that moves to a
  role and keeps its rung renders the same — but a wrong base rung in the table
  would change the popup silently, since nothing tests appearance. Mitigated by
  checking each of the 39 sites against the table rather than by pattern.
- **`ShortcutSheet` on a short screen.** It already has its own `Flickable`.
  At `large` its rows grow, so it will scroll sooner. That is correct
  behaviour, but it is the component most likely to look cramped first, and the
  sibling repo has an open issue about exactly this (`nixarchy-podman#17`).
- **The third grep is strict by design.** Any future font size that is neither
  a token nor a `root.font*` role fails the build. That is the point, but it
  will catch legitimate-looking code and needs its message to say what to do.
- **Nothing here is provable by a build.** Both suites and `nix flake check`
  can pass with the ladder mapped wrongly.

## Verification

Automated, all of which must pass unchanged — none of them can see the result:

```
node --test 'tests/model/*.test.js'
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"
nix flake check --all-systems --no-build
nix build && omarchy plugin validate "$(readlink -f result)"
```

The new guard proven by planting each violation and confirming it fails, then
reverting: a `uiScale` property, a `px(` call, a `font.pixelSize: 18`, and a
bare `scale: 1.2`.

On a real display, per AGENTS.md's "Verifying live", and **together with #12's
outstanding verification** — that check has not been done, and this change
alters what it would be looking at, so doing #12's first would verify something
about to be replaced:

1. The menu reads larger than the bar popup, and the difference looks like
   larger type rather than a magnified picture — glyph edges sharp, no
   stretched wrapping.
2. `omarchy display text size` moved up and down: both surfaces move together,
   and the menu stays a rung above rather than a fixed percentage.
3. A short or portrait screen, and a compositor scale other than 1: nothing is
   clipped, and the view scrolls if it does not fit.
4. `hyprctl layers -j` read into a variable, not piped to `grep -q` — under
   `pipefail` that SIGPIPEs `hyprctl` and reads as "closed" while the menu is
   on screen.
5. `qs log -i <instance>` clean.
