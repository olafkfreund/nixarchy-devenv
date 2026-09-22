---
status: approved
issue: 8
intent: intent/2026-09-22-8-remove-dead-code.md
---

# Spec: remove dead and duplicated code

## Design

One PR, grouped by file. Every change keeps behaviour: the same rows, actions,
messages, CLI output and exit codes. Where a change could alter output, this
spec says why it does not.

### `Model.js`

- **Delete `removeMessage`**: the removal chooser draws
  `tiersFor(env)[i].text`, and nothing else calls it. Its three assertions in
  `remove.test.js` go with it. The bound-revoke text is still asserted through
  `tiersFor`, which is what is drawn.
- **Replace `templateOrder` with `templateChoices(templates, filter)`**
  (decision 3). It flattens `templateGroups` in group order and keeps a
  template when `filter` is empty, or when `(id + " " + label + " " + group)`
  lower-cased contains `filter` lower-cased. That is the loop now inlined in
  `CreateForm.qml:46`, moved as is.
- **`findBy(list, field, value)`**, which returns the first match or `null`.
  `templateById`, `envByPath` and `tierById` become one-line calls, and their
  names and signatures stay, so no caller changes.
- **`rootArgs(roots)`** returns the flat `["--root", r, …]` array, or `null`
  when any root is not absolute. `listArgv` and `removeArgv` use it; the argv
  stays the same element for element, including returning `null` on a bad
  root.
