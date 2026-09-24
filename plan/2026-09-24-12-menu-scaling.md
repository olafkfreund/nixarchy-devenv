---
status: draft
issue: 12
spec: spec/2026-09-24-12-menu-scaling.md
---

# Plan: the menu follows the desktop's size, instead of a fixed magnification

Self-contained summary of the approved decisions carried from the spec:

- Delete `uiScale` entirely, no computed replacement. The compositor's
  per-monitor `scale` and the theme's `Style.space`/`Style.font` scale are
  both already applied to the view before `uiScale` runs a third,
  unjustified multiplication on top. The shell's own full-screen menu
  (`plugins/menu/Menu.qml`) sizes its card straight from `Style.space()`
  tokens with no `scale:` transform at all — that is the pattern to copy.
- Wrap `DevenvView` in a `Flickable`, but **inside `Menu.qml`'s `frame`
  only** — not inside `DevenvView.qml`. `DevenvView.qml` stays untouched so
  `Panel.qml`'s bar-popup usage (`panel.fittedContentHeight(view.implicitHeight)`)
  keeps its own, different sizing contract. The `Flickable` shape to copy is
  `ShortcutSheet.qml`'s `flick` (ShortcutSheet.qml:39-46): `anchors.fill`,
  `contentHeight` bound to the content's `implicitHeight`, `clip: true`,
  `boundsBehavior: Flickable.StopAtBounds`.
- Reword the stale comment at `CreateForm.qml:14-16` in the same commit as
  the `uiScale` removal: it currently justifies avoiding `QQC Popup` by
  saying a Popup "would ignore the menu's scale" — once there is no scale,
  that reasoning is gone, but the no-`Popup` rule itself still holds for
  other reasons (keyboard-first navigation, `keepLoaded` surfaces) and must
  not be relitigated here.
- This repo diverges first and proves the fix live (per the intent's answer
  to open question 3); the identical diff ports to nixarchy.distrobox,
  nixarchy.microvm and nixarchy.podman as separate follow-up issues, not in
  this PR.

Re-verified against `main` at `e254c82` (post-#8, which removed
`onSwitchPanelRequested` wiring from `Menu.qml` as dead code — `Menu.qml`
never had a neighbouring panel to hand off to; `DevenvView.qml`'s
`switchPanelRequested` signal itself is untouched and still used by
`Panel.qml`). `uiScale` and the `* uiScale` card/view arithmetic this plan
removes are all still present, unchanged, at the line numbers below.

## Steps

