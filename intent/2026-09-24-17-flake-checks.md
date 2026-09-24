---
status: approved
issue: 17
author: olafkfreund
---

# Intent: the flake checks enforce the rules they claim to enforce

Closes #17, #18, #19.

## Problem

`nix flake check` is the stated enforcement for several AGENTS.md rules. For
three of them the check is narrower than the rule, so the repository can
violate a documented invariant and still report "all checks passed". Found in a
cross-model review and confirmed by reading the check bodies.

**The Arch package manager rule (#17).** AGENTS.md says `pacman` and `yay` must
not appear anywhere in the repository, not even in comments, because nixarchy
fails the rebuild on them. The check greps only the root-level QML and
JavaScript files plus two directories. The Lua keybinding file, the docs, the
shared menu entry, the tests, the README and AGENTS.md itself are never
scanned. A reference in any of them passes. This narrowing was deliberate and
is recorded in the #8 spec, so the defect is the mismatch between the rule and
the enforcement, not a regression.

**The package contents rule (#18).** AGENTS.md says a new runtime file must be
added to the `files` list in the flake or it is not in the package. Nothing
verifies this. The plugin check tests that the two entry points exist and
nothing else, and that test is existence-only — it never parses the QML, so a
file with a syntax error passes too. A component imported by the view but
missing from the list passes every check and fails only when the shell loads
the plugin. The list happens to be correct today; this is about drift.

**The Home Manager module (#19).** `nix flake check` emits "unknown flake
output 'homeManagerModules'" and therefore never evaluates that output on any
system. It is the name nixarchy consumes. Hand-evaluation against a stub shows
it is correct today, but a future edit that breaks it ships silently.

## Proposed outcome

- Either each check covers what its rule claims, or the rule is reworded to
  describe what is actually enforced. No rule is left with an enforcement that
  looks stronger than it is.
- A runtime file that is imported but not packaged fails `nix flake check`
  rather than failing at plugin load.
- `homeManagerModules.default` is evaluated by `nix flake check` like every
  other output.

## Affected users and systems

Maintainers and any agent working in this repository — these checks are the
guard rail that catches rule violations before review. Touches `flake.nix`, and
`AGENTS.md` if any rule is reworded instead of enforced. No runtime behaviour
changes for users.

## Constraints

- `nix flake check` must stay runnable without network access; the impure
  template check stays separate.
- Must keep evaluating on aarch64 under `--all-systems --no-build`.
- No new import-from-derivation.
- No symlinks introduced anywhere, since plugin validation refuses them.
- Checks should stay fast enough that they are actually run locally.

## Open questions

1. For the Arch rule: widen the grep to the whole source minus `.git` and
   `result`, or narrow the AGENTS.md wording to the files that matter? Widening
   means the rule text in AGENTS.md itself becomes a match, which needs
   handling.
2. For the `files` list: is a reference check (resolve each local component and
   import in the packaged QML) enough, or is a real QML syntax check wanted?
   The latter needs a QML parser in the check's build inputs.
3. For the Home Manager module: evaluate it against a minimal stub module set
   inside a check, or accept that it is untestable in a flake check and cover it
   from nixarchy's side instead?
4. Should these three land as one PR or separately? They share a file but are
   otherwise unrelated.
