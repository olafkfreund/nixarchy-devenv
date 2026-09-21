---
status: draft
issue: 4
intent: intent/2026-09-21-4-bound-environments.md
---

# Spec: List environments bound with `devenv --from`

## Design

A bound directory gets its own row. Its data comes from the JSON line devenv
already writes to `allowed`. The existing actions reach it through the
directory's path, as they do for every row. Nothing new runs; the change is
what `list` keeps and what the row offers.

### devenv's behaviour this relies on (v2.3.1)

- `allowed` lines are JSONL: `{"path", "from"?, "profiles"?}` (`TrustEntry`,
  `devenv/src/commands/hook.rs`). A line with a string `from` is a binding.
- devenv resolves a directory's project by walking **up** from it: the nearest
  ancestor-or-self with a `devenv.nix` (`.exists()`, so a symlink counts) wins
  (`find_project_root`, `devenv-core/src/paths.rs`). Only when there is none
  does it look for a binding (`main.rs`, `trusted_from`). So a binding is
  shadowed by a `devenv.nix` in the directory **or in any ancestor**. This
  extends decision 3 of the intent from "the directory" to "the directory or
  any ancestor", because that is what devenv does.
- The bound directory is the project root: `.devenv/` and `devenv.lock` live
  in it.
- `devenv revoke` in the directory removes the whole entry: binding, source
  and profiles.

### `pkgs/cli.sh`: `list`

1. The existing jq pass over `allowed` stays as it is. It still produces
   `allowed.raw`, the local candidates and the `skipped` count, so skip
   counting does not change.
2. A second jq pass emits one compact object per binding:
   `fromjson? | select(.path startswith "/" and (.from | type) == "string")
   | {path, from, profiles: ((.profiles // []) | map(strings))}`, into
   `$tmp/bound`.
3. For each binding, the CLI emits a row only when all of these hold:
   - the directory exists (`realpath -e`);
   - it has not already been emitted as a row: `seen[]` is shared with the
     local loop, and local rows go first;
   - no ancestor-or-self of the canonical path has a `devenv.nix`, checked
     with `-e`, which matches devenv's `.exists()`.

   Otherwise the CLI skips the binding silently. It never touches the file.
4. A bound row carries the same fields as a local one, plus two more:

   | field | bound value |
   | --- | --- |
   | `allowed` | `true` (a binding is an allow entry) |
   | `lockfile` | `devenv.lock` present in the directory |
   | `template` | `custom` (the configuration is not local) |
   | `hasProcesses` | `true`: we cannot read the source without evaluating it, so Start is **offered**, not claimed. `devenv up` reports it if there are none. |
   | `dev`, `mtime` | `stat` of the directory itself (there is no `devenv.nix` to stat) |
   | `from` | the source string, as devenv stored it |
   | `profiles` | the saved profiles, possibly `[]` |

   Local rows get `from: ""` and `profiles: []`, so every row has the same
   shape.
5. A comment above the new pass cites `TrustEntry`, `find_project_root` and
   `trusted_from` at devenv v2.3.1, in the style of the option-name header in
   `data/templates.nix`.

