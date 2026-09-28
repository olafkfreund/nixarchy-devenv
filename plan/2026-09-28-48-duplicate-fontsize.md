---
status: draft
issue: 48
spec: spec/2026-09-28-48-duplicate-fontsize.md
---

# Plan: the devenv widget compiles again, and a duplicate property can't ship

Branch `fix/48-duplicate-fontsize`, in a worktree of
`/mnt/data/Source-home/nixarchy-devenv`. The local checkout is not touched.

## Approved decisions

These are carried over from the spec.

**D1. Remove exactly two lines.** Each is a `fontSize: root.fontIcon`
directly followed by `fontSize: root.fontGlyph` in the same object:

- `DevenvView.qml:587` (the Dismiss button)
- `EnvList.qml:234` (the row action button)

The other `fontSize: root.fontIcon` lines (`DevenvView.qml:377`, `386`,
`405`) are single assignments and stay.

**D2. `tests/qml-duplicate-props.py`,** dependency-free:

- For each `.qml` file argument, it tracks brace depth, and per object block
  the names assigned by a line starting `name:` or `a.b:`.
- It skips lines starting `property`, `signal`, `function`, `readonly`,
  `required` or `//`, and assignments whose value opens an object
  (`name: Type {`).
- It prints `file:line: 'name' already set at line N` for each repeat and
  exits 1 if there are any.

**D3. Wire it into the `plugin` check** (`flake.nix:154-155`). Add
`pkgs.python3` to `nativeBuildInputs` next to `pkgs.jq`, and add a
commented line next to the existing QML rules:

```nix
# A property set twice in one object makes QML refuse the whole file, and
# the bar widget, menu and panel all fail to load (#48).
python3 ${./tests/qml-duplicate-props.py} ${plugin}/*.qml
```

**D4. Retiring p620's hand copy is a separate step** after nixarchy ships
the fix. It is not part of this plan.

## Steps

1. **`tests/qml-duplicate-props.py`** (D2) and **`flake.nix`** (D3).
   → verify: `nix build .#checks.x86_64-linux.plugin` **fails**, naming
   `DevenvView.qml` and `EnvList.qml` with their `fontSize` lines.
2. **Scanner sanity** → verify: two throwaway files. One sets `width:` twice
   in one block and must fail. One sets `width:` in two sibling blocks and
   must pass.
3. **`DevenvView.qml`, `EnvList.qml`** (D1).
   → verify: the step-1 check passes, `nix flake check` passes, and
   `git diff` shows exactly two lines removed.
4. **Packaged equals the hand fix** → verify: the built plugin's two files
   are byte-identical to p620's hand-fixed copies in
   `~/.config/omarchy/plugins/nixarchy.devenv/`.
5. **Commit** as `fix: set fontSize once in DevenvView and EnvList, and
   check for duplicate QML properties (#48)`, push, and open a PR linking the
   intent, spec and plan.
6. **Merge** on green CI (squash, pinned to the head commit).

## Tests

| # | Command | Expected |
| --- | --- | --- |
| T1 | step 1 check, before the QML fix | fails, naming both files |
| T2 | step 2 throwaway files | the duplicate fails, the siblings pass |
| T3 | step 3 check and `nix flake check` | pass |
| T4 | step 4 `cmp` against p620's copies | identical |

## Rollback

- **Before merge:** close the PR.
- **After merge:** `git revert` the step-5 commit. p620 is unaffected, since
  it runs its hand copy until D4.