- **`sanitize`**:
  `var out = str(value).replace(/[\x00-\x1f\x7f-\x9f]/g, "").trim()`, then the
  existing length cap. It strips the same characters as the loop and trims the
  same whitespace (`String.prototype.trim` is ES5, available in QML's V4).
  Existing tests pin it: control characters, overlong input, `\n`.
- **`detailText`**: `Array.prototype.slice.call(env.profiles || []).join(", ")`,
  the idiom `Model.js` already uses for Qt sequence wrappers.
- **`statusText`**: `.map` over `status.processes` instead of a push loop.

`rowRecord` keeps its explicit typing. A ListModel takes its role types from
the first row it is handed; the comment above it records that failure.

### QML

- **`CreateForm.qml:46`**:
  `readonly property var templateChoices: Model.templateChoices(root.templates, root.templateFilter)`.
- **`DevenvState.qml`**:
  - delete `skipped` (L90, L343) and `streamName` (L116, L239), and
    `startStream`'s `name` parameter with its callers' third arguments;
  - `function canMutate(argv)` holds the shared prefix of `run` and
    `startStream` (refuse while mutating, `null` argv, clear `lastError`);
  - `readonly property string pendingText` replaces the string built in both
    `busyText` and `statusJson`. `statusJson`'s `pending` value is
    byte-identical.
- **`DevenvView.qml`**:
  - delete `import Quickshell` (decision 2);
  - `readonly property var removeTierEntry` replaces the two
    `removeTiers[Math.min(…)]` expressions (L44, L761);
  - inline the one-field `lock` object at its single use;
  - delete the second `removeTyped = ""` in `closeRemove` (`askRemove` resets
    it before the chooser can show again).
- **`Panel.qml`**:
  - delete `import Quickshell` (decision 2);
  - drop `hideWhenEmpty` from the settings pushed into DevenvState (Panel reads
    its own), and the stale mention in DevenvState's comment;
  - pass `refreshIntervalSec` unclamped, because DevenvState clamps it.
- **`Menu.qml`**: delete the empty `onSwitchPanelRequested` handler and its
  comment. An unhandled signal is a no-op.
- **`EnvList.qml`**: inline `maxHeight` (`Style.space(520)`), and delete the
  `width: parent ? … : implicitWidth` fallback, because its only user sets
  `width`.

### `pkgs/cli.sh`

- **`allowed_file()`** becomes two expansions at its only call:
  `af=${DEVENV_HOME:+$DEVENV_HOME/allowed}; af=${af:-${XDG_DATA_HOME:-$HOME/.local/share}/devenv/allowed}`.
  That is the same precedence, and the same form `templates-check.nix` uses.
- **`splice_preset`'s fallback**:
  `sed -i "$((close - 1))r $file" devenv.nix` replaces head, cat, tail and mv.
  `r` appends the file after line `close - 1`, which is before the closing
  `}`: the same bytes. The placeholder path is untouched.
- **`cmd_new`** calls `expand_root "$parent"` instead of repeating the `~` and
  `~/*` cases.
- **The row builders**: a `row_base DIR` helper emits the fields both builders
  share (path, name, lockfile, dev) as a jq object, and each builder merges its
  own fields. The emitted JSON is the same: jq object key order follows
  insertion, and the CLI tests compare values by key, not bytes.
- **`remove`'s single-arm `case "$tier"`** becomes an `if`.

The removal safety checks are not touched.

### `pkgs/cli.nix`, `pkgs/templates-check.nix`, `flake.nix`

- `cli.nix`: drop `passthru.share`; `templateIds` stays, because the flake
  assertion uses it.
- `templates-check.nix`: capture `templates --json` once before the loop, and
  look up each id's kind from that.
- `flake.nix`: one pacman/yay grep over the sources (`*.qml`, `*.js`, `pkgs`,
  `data`) in the `repo` check, instead of one in the `plugin` check plus one in
  `repo`. The package's QML and JS are copies of the same files. The check for
  symlinks inside the package stays.

### Tests

- **`node:test`** (decision 1):
  - `tests/harness.js` keeps its loader and fixtures (`env`, `listRow`,
    `templates`, `eq`, `ok`, `HOME`, `Model`), and exports
    `test = require("node:test").test` in place of its own runner and
    `report()`;
  - `tests/run.js` is deleted;
  - the command becomes `node --test 'tests/model/*.test.js'` in `flake.nix`'s
    `model` check, AGENTS.md (the Layout table and Commands) and the README.
  - Node 24.20 (nixpkgs) supports the glob.
- **`tests/cli.sh`**:
  - `rm_cli` becomes a plain function over `with_devenv`, and the running and
    unknown cases pass `STUB_PROCESSES` through `env` instead of rebuilding
    `rm_cli` in a `declare -f` subshell;
  - drop the duplicate outer `DEVENV_HOME=` and `STUB_PROCESSES=` prefixes
    where the inner `env` already sets them;
  - `remove.test.js` uses `env` directly instead of the alias `e`.
- **New**: `templateChoices` gets Node tests. They cover group order, filter
  matching on id, label and group, case-insensitivity, and an empty filter
  returning everything. The same cases that pinned `templateOrder` carry over.

## Alternatives rejected

- **Flattening `rowRecord`.** Its typing guards a real ListModel failure.
- **Deleting the symlink check on the built package.** A check of what the
  build produces is the minimum a build deserves.
- **Deleting `templateOrder` without moving the QML loop.** That leaves logic
  in QML with no test, against AGENTS.md (decision 3).
- **Keeping the hand-rolled runner.** `node:test` ships with the Node the
  flake already uses (decision 1).
- **Several PRs.** The owner asked for one.

## Risks

- **A QML file stops loading** if `import Quickshell` supplied something
  implicitly. The live load on razer catches it: the log checked for errors,
  and both surfaces opened.
- **`sed r` differs from the head/tail splice** on a file whose last `}` is on
  line 1. A `devenv init` scaffold never is. The CLI tests exercise the splice
  through `init python` and `init android`; the fallback path gets its own
  test case, a stub scaffold without the placeholder line.
- **`node --test` output differs** from the harness's `N passed, M failed`
  summary. Anything that parsed that summary would break. Nothing does: the
  flake check uses the exit code.
- **jq key order** in `row_base` merges. The tests compare by key. The plugin
  parses JSON by key (`parseList`).
- **Hosts:** none. Plugin and CLI only.

## Verification

1. `node --test 'tests/model/*.test.js'` passes, with the new
   `templateChoices` tests. `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
   passes, with the new fallback-splice case.
2. `nix flake check`, and `nix flake check --all-systems --no-build`.
3. A fresh-clone `omarchy plugin validate`.
4. `git diff --stat main` shows a net reduction near the review's estimate of
   about 130 lines.
5. **Live on razer** (AGENTS.md procedure, restoring the Home-Manager-linked
   plugin afterwards):
   - install the branch build;
   - check `qs log` for errors from `nixarchy.devenv`;
   - open the menu and the bar popup;
   - open the create form, and filter templates by typing, which exercises
     `templateChoices`;
   - open the removal chooser on a local demo row (four tiers) and on a bound
     row (revoke only);
   - restore.