`remove` is unchanged. Its check `[ -f "$dir/devenv.nix" ] && [ ! -L … ]`
already refuses every deleting tier on a bound directory ("has no devenv.nix
of its own").

### `Model.js`

- **`parseList`** reads `from` with `sanitize(…, 200)`. It keeps `profiles`
  as an array of sanitized strings matching `^[A-Za-z0-9._-]+$`, and drops
  anything else. Rows from an older CLI get `from: ""` and `profiles: []`.
- **`rowsFor` / `ROW_FIELDS`** add `bound` (a boolean, `from !== ""`) and a
  `detail` string. For a bound row, `detail` is `from <source>`, plus
  ` · profiles a, b` when there are profiles. For a local row it is the
  template, as today. `EnvList.qml` shows `detail` where it now shows
  `template`, so the list's drawing does not branch.
- **`filterEnvs`** also matches on `from`, so typing part of a flake reference
  finds its row.
- **`actionsFor`** leaves `edit` out for a bound row. Enter, start/stop,
  update and revoke are unchanged (decision 2). Allow never appears, because
  a bound row is always allowed. `allowsVerb(row, "edit")` is therefore false,
  so the `e` key does nothing, through the existing `dispatch` path.
- **`tiersFor(env)`** returns `[revoke]` for a bound environment and `TIERS`
  otherwise. `DevenvView.qml` uses it in its three `Model.TIERS` sites: the
  Repeater, `moveTier` and the footer text.
- **`removeRefusal`** refuses any tier except revoke on a bound environment:
  "Bound to <source>: nothing here to remove; revoke forgets the binding".
  This covers a dialog opened some other way, and the CLI refuses as well.
- **`removeMessage`** for revoke on a bound environment says what else goes:
  "Revoke: <path>\nForgets that it is bound to <source>, and its saved
  profiles. Nothing is deleted. It leaves this list, because without the
  binding devenv no longer sees an environment here."
- The shortcut sheet's `e` line becomes "Edit its devenv.nix in your editor
  (not for bound environments)".

### QML

- `EnvList.qml`: `row.template` becomes `row.detail` in the caption.
- `DevenvView.qml`: `Model.TIERS` becomes `Model.tiersFor(root.removeEnv)`,
  and `removeTierId` reads from the same list.
- `DevenvState.qml`: no change. `edit`, `remove` and the other actions
  already go through `Model`.

### Docs

`docs/usage.md` gets a short "Bound environments" section. It covers:

- what a bound row shows, and why its template reads `custom`;
- that editing and deleting are not offered;
- that revoke also drops the source and the profiles, and the row then leaves
  the list;
- that a `devenv.nix` in the directory or above it takes precedence, as it
  does in devenv.

The README's list of what the plugin lists gains one line.

## Alternatives rejected

- **Evaluating the source** to fill `hasProcesses` or the template. The
  plugin never evaluates Nix to draw, and a remote source needs the network.
- **`hasProcesses: false` for bound rows.** This hides Start and Stop, which
  the intent requires, for environments whose whole point may be services.
- **A deletion tier for bound directories** (for example `.devenv/` without
  `state`). The intent keeps deletion out of this task. The existing tiers
  are built around a local `devenv.nix`, and the CLI's refusal stays the
  bound.
- **Parsing the legacy plain-path lines** as well. They cannot carry `from`,
  so they can never be bindings. How they are counted is unchanged.
- **Limiting bound rows to the project roots.** Rejected by decision 1.
- **A new `status`/`kind` field instead of `from`.** `from` is what devenv
  stores, and `bound` derives from it in one place (`Model.js`).

## Risks

- **devenv changes `allowed`.** It is an internal file. Mitigations: fields
  are read defensively (`fromjson?`, type checks), the version is cited, and
  `templates-check` does not depend on it. The worst case is that bound rows
  silently stop appearing, which is today's behaviour, not a wrong action.
- **The ancestor walk is slow on a deep path.** At most one `-e` test per
  path component per binding, and bindings are few. This is negligible next
  to `find`.
- **Start is offered on a bound environment with no processes.** `devenv up
  -d` fails and its message reaches the log, the same path as any failed up.
  It is labelled, not hidden.
- **A path with a newline in `allowed`.** The existing pass already reads
  line by line. The new pass emits compact JSON, one object per line, and
  reads fields with jq, so a newline inside a string stays escaped.
- **All hosts:** the CLI and the plugin only. There is no NixOS module
  change, and nothing host-specific.

## Verification

- `tests/cli.sh` adds these fixtures to the existing `allowed` file:
  - a bound directory with a `devenv.lock` and profiles: listed, with
    `allowed`, `template == "custom"`, `hasProcesses`, `from`, `profiles`
    and `lockfile`;
  - a bound directory **outside** the roots: listed (decision 1);
  - a bound directory that also has its own `devenv.nix`: one row, with
    `from == ""` (decision 3);
  - a bound directory **below** a local project: not listed (the ancestor
    rule);
  - a bound entry whose directory is gone: not listed;
  - a `from` of the wrong type (`42`): not a binding, and not counted as
    skipped, because its `path` is valid;
  - the allow file's checksum is unchanged afterwards (the existing
    assertion).
- `tests/cli.sh` removal: `remove --tier files|state|folder` on a bound
  directory with `.devenv/state/db/x` exits 2, and nothing is deleted.
- `tests/model/`: `parseList` with `from`/`profiles`, including hostile
  values (control characters, an overlong source, profile names with `/` or
  spaces, a non-array); `rowsFor` `detail`/`bound`; `actionsFor` without
  `edit` for a bound row; `tiersFor`; `removeRefusal` for every non-revoke
  tier; `removeMessage` naming the source; `filterEnvs` on `from`.
- `node tests/run.js`, `bash tests/cli.sh …`, and `nix flake check` pass;
  `nix flake check --all-systems --no-build` evaluates.
- **Live, on a nixarchy desktop,** per AGENTS.md "Verifying live":
  1. In a `mktemp -d` directory, run
     `devenv --from path:<a throwaway devenv project> allow`.
  2. Check that the row appears on both surfaces with its source.
  3. Check that `e` does nothing, and that `x` offers revoke only.
  4. Revoke from the plugin.
  5. Check that the row leaves and the throwaway line is gone from `allowed`.
