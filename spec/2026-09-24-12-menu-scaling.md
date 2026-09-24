---
status: approved
issue: 12
intent: intent/2026-09-24-12-menu-scaling.md
---

# Spec: the menu follows the desktop's size, instead of a fixed magnification

## Design

**What "the desktop scale that is already set" concretely means here.** Two
scales are already in effect before `Menu.qml` does anything:

- Hyprland's per-monitor `scale` is applied by the compositor to the whole
  Wayland surface's logical-pixel space. Qt draws in logical pixels and the
  compositor (and, for the buffer, `devicePixelRatio`) handles the rest — this
  is exactly why `AGENTS.md`/the intent are right that `devicePixelRatio` must
  stay out of layout maths.
- The theme's own scale is already applied by `Style.qml`: `Style.space(n)`
  multiplies by `effectiveSpacingScale = spacingScale * fontScale`
  (Style.qml:213-223), and every `Style.font.*` token is
  `Math.round(fontBaseSize * mult)` (Style.qml:279-338). `Menu.qml` already
  uses both (`Style.space(680)` for `viewWidth`, and every size inside
  `DevenvView`/`EnvList`/etc. goes through `Style.*`).

So by the time `Menu.qml:32` applies `uiScale: 1.45` as a `scale:` transform
(Menu.qml:144), the view has *already* been laid out at the desktop's actual
scale twice over — once by the compositor, once by the theme. `uiScale` is a
third, unconditional multiplication on top of both, sourced from neither: it
is a constant nixarchy-pkg's menu happened to use, copied here as "the same
factor nixarchy-pkg's menu uses" (Menu.qml:30-31).

**Evidence from the shell's own full-screen surfaces.** The shell's own
full-screen menu, `plugins/menu/Menu.qml`, is the closest first-party
comparison (same kind of surface: `PanelWindow`, `WlrLayer.Overlay`,
`WlrKeyboardFocus.Exclusive`, a card centered over a scrim). It sizes its
card directly from `Style.space()` tokens and clamps to the screen:

```
cardWidth: Math.min(..., Style.space(300..520), panel.width - Style.gapsOut * 2)
cardHeight: Math.min(contentMargin*2 + headerHeight + ..., panel.height - Style.gapsOut*2)
```

There is no `scale:` transform anywhere in that file, and `grep -rn "scale:"`
across the whole shell tree turns up exactly two other uses, both of them
telling:

- `Ui/SpeedTestOverlay.qml:120` and `plugins/panels/wifiqr/Panel.qml:247`:
  `scale: Math.min(1, availableWidth / contentWidth, availableHeight /
  contentHeight)` — a **shrink-only** clamp so a QR/speedtest card fits a
  small or heavily-scaled output, never a multiplier that enlarges it.
- `plugins/panels/monitor/Panel.qml:215`: `scale: root.monitorScale` — this is
  a data field in an IPC JSON payload (the monitor's own reported scale
  factor), not a QML transform at all.

No shell surface ever uses `scale:` to make itself *larger* than its
theme-scaled layout. The honest reading the intent asked for is confirmed:
**`uiScale` should be removed, not replaced with a computed value.** There is
no "desktop scale" left to derive — both scales that exist are already
applied, and inventing a third one (any formula for `uiScale`) would just be
a new unjustified magic number replacing the old one.

**The fix, concretely, in `Menu.qml`:**

- Delete `readonly property real uiScale: 1.45` (Menu.qml:32) and its comment
  (Menu.qml:29-31).
- `card.width`/`card.height` (Menu.qml:116-119) drop the `* root.uiScale`
  factor: `Math.min(root.viewWidth + insets, Math.round(panel.width * 0.9))`
  and `Math.min(Math.round(view.implicitHeight) + insets, Math.round(panel.height
  * 0.85))`, i.e. the same shape `plugins/menu/Menu.qml`'s `cardWidth`/
  `cardHeight` already use — clamp to a fraction of the screen, nothing else.
