---
status: draft
issue: 13
author: olafkfreund
---

# Intent: consent is enforced, and a name cannot lie about itself

Closes #13, #15.

## Problem

Two defects sit on the same trust boundary: what the user consents to, and
whether what they see is what they get. Both were found in a cross-model
review.

**A declared capability is never enforced (#13).** The template catalogue lets
a generator entry declare which form toggles it honours. `honours_allow` is
read from the catalogue, built into the package index, and parsed into the
template model — and then never consulted by anything. Its sibling
`honoursGit` is checked in three places and correctly locks the form toggle.
This is latent today because the only generator sets it true. The day a
generator sets it false, a user ticking "Allow automatic activation" still
causes `devenv allow` to run, silently contradicting the catalogue's own
declaration and the AGENTS.md rule that consent stays with the user.

**A name can render as something it is not (#15).** Names typed into the create
form are validated against a strict whitelist and are safe. Names of
*discovered* environments are not: the sanitiser strips only the C0 and C1
control ranges, so Unicode bidi overrides survive. Nothing enforces the name
charset on directories that already exist on disk. That unfiltered name is then
what the user must type to confirm the irreversible folder deletion — so the
plugin's last safeguard compares what the user sees against a string that can
be made to display differently from its actual content.

## Proposed outcome

- A generator that declares it does not honour a toggle has that respected: the
  toggle is not silently sent anyway, and the form reflects the fact, the way it
  already does for git.
- Or, if the capability is not wanted, the field and its plumbing are gone
  rather than left half-wired.
- An environment name shown in a row and used in a destructive confirmation
  cannot contain characters that make it render differently from what it is.
- Both are covered by Node tests, including the discovered-environment path
  specifically.

## Affected users and systems

Anyone creating a project from a generator template, and anyone using the
"remove folder" tier on an environment discovered from disk rather than created
through the form. Touches `Model.js`, `pkgs/cli.sh`, `pkgs/cli.nix` and the
create form; `data/templates.nix` only if the capability is dropped.

## Constraints

- Consent rule from AGENTS.md: `devenv allow` runs only from the create form's
  toggle or the explicit allow action; never as a side effect, never re-run over
  an existing allow.
- Form fields stay allowlisted; any behaviour change needs a hostile-input test
  row.
- Name handling must not break legitimate non-ASCII project names. Stripping
  bidi controls must not become "ASCII only".
- Logic goes in `Model.js` with a Node test.

## Open questions

1. `honours_allow`: wire it up mirroring `honoursGit`, or delete the field and
   its `cli.nix` / `cli.sh` plumbing? Wiring it up is more code for a capability
   nothing currently uses; deleting it removes a documented catalogue feature.
2. For bidi characters in a discovered name: strip them, replace them with a
   visible placeholder, or refuse to offer the folder tier on such a row? Strip
   is simplest; a visible placeholder tells the user something was off.
3. Should the `list` command reject such directory names at the source instead,
   so the plugin never sees them? That moves the fix into the CLI and out of
   `Model.js`.
