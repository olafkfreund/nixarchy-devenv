---
status: approved
issue: 4
author: olafkfreund
---

# Intent: List environments bound with `devenv --from`

## Problem

Since devenv 2.2 a directory can be bound to an out-of-tree configuration with
`devenv --from <source> allow`. That directory has a working environment
(`cd` activates it, `devenv shell` and `devenv up` work in it) but **no local
`devenv.nix`**.

The plugin cannot see it. `nixarchy-devenv list` finds candidates from two
sources, the roots' `find` hits and devenv's `allowed` file, and keeps an entry
only when `<path>/devenv.nix` exists (`pkgs/cli.sh:339`). A bound directory
fails that check, so it is missing from the bar popup and the menu. The user
cannot start its processes, stop them, update its lock or revoke it from the
desktop, and nothing tells them why it is missing.

What devenv v2.3.1 does (read from its source, not from docs):

- The binding lives in the file the CLI already reads, `<devenv home>/allowed`,
  as a JSON line: `{"path":"/abs/dir","from":"<source>","profiles":[...]}`
  (`devenv/src/commands/hook.rs`, `TrustEntry`). There is no other record.
- A binding exists only through `allow`, so every bound directory is in that file.
- devenv treats the bound directory as the project root
  (`devenv/src/main.rs`, `trusted_from`), so its `.devenv/` state and
  `devenv.lock` live there even though `devenv.nix` does not.
- `devenv revoke` in the directory removes the entry, together with its
  source and saved profiles.

## Proposed outcome

- A bound directory that still exists appears in the list on both surfaces,
  marked as bound and showing where its configuration comes from (`from`) and
  any saved profiles.
- Enter, start/stop processes, update, and revoke work on it as on any other row.
- Actions that assume a local `devenv.nix` are not offered: edit `devenv.nix`,
  and "Remove devenv files". The CLI still refuses them if called directly.
- Revoking a bound row says plainly that it also forgets the source and the
  saved profiles, because devenv stores them in the same entry.
- The manual (`docs/usage.md`) and the README describe bound rows. Neither
  mentions `--from` today, although the issue expected the manual to.

## Affected users and systems

- Anyone using `devenv --from`. Users without bindings see no change.
- `pkgs/cli.sh` (`list`), `Model.js` (rows and which actions are offered), the
  list drawing in `EnvList.qml`, `tests/cli.sh` and its stubs,
  `tests/model/`, `docs/usage.md` and the README.
- Not affected: the catalogue, create, `templates-check`, and nixarchy.

## Constraints

- **Consent stays with the user.** Listing only reads `allowed`. The plugin
  never writes a binding, never runs `allow` over one, and never re-runs
  `allow` in a way that would reset its profiles.
- **Removal stays tiered and bounded where it executes.** A bound directory
  gets no deletion tier in this task. The CLI's existing refusal ("has no
  devenv.nix of its own") keeps working and gets a filesystem test. Its
  `.devenv/state` is never touched.
- **No guessing.** The template of a bound row is not local, so it is shown as
  "custom", or as the source string, never inferred. Process state follows the
  existing rules (`unknown` unless a real process row is parsed).
- **Directories that no longer exist stay hidden**, and are never removed from
  devenv's database, as with local rows.
- **The plugin never evaluates Nix to draw.** The `from` source is displayed as
  text. It is not fetched or resolved.
- `allowed` is devenv's internal file, not a published interface. The format
  assumption is pinned in a comment citing devenv's source and version, like
  the option names in `data/templates.nix`. Lines the CLI cannot parse
  continue to be counted as skipped, not guessed at.

## Decisions

Answered by the owner on 2026-09-21:

1. **Bound rows are listed wherever they are**, not only under a configured
   project root. Local rows found through `allowed` are not limited to
   roots either, so a binding is never invisible.
2. **Update is offered on bound rows** as on local ones. The lock lives in the
   bound directory; the inputs come from the source's `devenv.yaml`.
3. **A bound directory with its own `devenv.nix` is an ordinary local row.**
   devenv uses the local project and ignores the binding
   (`find_project_root` wins), so the row shows what devenv will actually do.

## Open questions

None.