- `DevenvView` (Menu.qml:138-151) drops `scale: root.uiScale`,
  `transformOrigin: Item.TopLeft`, and the `/ root.uiScale` division on
  `width`/`height`: it becomes `width: frame.width; height: frame.height`,
  laid out 1:1 like the bar popup's copy in `Panel.qml:113-120`. Input mapping
  is not "preserved through a replacement" — it stops being needed. A 1:1
  layout has no click-to-content coordinate transform to preserve; removing
  the transform removes the class of bug entirely rather than reimplementing
  it correctly.

**Is removing the magnification alone enough, or is an outer `Flickable`
still needed?** Not enough on its own. The clamp survives
(`card.height` still caps at `panel.height * 0.85`) and `frame` still clips
(Menu.qml:136), because both are legitimate: a full-screen surface should
never grow past the screen. Without `uiScale`, the *common* case (default
theme, normal screen) now fits comfortably — `view.implicitHeight` was only
ever tight because of the 1.45× multiplier — but the *edge* case the intent
names explicitly (a raised theme `base-size`, or a short/portrait screen)
can still make `view.implicitHeight` alone exceed 85% of the screen, because
`Style.space`/`Style.font` scale with the theme too. `DevenvView`'s `Column`
(DevenvView.qml:339-624) has no scrolling of its own — only `EnvList` and
`LogView` scroll internally, each within its own fixed slice of the column.
If the column's total height ever exceeds the clamp, the footer/status
lines below the list are unreachable exactly as they are today, just at a
higher (theme-size or aspect-ratio) threshold instead of a font-size-1.0
threshold.

The fix: wrap `DevenvView` in a `Flickable` inside `Menu.qml`'s `frame`,
sized to `frame`, with `contentHeight: view.implicitHeight` — the same
shape `ShortcutSheet.qml`'s own `flick` already uses inside this same
view (`ShortcutSheet.qml:39`, and referenced from `DevenvView.qml:626-635`
as `helpSheet`), and the same shape the shell's `plugins/menu/Menu.qml`
scroll list and `ShortcutSheet`/`SearchableDropdown`/etc. across the shell
tree already use for exactly this reason (`grep -rln "Flickable"` lists
`SearchableDropdown.qml`, `Dropdown.qml`, `MultiSelect.qml`, `Tray.qml`, and
several plugin panels — an outer `Flickable` around content that occasionally
overflows its clamp is the shell's established vocabulary, not a new idea
introduced here). `DevenvView` keeps `implicitHeight: column.implicitHeight`
unchanged, so `Panel.qml`'s bar-popup usage (`view.implicitHeight` feeding
`panel.fittedContentHeight`) is untouched — the `Flickable` is added only in
`Menu.qml`, around the existing `DevenvView`, not inside it. Change shape:

```
Item { id: frame; ... ; clip: true
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
      ...
    }
  }
}
```

`EnvList`'s internal `ListView` stays `interactive: contentHeight > height`
(EnvList.qml:78) so it only claims wheel/drag events when it actually has
more rows than its own slice; otherwise they fall through to `viewFlick`,
same as any other nested-`Flickable` case in this shell. Keyboard scrolling
is unaffected either way: cursor movement and `j`/`k`/`PageUp`/`PageDown`
inside `EnvList`/`LogView`/`ShortcutSheet` already call `positionViewAtIndex`/
set `contentY` directly rather than relying on wheel/drag, and none of that
code changes.

**Sibling plugins (distrobox, microvm, podman).** This repo diverges first.
See Alternatives rejected.

## Alternatives rejected

- **Derive `uiScale` from screen height/DPI/theme `base-size`.** Rejected per
  the owner's directive and the evidence above: both scales the desktop
  already sets (compositor + theme) are already applied to the view before
  `uiScale` is multiplied in. A derived `uiScale` would still be a second,
  redundant scaling pass layered on top of the first — it would only change
  *which* magic number causes the same class of bug, not whether one exists.
  It would also cost a second reference point ("derived from what baseline?")
  that the owner explicitly declined to give, because the requirement is to
  be correct at whatever scale is set, not tuned to one.
