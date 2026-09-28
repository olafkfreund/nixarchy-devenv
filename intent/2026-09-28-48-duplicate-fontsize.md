---
status: approved
issue: 48
author: olafkfreund
---

# Intent: the devenv widget compiles again, and a duplicate property can't ship

## Problem

Two icon buttons assign `fontSize` twice in the same QML object:

- `DevenvView.qml`, the Dismiss button: `fontSize: root.fontIcon` then
  `fontSize: root.fontGlyph`
- `EnvList.qml`, the row action button: the same pair

QML rejects a property set twice ("Property value set multiple times"). So
`EnvList` fails to compile, which makes `DevenvView` unavailable, which makes
the bar widget, the menu and the panel all fail to load. Both duplicates are
in the shipped `nixarchy-devenv-plugin-1.0.1` and on `main`. They look like
one edit that added a `fontGlyph` line after each existing `fontSize`.

The damage reaches beyond this plugin. On p620 (2026-09-28), the Bar Folder
plugin retried the failing load repeatedly. at-spi marked the Omarchy shell
unresponsive for about 26 s at a time, and every bar went blank within a
couple of minutes of each shell start. A hand edit that removed the
`fontIcon` line from both files stopped it: the bar has stayed stable since,
with 0 devenv errors.

Nothing in the test suite caught it. The flake checks validate
`manifest.json` and `qmldir`, and the JS tests exercise `Model.js`, but no
check compiles or lints the QML files.

## Proposed outcome

- The widget, the menu and the panel load on a real Omarchy shell with no
  "Property value set multiple times" or "Type … unavailable" errors.
- The buttons keep a glyph-sized icon (`root.fontGlyph`, the value that was
  meant to win).
- A flake check fails if any QML file in the plugin assigns the same
  property twice in one object, or otherwise fails to lint.

## Affected users and systems

- `DevenvView.qml`, `EnvList.qml`, `flake.nix` (a new check), and possibly a
  small checker script under `tests/`.
- Downstream: nixarchy's pin of this plugin, then `olafkfreund/nixos_config`.
  p620 is running a hand-fixed local copy
  (`~/.config/omarchy/plugins/nixarchy.devenv` is a real directory from
  09-24, which shadows the packaged plugin). Once a fixed release ships, that
  copy should be retired so the packaged plugin is used.

## Constraints

- There is no visual change beyond the widget working again: the icon size is
  the one the second assignment intended.
- The new check has to run in the Nix sandbox (no display, no running shell).

## Open questions

1. **How does the check work?** `qmllint` from Qt 6 (`qt6.qtdeclarative`),
   which catches this and other QML errors but adds a Qt dependency to the
   check and can be noisy about Quickshell/Omarchy imports it can't resolve.
   Or a small Python scan for any property set twice in one object, which is
   narrow, dependency-free and exact for this bug. I recommend the Python
   scan now, with `qmllint` as a follow-up if it can be made quiet.
2. **Should the local hand copy on p620 be retired** as part of this task,
   after nixarchy picks up the fix? Or stay a separate step?
