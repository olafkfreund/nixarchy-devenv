---
status: draft
issue: 8
spec: spec/2026-09-22-8-remove-dead-code.md
---

# Plan: remove dead and duplicated code

Branch `fix/8-remove-dead-code`. **One PR** (the owner's request), one commit
per step, citing the step: `refactor(model): … (#8, step 2)`.

## Approved decisions (self-contained)

- **No behaviour change.** The same rows, actions, messages, CLI output, exit
  codes and argv arrays. Anything that would change them is out of scope.
- **Kept on purpose:**
  - `rowRecord`'s explicit typing, because a ListModel takes role types from
    its first row;
  - the check for symlinks inside the built package;
  - every removal safety check in `cli.sh`.
- **The test runner becomes `node:test`.** `harness.js` keeps its loader and
  fixtures and exports `test` from `node:test`. `run.js` is deleted. The
  command is `node --test 'tests/model/*.test.js'` (Node 24.20 in nixpkgs).
- **`import Quickshell` is removed** from `DevenvView.qml` and `Panel.qml`,
  proven by a live load on razer.
- **`templateOrder` is replaced by a Node-tested
  `Model.templateChoices(templates, filter)`.** It is `CreateForm.qml`'s
  inlined loop, moved as is: flatten `templateGroups` in order, and keep a
  template if the filter is empty or
  `(id + " " + label + " " + group).toLowerCase()` contains
  `filter.toLowerCase()`.
- **Helpers keep the public names.** `findBy`, `rootArgs`, `canMutate` and
  `pendingText` sit behind the existing functions, so no caller changes.

## Steps

1. **Tests to `node:test` first,** so every later step runs under the new
   runner.
   - `tests/harness.js`: delete `passed`, `failures`, `test` and `report`, and
     export `test: require("node:test").test`, keeping `eq`, `ok`, `env`,
     `listRow`, `templates`, `HOME` and `Model`;
   - delete `tests/run.js`;
   - `flake.nix` `model` check: `node --test 'tests/model/*.test.js'`;
   - AGENTS.md (the Layout row and Commands) and the README: the new command.

   → verify by `node --test 'tests/model/*.test.js'` passing the same number of
   tests as `node tests/run.js` did before (69), and by `nix build
   .#checks.x86_64-linux.model`.

2. **`Model.js`:**
   - delete `removeMessage`, and its assertions in `remove.test.js`;
   - add `templateChoices(templates, filter)` and delete `templateOrder`. Its
     test in `parsing.test.js` becomes `templateChoices` tests: group order,
     an empty filter, matches on id, label and group, case-insensitivity, and
     no match;
   - add `findBy(list, field, value)`. `templateById`, `envByPath` and
     `tierById` call it;
   - add `rootArgs(roots)`, returning an array or `null`. `listArgv` and
     `removeArgv` use it;
   - `sanitize`: `str(value).replace(/[\x00-\x1f\x7f-\x9f]/g, "").trim()`,
     then the existing cap;
   - `detailText`: `Array.prototype.slice.call(env.profiles || []).join(", ")`;
   - `statusText`: `.map`;
   - `remove.test.js`: `env` instead of the `e` alias.

   → verify by `node --test` passing, and by `commands.test.js`, which pins the
   argv arrays, passing unchanged.

3. **QML:**
   - `CreateForm.qml`: `templateChoices: Model.templateChoices(root.templates, root.templateFilter)`;
   - `DevenvState.qml`:
     - delete `skipped` and `streamName`, `startStream`'s `name` parameter, and
       the third argument at its callers;
     - add `canMutate(argv)`, used by `run` and `startStream`;
     - add `pendingText`, used by `busyText` and `statusJson`;
   - `DevenvView.qml`:
     - delete `import Quickshell`;
     - add `removeTierEntry`, used at L44 and L761;
     - inline `lock`;
     - delete the extra `removeTyped = ""` in `closeRemove`;
   - `Panel.qml`: delete `import Quickshell`; drop `hideWhenEmpty` from the
     pushed settings, and DevenvState's comment mention; pass
     `refreshIntervalSec` unclamped;
   - `Menu.qml`: delete the empty `onSwitchPanelRequested` handler and its
     comment;
   - `EnvList.qml`: inline `maxHeight`, and delete the `width` fallback.

   → verify by `nix flake check` (entry points, no hex colours), and by
   `grep -n 'templateOrder\|removeMessage\|streamName\|skipped' *.qml Model.js`
   returning nothing. The live load comes in step 6.

4. **`pkgs/cli.sh`, `pkgs/cli.nix`, `pkgs/templates-check.nix`, `flake.nix`:**
   - `cli.sh`:
     - inline `allowed_file()` as the two expansions;
     - the fallback splice becomes `sed -i "$((close - 1))r $file" devenv.nix`;
     - `cmd_new` uses `expand_root`;
     - add `row_base DIR`, shared by both row builders;
     - `remove`'s single-arm `case` becomes an `if`;
   - `cli.nix`: drop `passthru.share`;
   - `templates-check.nix`: one `templates --json`, captured before the loop;
   - `flake.nix`: one pacman/yay grep in `repo`, over `*.qml`, `*.js`, `pkgs`
     and `data`, and remove it from the `plugin` check.
   - `tests/cli.sh`:
     - `rm_cli` becomes a plain function, and the running and unknown cases
       pass `STUB_PROCESSES` through `env`, without the `declare -f` subshell;
     - drop the duplicate outer env prefixes;
     - **add a case for the fallback splice**: a stub `devenv init` scaffold
       without the `# languages.*.enable` placeholder, via a stub env switch,
       asserting the preset lands before the last `}` exactly as before.

   → verify by `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
   passing (62 existing cases plus the new one), shellcheck clean in the
   build, and `nix flake check --all-systems --no-build`.

5. **The whole local check:**
   - `nix flake check`;
   - `nix flake check --all-systems --no-build`;
   - `nix build`;
   - fresh-clone `omarchy plugin validate`;
   - `git diff --stat main -- ':!intent' ':!spec' ':!plan'` for the net line
     count.

   → verify by all passing, with the net negative near the review's estimate.
   No commit unless a fix was needed.

6. **Live on razer** (AGENTS.md "Verifying live"). The plugin is installed
   there by Home Manager, so the test copy replaces its link and the link is
   restored afterwards.
   - Read the bus and announce first. Check the nixarchy CI load before any
     local build.
   - Record `shell.json`'s checksum, the plugin link target, the enabled-once
     state, the theme, DND and the workspace.
   - Build the branch on razer from `git archive`, and put the copy in place of
     the link.
   - `rescanPlugins`, `omarchy-restart-shell`, `ping`, and check `qs log` for
     errors from `nixarchy.devenv`.
   - On an empty workspace, checking the layer before every `wtype`:
     - open the menu, then the bar popup (`nixarchy.devenv.bar open`);
     - open the create form (`{"create":true}`), and type in the template
       filter: the list narrows;
     - with `docs/capture.sh --setup`, open the removal chooser on a local demo
       row (four tiers) and on `demo-bound` (revoke only), cancelling each.
   - Restore: `capture.sh --teardown`, put the Home Manager link back, restore
     `shell.json`, restart the shell, and diff against what was recorded.

   → verify by no log errors, every surface drawn, and razer restored.

7. **PR:** link all three artifacts, say `Closes #8`, and include the net line
   count and the razer results.

## Tests

| Command | Expected |
| --- | --- |
| `node --test 'tests/model/*.test.js'` | passes: the existing tests, minus the deleted functions' assertions, plus the `templateChoices` tests |
| `bash tests/cli.sh …` | passes: 62 cases plus the fallback splice |
| `nix flake check` / `--all-systems --no-build` | pass |
| fresh-clone validate | valid |
| razer | no log errors; menu, popup, form filter and both removal choosers drawn |

## Rollback

Revert the step commits, or do not merge. There is no data format, no CLI
contract and no setting change.
