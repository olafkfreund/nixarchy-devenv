---
status: draft
issue: 48
intent: intent/2026-09-28-48-duplicate-fontsize.md
---

# Spec: the devenv widget compiles again, and a duplicate property can't ship

The intent was approved on 2026-09-28:

| # | Question | Decision |
| --- | --- | --- |
| 1 | How the check works | A small Python scan (recommended) |
| 2 | Retire p620's hand copy here | No. A separate step after the release |

On decision 2: retiring the copy needs this fix released and picked up by
nixarchy first. Until then, the hand-fixed copy is what keeps p620's bar
working.

## Design

### 1. Remove the duplicate assignments

- `DevenvView.qml`, the Dismiss button: delete `fontSize: root.fontIcon` and
  keep `fontSize: root.fontGlyph`.
- `EnvList.qml`, the row action button: the same.

`fontGlyph` was the second assignment, so it's the one the author meant to
win, and it matches what p620 has run since its hand fix.

### 2. `tests/qml-duplicate-props.py`, run from the `plugin` check

A dependency-free scanner. For each `.qml` file given, it tracks brace depth
and, within each object block, the property names assigned
(`name: value` / `a.b: value` at the start of a line). It ignores
`property`, `signal`, `function`, `readonly` and `required` declarations,
and nested-object openers (`name: Type {`). It reports every name assigned
twice in one block as `file:line: 'name' already set at line N`, and exits 1
if any were found.

The `plugin` check in `flake.nix` gains `pkgs.python3` in
`nativeBuildInputs` and one line next to the existing grep rules:

```nix
python3 ${./tests/qml-duplicate-props.py} ${plugin}/*.qml
```

It follows the pattern of the existing rules (hardcoded colours,
`textScale`/`uiScale`): a cheap static rule over the packaged QML, with a
comment saying why it exists.

## Alternatives rejected

- **`qmllint`:** a Qt 6 dependency in the check, and without Quickshell's and
  Omarchy's type information it floods with unresolved-import warnings,
  which would have to be suppressed file by file. It could be a follow-up if
  it can be made quiet.
- **Loading the plugin in a headless Quickshell:** it needs Wayland and the
  Omarchy shell tree in the sandbox, which is heavy for a check whose target
  bug is textual.
- **A plain `grep` for two adjacent `fontSize:` lines:** it catches only this
  exact pair. The next duplicate would be a different property, or
  non-adjacent.

## Risks

- **False positives on valid QML** (all files): the scanner skips
  declarations and object openers. Verification runs it over every file on
  `main` after the fix, and it must report nothing.
- **False negatives for unusual layouts** (all files): it's line-based, so
  two assignments on one line aren't caught. That's acceptable. The goal is
  to stop the realistic regression. `qmllint` stays the follow-up for the
  rest.

## Verification

1. **Red first:** add the scanner and the check line only, then run
   `nix build .#checks.x86_64-linux.plugin`. It must **fail**, naming
   `DevenvView.qml` and `EnvList.qml` with their `fontSize` lines.
2. **Green:** remove the two lines, and the same check passes.
   `nix flake check` passes overall.
3. **Scanner sanity:** running it over every `.qml` in the repo reports
   nothing. It also flags a throwaway file that sets `width:` twice in one
   block, and passes one that sets `width:` in two sibling blocks.
4. **Real shell:** the packaged plugin's `DevenvView.qml` and `EnvList.qml`
   are identical to p620's hand-fixed copy, so the runtime behaviour is
   already proven. Since the hand fix at 10:54 the bar has stayed full, with
   0 devenv errors.
