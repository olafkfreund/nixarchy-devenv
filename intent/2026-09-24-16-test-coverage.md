---
status: draft
issue: 16
author: olafkfreund
---

# Intent: the refusals and branches the rules require are actually tested

Closes #16, #24.

## Problem

The suite is in good shape: seventy Node tests and sixty-three CLI tests pass,
every top-level function in `Model.js` is exercised, and the stub harness was
probed and cannot reach a real `devenv` or `nix` under any constructible path.
The gaps are specific and worth closing rather than rewriting anything.

**Four refusals have no filesystem test (#16).** AGENTS.md states plainly that
every refusal has one. Four in the removal command do not: `devenv.nix` being a
symlink rather than absent, the target containing the home directory, the
target not existing, and the target being the root directory. All four were
probed by hand and behave correctly — they are simply unguarded against
regression, which is exactly what the rule exists to prevent on the most
destructive command in the tool.

**A set of CLI branches is untested (#24).** The dispatch surface — no
arguments, explicit help, unknown command, unknown option on each subcommand —
is uncovered boilerplate. More interesting: the personal-template path where a
`devenv.yaml` already exists, a personal template whose JSON is valid but
carries the wrong version, the generator path when `nix` is missing, and the
removal branch where `.devenv` is a symlink rather than a directory. None of
these touch the removal-safety checks, which are covered.

One of them cannot be tested as things stand: the stub `devenv` succeeds
unconditionally on `revoke`, so the "revoke failed, continuing" path in removal
has no way to be exercised without a hook in the stub.

## Proposed outcome

- The AGENTS.md rule that every refusal has a filesystem test is true again.
- The removal command's uncovered branches — especially `.devenv` as a symlink
  — are exercised, so a future refactor cannot quietly change them.
- The stub gains whatever minimal hook is needed to make failure paths
  testable, without letting tests reach the real `devenv` or `nix`.
- The remaining dispatch and usage-error branches are covered or explicitly
  written off as boilerplate, rather than left ambiguous.

## Affected users and systems

Maintainers and agents; no runtime behaviour change. Touches `tests/cli.sh`,
`tests/stub/devenv`, and possibly `tests/model/` if a pre-check needs a
matching Node test.

## Constraints

- Tests must never reach the real `devenv` or `nix`. The stub PATH construction
  is the guarantee and must not be loosened to make a failure path testable.
- Removal tests point only at throwaway directories under a temporary root,
  never at a real project.
- New stub behaviour must be opt-in through an environment variable so the
  default stub stays honest about the success path.
- Tests stay runnable under `nix flake check` without network.

## Open questions

1. What shape should the stub failure hook take — one variable per failing
   subcommand, or a single variable naming the subcommand that should fail?
2. Are the dispatch and usage-error branches worth testing at all, or should
   they be written off in AGENTS.md as boilerplate outside the rule? Testing
   them is cheap but adds noise.
3. Should the four missing refusal tests land first, on their own, given they
   are the ones a documented rule already requires?