- **Keep `uiScale` but shrink-clamp it like `wifiqr`'s
  `scale: Math.min(1, ...)`.** i.e., keep the transform but cap it at 1 so it
  can shrink a surface that doesn't fit, never enlarge one that does. This
  was considered because it's the one legitimate use of `scale:` found
  elsewhere in the shell. Rejected: it still keeps a transform (and the
  input-mapping code that goes with it) alive for a surface that, once
  correctly laid out at 1:1, essentially never needs shrinking — the
  `Flickable` handles the rare overflow case more simply, without any
  transform or click-coordinate math at all. Removal is the smaller diff and
  the smaller number of failure modes.
- **Add the `Flickable` without removing `uiScale`.** Would paper over the
  truncation but leave the actual defect (an unjustified 1.45× magnification
  with no source in "the desktop scale") in place, directly contradicting the
  owner's directive. Also would still need the scale/click-mapping code kept
  correct on top of scroll math — strictly more moving parts for no benefit.
- **Wrap the `Flickable` inside `DevenvView.qml` itself, rather than around
  it in `Menu.qml`.** Considered so the scroll-safety net would also cover
  the bar popup. Rejected for this change: the bar popup is explicitly out of
  scope ("already screen-aware through the shell's fitting helpers", per the
  intent), and `Panel.qml` already fits `KeyboardPanel`'s content to
  `panel.fittedContentHeight(view.implicitHeight)`, which is a different
  sizing contract than the menu's fixed 85%-of-screen clamp. Touching
  `DevenvView.qml`'s root layout would risk that contract for a surface this
  issue doesn't need to touch. If the bar popup is later found to have the
  same truncation risk, that is a separate, smaller issue — reusing the
  `Flickable` shape shown here.
- **Change distrobox/microvm/podman in the same PR.** Rejected for the first
  landing. See Risks.

## Risks

- **Sibling plugins keep the same defect until ported.** distrobox, microvm
  and podman carry a byte-identical `uiScale: 1.45` block (confirmed:
  `~/.config/omarchy/plugins/nixarchy.{distrobox,microvm,podman}/Menu.qml`,
  same line numbers, same comment). Recommendation: **this repo diverges
  first.** The fix here is a behavior change that "cannot be verified from a
  build alone" (per the intent) — it needs a real display, at more than one
  theme `base-size` and screen shape, before it's trusted. Landing it in one
  repo, verifying it live per the Verification section below, and only then
  porting the identical diff to the other three is lower risk than editing
  four plugins on one unverified assumption. Because the blocks are
  byte-identical, the ported diff is mechanical once this one is confirmed
  good — record that follow-up as its own issue per repo (or one tracking
  issue that lists all three), not done silently in this PR.
- **`CreateForm.qml`'s "ignores the menu's scale" comment goes stale.**
  CreateForm.qml:14-16 says pickers are drawn inline rather than as a
  `QQC Popup` because "a Popup is reparented to the overlay and would ignore
  the menu's scale." Once `uiScale` is gone there is no scale for a Popup to
  ignore, but the *reason the constraint still holds* doesn't change: this
  plugin still has no `QQC Popup` anywhere, on purpose, for other reasons
  (keyboard-first navigation, `keepLoaded` surfaces). The comment should be
  reworded in the same commit as the removal so it doesn't cite a mechanism
  that no longer exists, but the actual rule (no `Popup`) does not change and
  is out of scope to relitigate here.
