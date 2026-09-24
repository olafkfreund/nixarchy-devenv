---
status: approved
issue: 37
author: olafkfreund
---

# Intent: the menu reads larger by climbing the theme's ladder, not by a factor

Closes #37.

## Problem

This is a regression introduced by #12, in `main` now.

The full-screen menu used to multiply its whole view by a hardcoded `1.45`,
applied as a QML `scale:` transform. That was wrong for two reasons: it
magnified figures the theme had already scaled, so raising the desktop's text
size compounded rather than tracked; and a transform magnifies the view *after*
layout, so wrapping and eliding are computed at one size and stretched to
another. Content below the list was clipped with no way to reach it.

#12 deleted the multiplier and wrapped the view in a `Flickable`. That fixed
the clipping. But the multiplier was there for a stated reason — a full-screen
surface is read from further away than a bar popup — and #12 removed the
mechanism without replacing the intent. The menu now renders at exactly
bar-popup text size. The clipping is gone; so is the deliberate difference
between the two surfaces.

The sibling plugin `nixarchy.distrobox` hit the same defect and solved it
completely. Its view carries a `large` flag that moves each named text role up
a rung of the shell's own ladder — `title` where the popup uses `caption`,
`heading` where it uses `body`, and so on — and the menu passes `large: true`.
Every rung derives from the theme's `[font] base-size`, so the menu moves *in
step with* the desktop instead of sitting a fixed percentage above it, and a
theme that pins a font token is honoured rather than overridden.

It also carries a `no-text-multiplier` check in `nix flake check` that fails on
either a `scale:` transform or a flat multiplier, so the defect cannot return.
This repo has no equivalent, which is why #12's regression was possible at all.

## Proposed outcome

- The full-screen menu reads larger than the bar popup again, and the
  difference comes from picking larger tokens rather than from any factor.
- Raising or lowering the desktop's text size moves both surfaces together.
- A theme that pins a specific font token is honoured on both.
- Reintroducing a `scale:` transform or a flat multiplier fails
  `nix flake check` rather than shipping.

## Affected users and systems

Anyone using the full-screen menu. `DevenvView.qml` owns the roles and must
pass them to the four drawing components it already hands `foreground` and
`fontFamily` to — `EnvList.qml`, `CreateForm.qml`, `LogView.qml`,
`ShortcutSheet.qml`. `Menu.qml` sets the flag; `Panel.qml` keeps the base
rungs. `flake.nix` gains the check. There are 46 direct `Style.font.*` uses
across those five files today, so this is not a one-line change.

No CLI, no packaging, no behaviour outside drawing.

## Constraints

- Nothing multiplies. The difference between the surfaces is which rung of the
  shell's ladder each sits on, and nothing else.
- No hardcoded sizes and no hardcoded colours; tokens only.
- `devicePixelRatio` stays out of layout — the compositor already applies the
  monitor's scale to these logical pixels.
- The bar popup's appearance must not change at all.
- Keep-loaded behaviour is unchanged: `open()` still resets and focuses the
  final mode, and never touches the stream or the log.
- Cannot be proven by a build. Needs a real display, at more than one theme
  font size.

## Open questions

1. Which roles need a rung, and how many? Distrobox lifts five (`row`, `label`,
   `icon`, `glyph`, `hero`). This view's usage is mostly `caption` (11 sites),
   with `body`, `iconSmall` and `display` — so the mapping may not be identical
   and should be derived from what this view actually draws, not copied.
2. Should the roles be named properties on `DevenvView` passed down explicitly,
   as `foreground` and `fontFamily` already are, or should the children read a
   single `large` flag and map it themselves? The first keeps the ladder in one
   place; the second is less wiring.
3. Port distrobox's `no-text-multiplier` check verbatim, or write one that also
   catches the `/ uiScale`-style divisions that accompanied the old transform?
4. #12 is still unverified on a display. Should that verification and this
   change be done in one sitting, since both are judged by eye and this one
   changes what that check would be looking at?