1. `Menu.qml`: delete `readonly property real uiScale: 1.45` (line 32) and
   its preceding comment (lines 29-31, "A full-screen surface is read from
   further away… Safe here because nothing in the view pops up…") →
   verify by `grep -n uiScale Menu.qml` returning nothing.

2. `Menu.qml`: change `card.width`/`card.height` (lines 116-119) to drop
   the `* root.uiScale` factor, matching the shell's `cardWidth`/
   `cardHeight` clamp-to-screen-fraction shape:
   ```qml
   width: Math.min(root.viewWidth + card.contentLeftInset + card.contentRightInset,
                   Math.round(panel.width * 0.9))
   height: Math.min(Math.round(view.implicitHeight) + card.contentTopInset + card.contentBottomInset,
                    Math.round(panel.height * 0.85))
   ```
   → verify by reading the diff: no `uiScale` reference remains, `viewWidth`
   and `view.implicitHeight` are used at 1:1 (no multiplication), and the
   0.9/0.85 screen-fraction clamps are unchanged from before.

3. `Menu.qml`: wrap `DevenvView` in a `Flickable` inside `frame`, and drop
   the scale transform and the `/ root.uiScale` division on `width`/
   `height`. Replace the current block (lines 129-150, `frame` through its
   closing braces — note `DevenvView` here has no `onSwitchPanelRequested`
   handler post-#8, so none is reintroduced) with:
   ```qml
   Item {
     id: frame
     anchors.fill: parent
     anchors.topMargin: card.contentTopInset
     anchors.rightMargin: card.contentRightInset
     anchors.bottomMargin: card.contentBottomInset
     anchors.leftMargin: card.contentLeftInset
     clip: true

     Flickable {
       id: viewFlick
       anchors.fill: parent
       contentWidth: width
       contentHeight: view.implicitHeight
       boundsBehavior: Flickable.StopAtBounds

       DevenvView {
         id: view
         width: viewFlick.width
         height: implicitHeight
         foreground: Color.foreground
         fontFamily: Style.font.family
         onCloseRequested: root.close()
       }
     }
   }
   ```
   Note `height: implicitHeight` on `DevenvView` is required, not
   decorative: per the spec's Risks section, a `Flickable`'s content does
   not auto-participate in implicit sizing the way an anchored item does,
   so without an explicit `height` binding `contentHeight` collapses to 0
   and nothing scrolls.
   → verify by reading the diff: no `scale:`, no `transformOrigin:`, no
   `/ root.uiScale` anywhere in `Menu.qml`; `DevenvView.width` is
   `viewFlick.width` (1:1, not divided); `nix flake check` (below) catches
   any QML syntax error.

   **Input-mapping re-check, because this is the load-bearing part of the
   fix.** The old code's own comment said "input is mapped through the same
   transform, so clicks still land" (Menu.qml:141) — i.e. Qt Quick's `scale:`
   transform on `DevenvView` scaled both the drawn pixels *and* the
   mouse/touch hit-testing geometry together, so clicks landed correctly
   despite the 1.45x. That transform, and the click-mapping problem it
   solved, are both gone after this step: `DevenvView` is now laid out 1:1
   (`width: viewFlick.width`, no `scale:`), so there is no coordinate
   transform between what's drawn and what's clicked — the class of bug
   (click coordinates not matching drawn coordinates) is removed rather than
   reimplemented. What must be re-checked live, because nothing in the test
   suite exercises pointer hit-testing: every clickable control in
   `DevenvView` (list row actions — enter/edit/update/allow/remove — filter
   field, form fields and buttons, log view controls, `ShortcutSheet`
   dismiss) still receives clicks at the position it's drawn, both when
   `viewFlick` is scrolled to the top and after it has been scrolled down
   (a scrolled `Flickable` translates its content's on-screen position, and
   this repo has never exercised click handling through a scrolled
   ancestor before, since the old view was single-screen-full always). This
   is covered by Tests step 2 below.

4. `CreateForm.qml`: reword the comment at lines 14-16 so it no longer cites
   a scale that no longer exists, while keeping the same rule (no `Popup`
   anywhere in this plugin). Replace:
   ```qml
   // No Popup anywhere: the template and provider pickers are inline lists under
   // their row. A Popup is reparented to the overlay and would ignore the menu's
   // scale.
   ```
   with:
   ```qml
   // No Popup anywhere: the template and provider pickers are inline lists under
   // their row. This plugin is keyboard-first and keep-loaded; a QQC Popup is
   // reparented to the overlay and would sit outside this scope's own
   // navigation and focus handling.
   ```
   → verify by `grep -n "menu's scale" CreateForm.qml` returning nothing, and
   `grep -n "No Popup anywhere" CreateForm.qml` still present.

## Tests

Automated suites that must still pass (none of them can prove the visual
fix — they only prove nothing else regressed). `tests/run.js` no longer
exists (removed by #8); the model suite runs on `node:test` directly:

```bash
node --test 'tests/model/*.test.js'            # expect 70 passing
bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"   # expect 63 passed
nix flake check
```

The defect and the fix are both about pixels on a real screen at a real
theme scale, which nothing in this repo's suite renders. Verification is
manual, on a real nixarchy desktop, per `AGENTS.md`'s "Verifying live"
procedure. Record which of the following were actually run, and on what
hardware/theme settings, in the PR description.

1. **Install a real copy** (a symlinked checkout does not reload):
   ```bash
   nix build
   rm -rf ~/.config/omarchy/plugins/nixarchy.devenv
   cp -rL result ~/.config/omarchy/plugins/nixarchy.devenv
   chmod -R u+w ~/.config/omarchy/plugins/nixarchy.devenv
   omarchy-shell shell rescanPlugins
   omarchy plugin enable nixarchy.devenv   # if not already enabled
   omarchy-restart-shell
   ```
   Wait until `omarchy-shell shell ping` answers, then get the instance and
   watch the log for errors:
   ```bash
   inst=$(qs list --all | grep -i devenv)   # or read the relevant instance by hand
   qs log -i "$inst"
   ```

2. **Baseline (default theme, normal screen) — the click-mapping check.**
   Load a handful of real or `demo-*` environments (enough that `EnvList`
   scrolls internally). Open the menu:
   ```bash
   omarchy-shell shell toggle nixarchy.devenv '{}'
   ```
   Confirm: footer, status line and key hints are visible without scrolling
   the outer `viewFlick`; `EnvList` still scrolls internally with j/k and
   the mouse wheel; clicking a row's action buttons
   (enter/edit/update/allow/remove) lands on the right row both before and
   after scrolling `viewFlick` down and back — this is the direct check that
   losing the `scale:` transform did not break click targeting anywhere in
   the card (see step 3's input-mapping note above).

3. **Raised theme font size.** Raise the theme's `[font] base-size` (or
   however this shell's font-size mechanism is triggered — `Style.font`/
   `Style.spacing` scale together) enough that `view.implicitHeight` would
   have exceeded the 85%-of-screen clamp under the *old* 1.45x multiplier
   even at the default size. Reopen the menu: confirm the surface either
   fits, or — if still taller than the clamp at this size — the whole view
   scrolls via `viewFlick` and every row of the footer is reachable by
   scrolling, not truncated.

4. **Short / portrait screen** (or the smallest panel available). Repeat
   step 3's reachability check. If no such output is available, say so
   explicitly in the PR description as unverified rather than skipping
   silently.

5. **Compositor scale != 1.** With Hyprland's per-monitor `scale` set to
   whatever the owner's actual monitors use (not 1), confirm the menu's
   text and controls are the same *proportional* size as the rest of the
   shell (bar, other plugin popups) on that output — this is the direct
   check on "it needs to follow the desktop scale that is already set."

6. **Layer lifecycle unchanged.** Before and after opening/closing the menu,
   check the layer namespace into a variable (never pipe straight to
   `grep -q` under `pipefail` — `AGENTS.md` records this as the exact false
   reading that caused a prior bug, since `hyprctl layers -j` gets SIGPIPE'd
   while the menu is on screen and reads as "closed"):
   ```bash
   layers=$(hyprctl layers -j)
   echo "$layers" | grep -c "nixarchy-devenv-menu"
   ```
   Confirm the namespace appears while open and is gone after close,
   unchanged from before this change — this fix only touches
   sizing/transform, not the `PanelWindow`/layer-shell wiring.

## Rollback

A single-commit revert of the four steps above restores `uiScale: 1.45`,
the scaled `card.width`/`card.height`, the `scale:`-transformed
`DevenvView` without the `Flickable`, and the original `CreateForm.qml`
comment — `git revert` on the merge commit (or on each of the four
per-step commits, in reverse order, if squash-revert is not used) is
sufficient. No other file changes, no data migration, and no sibling
plugin was touched by this PR, so nothing else regresses on rollback:
distrobox, microvm and podman keep their own byte-identical `uiScale` block
exactly as before, unaffected either by this change landing or by its
revert.