- **Nested `Flickable`/`ListView` wheel handling.** Adding `viewFlick` around
  a view that already contains one internally-scrolling `ListView`
  (`EnvList`) and one `Flickable` (`ShortcutSheet`'s `helpSheet`, drawn as a
  sibling overlay, not inside the column) introduces one more level of
  nesting than exists today. Qt Quick's default behavior (an inactive inner
  `Flickable` lets wheel/drag fall through to the next one up) is exactly
  what's relied on here, and it's the same pattern already used elsewhere in
  the shell (e.g. `SearchableDropdown.qml`'s list inside a popup). Low risk,
  but it is a real behavior to eyeball on a real display, not just infer from
  the code — see Verification.
- **`view.implicitHeight` inside a `Flickable` needs an explicit `height`.**
  `DevenvView`'s `implicitHeight: column.implicitHeight` (DevenvView.qml:22)
  only works as a size hint when something reads it and assigns it forward —
  a `Flickable`'s content does not auto-participate in implicit sizing the
  way an anchored item does. The replacement `DevenvView { height:
  implicitHeight }` inside `viewFlick` must set `height` explicitly (as shown
  in Design) or `contentHeight` collapses to 0 and nothing scrolls. Called
  out here so the implementer doesn't drop it while deleting the `uiScale`
  lines.

## Verification

A build proves the QML is syntactically valid and `nix flake check` passes;
it cannot prove the fix, because the defect is about pixels on a real
screen at a real theme scale, which nothing in this repo's test suite
renders. Verification is manual, on a real nixarchy desktop, following
`AGENTS.md`'s "Verifying live" procedure:

1. Build and install a real copy (not a symlink — `AGENTS.md` is explicit
   that a symlinked checkout does not reload): `nix build`, then replace
   `~/.config/omarchy/plugins/nixarchy.devenv` with `result` per the
   procedure, `rescanPlugins`, `omarchy-restart-shell`.
2. **Baseline (default theme, normal screen).** Open the menu
   (`omarchy-shell shell toggle nixarchy.devenv '{}'`) with a handful of real
   or `demo-*` environments loaded (enough rows that `EnvList` scrolls
   internally). Confirm: footer, status line and key hints are visible
   without scrolling; the list still scrolls with j/k and the mouse wheel;
   clicking a row's action buttons (enter/edit/update/allow/remove) lands on
   the right row — this is the check that losing the `scale:` transform
   didn't break click targeting anywhere in the card.
3. **Raised theme font size.** Raise the theme's `[font] base-size` (or
   trigger it via the shell's own font-size mechanism — `Style.font`/
   `Style.spacing` scale together) enough that `view.implicitHeight` would
   have exceeded the clamp under the *old* 1.45× multiplier at the default
   size. Reopen the menu: confirm the surface either fits, or — if it's still
   taller than 85% of the screen at this size — the whole view scrolls via
   the new `Flickable` and every row of the footer is reachable by scrolling,
   not just the ones above the old truncation point.
4. **Short / portrait screen (or a laptop panel if that's what's on hand).**
   Repeat step 3's reachability check on whatever short or narrow output is
   available. If none is available, this step is explicitly called out as
   unverified in the PR description rather than skipped silently.
5. **Compositor scale.** With Hyprland's per-monitor `scale` set to something
   other than 1 (e.g. 1.25 or 1.5, whatever the owner's actual monitors use —
   the intent notes the owner didn't give a specific value, so use what's
   configured), confirm text and controls are the same *proportional* size
   as the rest of the shell (bar, other plugin popups) — i.e. the menu isn't
   visibly smaller or larger than everything else drawn on that same output.
   This is the direct check on "it needs to follow the desktop scale that is
   already set."
6. **`hyprctl layers -j`** shows the `nixarchy-devenv-menu` namespace present
   and gone correctly across open/close, unchanged from before this change
   (this fix touches only sizing/transform, not the `PanelWindow`/layer-shell
   wiring).
7. Re-run the Node/CLI test suites (`node tests/run.js`,
   `bash tests/cli.sh ...`, `nix flake check`) — they won't catch the visual
   defect, but they confirm nothing in `Model.js` or the CLI regressed as a
   side effect of a QML-only change, and `nix flake check`'s no-hardcoded-
   hex-colours / no-symlinks gates still apply to whatever the implementer
   touches.

Record which of steps 2-5 were actually run, on what hardware/theme
settings, in the PR description — per the intent, this cannot be verified
from a build alone, so the PR needs to say what real-display checking backs
the claim that it's fixed, not just link to a green CI run.
