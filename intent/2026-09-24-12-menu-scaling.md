---
status: draft
issue: 12
author: olafkfreund
---

# Intent: the menu follows the desktop's size, instead of a fixed magnification

Closes #12.

## Problem

Reported by the owner: "the text and the windows needs to follow the desktop
size and scale."

Most of the UI already does, and it is worth recording what was ruled out, so
this is not re-litigated. Two external reviewers claimed the plugin hardcodes
pixel sizes and ignores DPI. Traced to source, that is wrong: the spacing
helper multiplies by the theme's spacing and font scale, the font tokens derive
from the theme's base font size, and `devicePixelRatio` is correctly unused
because Qt and Wayland handle per-output buffer scaling for text and vector
layout automatically. The environment list is a real scrolling list that keeps
the cursor visible.

The one genuinely unscaled value is the full-screen menu's `uiScale`, a bare
`1.45` applied as a QML scale transform on top of everything the theme has
already scaled. On its own that would only make the menu larger. The defect is
the combination: the view as a whole has no outer scroll container — only the
environment list and the log scroll internally — while the card is clamped to a
fraction of the screen height and the frame clips. So whenever the view's
natural height, multiplied by that fixed 1.45, exceeds the clamp, everything
below the list — footer, status line, hints — is truncated with no way to reach
it. Raising the theme's base font size or using a short screen is enough to
trigger it.

The same `uiScale` value and the surrounding card arithmetic are byte-identical
in the distrobox, microvm and podman plugins, so this is a shared house pattern
rather than a defect unique to this repo.

## Proposed outcome

- On any screen the owner actually uses, and at any theme font size, no part of
  the menu is unreachable: either it fits, or it scrolls.
- The menu's size is derived from the screen it opens on rather than from a
  constant.
- Whatever is decided here is written down well enough that the sibling plugins
  can adopt the same change rather than drifting.

## Affected users and systems

Users of the full-screen menu on short screens, portrait monitors, or with a
raised theme font size. `Menu.qml` and possibly `DevenvView.qml`. The bar popup
is already screen-aware through the shell's fitting helpers and is not in
scope. Cross-repo impact on nixarchy.distrobox, nixarchy.microvm and
nixarchy.podman.

## Constraints

- No hardcoded colours; theme tokens only. Sizes must keep going through the
  theme's scale helpers, not become raw numbers.
- `devicePixelRatio` must stay out of layout maths — adding it would double-
  scale against the compositor.
- Input mapping must keep working: the existing transform is documented as
  mapping clicks through the same scale, and any replacement must preserve that.
- Keep-loaded behaviour is unchanged: `open()` still resets and focuses the
  final mode, and never touches the stream or log.
- Cannot be verified from a build alone; needs a look on a real display.

## Open questions

~~1. Which fix: derive `uiScale` from screen height, wrap the view in a
`Flickable` so it scrolls when clamped, or both?~~
~~2. If `uiScale` becomes derived, what is the reference?~~
~~4. What is the owner's actual resolution, per-monitor scale and theme
`base-size`?~~

**Answered by the owner, 2026-09-24:** *"it needs to follow the desktop scale
that is already set."*

So the direction is settled: the menu takes the scale the desktop already has,
rather than deriving a new one or applying a constant of its own. The owner did
not give a resolution or `base-size`, because the requirement does not depend on
one — it must be right at whatever scale is set, not tuned for one screen.

Left for the spec to work out, not to re-decide:

- Which value *is* "the desktop scale that is already set" in this context.
  Hyprland's per-monitor `scale` is already applied by the compositor to Qt's
  logical pixels, and the theme's font and spacing scale are already applied by
  the style helpers. If both are already in effect, the honest reading is that
  `uiScale` should go away rather than be replaced with a computed value.
- Whether removing the magnification alone is enough, or an outer `Flickable` is
  still needed so the surface scrolls if it is ever clamped.

3. Do the sibling plugins change in lockstep, in this PR's wake, or is this repo
   deliberately allowed to diverge first and prove the approach? **Still open.**
