---
status: approved
issue: 4
spec: spec/2026-09-21-4-bound-environments.md
---

# Plan: List environments bound with `devenv --from`

Branch `feat/4-bound-environments`. One commit per step, citing the step,
e.g. `feat(cli): list bound environments (#4, step 1)`.

## Approved decisions (self-contained)

- A directory bound with `devenv --from <src> allow` is recorded in devenv's
  `allowed` file as a JSON line `{"path","from","profiles"?}` (devenv v2.3.1,
  `TrustEntry` in `devenv/src/commands/hook.rs`). A line whose `from` is a
  string is a binding.
- The binding gets a row when:
  - its directory exists;
  - it is not already a row;
  - **no ancestor-or-self has a `devenv.nix`** (`-e`, which matches devenv's
    `find_project_root` and its `.exists()`). Otherwise devenv ignores the
    binding, and the directory is listed as an ordinary local row, or not at
    all.
- Bound rows are listed wherever they are, not only under the roots.
- The row fields for a bound directory are:
  - `allowed: true` and `template: "custom"`;
  - `hasProcesses: true` (Start is offered, not claimed);
  - `lockfile` from `devenv.lock` in the directory;
  - `dev` and `mtime` from `stat` of the directory;
  - `from` (the source string) and `profiles` (a string array).

  Local rows get `from: ""` and `profiles: []`.
- The plugin reads `allowed` and never writes to it. It evaluates nothing.
  Directories that no longer exist are hidden, never removed from devenv's
  database.
- Actions on a bound row:
  - offered as on a local row: enter, start/stop, update (decision 2), and
    revoke;
  - not offered: edit;
  - removal offers **revoke only**. `removeRefusal` refuses every other tier,
    and the CLI's existing `has no devenv.nix of its own` refusal remains the
    authority.
- The revoke message names the source, says the saved profiles go with it and
  that nothing is deleted, and says the row then leaves the list.
- The caption shows `from <source>`, plus ` · profiles a, b` when there are
  any. The filter matches on `from`.
- `profiles` are kept only if they match `^[A-Za-z0-9._-]+$`, and `from` is
  sanitized to 200 characters.

## Steps

1. **`pkgs/cli.sh` `cmd_list`: the bound pass.**
   - Leave the existing `allowed.raw` pass and the `skipped` count as they are.
   - Add a comment citing devenv v2.3.1 `TrustEntry`, `find_project_root` and
     `trusted_from`.
   - Add a second pass:
     `jq -R -c 'fromjson? | select((.path|type)=="string" and (.path|startswith("/")) and (.from|type)=="string") | {path, from, profiles: ((.profiles // []) | if type=="array" then map(strings) else [] end)}' "$af" > "$tmp/bound"`.
   - Add a helper `shadowed DIR` that walks from DIR up to `/` and succeeds if
     any level has `-e devenv.nix`.
   - After the local loop, and sharing `seen[]` with it, read `$tmp/bound`
     line by line:
     - take `path` with jq;
     - get `real` with `realpath -e`, or skip;
     - skip if it is in `seen`, or if `shadowed "$real"`;
     - emit the row with the bound values above. `from` and `profiles` are
       passed via `--argjson` from the object, never re-split in shell.
   - Add `from: ""` and `profiles: []` to local rows.
   - Extend `tests/cli.sh`:
     - add to the list fixture's `allowed` file:
       - `$O/bound`: a lock, `profiles:["backend"]`, outside the roots;
       - `$L/boundlocal`: its own `devenv.nix`;
       - `$L/a/boundbelow`: below the local project `a`;
       - `$root/boundgone`: does not exist;
       - `$O/badfrom`: `from: 42`, no `devenv.nix`;
     - assert:
       - `$O/bound` is listed, with `allowed`, `custom`, `hasProcesses`,
         `lockfile`, its `from` and `profiles == ["backend"]`;
       - `$L/boundlocal` is one row, with `from == ""`;
       - `$L/a/boundbelow`, `$root/boundgone` and `$O/badfrom` are absent;
       - `skipped` is still `3`;
       - row `a` has `from == ""` and `profiles == []`;
       - the allow-file checksum is unchanged (the existing assertion).
     - add removal cases: a bound directory with `.devenv/state/db/x`, where
       `remove --tier files`, `state` and `folder` each exit 2 and everything
       is still there.

   → verify by
   `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"`
   passing, with shellcheck clean in the build.

2. **`Model.js`: rows, actions, tiers, messages.**
   - `parseList` reads `from` with `sanitize(…, 200)`, and `profiles` as an
     allowlisted array (anything else becomes `[]`).
   - Add a helper `isBound(env)` (`str(env.from) !== ""`).
   - `rowsFor` adds `bound` and `detail`, and `ROW_FIELDS`/`ROW_BOOLEANS`
     gain `detail` and `bound`.
   - `filterEnvs` matches on `from`.
   - `actionsFor` omits `edit` when `row.bound`.
   - Add `tiersFor(env)`: `TIERS` for a local environment. For a bound one it
     is a single revoke tier whose `text` is the bound revoke message.
     *Deviation, found live on razer in step 6:* the chooser draws each tier's
     own `text` and never calls `removeMessage`. With `[TIERS[0]]` the dialog
     read "Stop it activating on cd", so the source and profiles were never
     mentioned on screen.
   - `removeRefusal` returns `"Bound to <from>: nothing here to remove;
     revoke forgets the binding"` for a non-revoke tier on a bound env, before
     the path checks.
   - `removeMessage` uses the bound revoke text.
   - The shortcut `e` text becomes "Edit its devenv.nix in your editor (not
     for bound environments)".
   - Add tests in `tests/model/`:
     - `parsing.test.js`: `from`/`profiles`, including hostile values
       (control characters, a 500-character source, profiles with `/`, a
       space or a newline, a non-array, an older CLI without the fields);
     - `rows.test.js`: `detail`, `bound`, filtering on `from`;
     - `availability.test.js`: no `edit` for a bound row, with enter, update,
       start and revoke present;
     - `remove.test.js`: `tiersFor`, the refusal for `files`/`state`/`folder`,
       the revoke message naming the source.

   → verify by `node tests/run.js` passing.

3. **QML.**
   - `EnvList.qml:187`: `rowSurface.row.template` → `rowSurface.row.detail`.
   - `DevenvView.qml`: add
     `readonly property var removeTiers: Model.tiersFor(root.removeEnv)`.
     `removeTierId`, the Repeater model (`:684`), `moveTier` (`:216`) and the
     footer text (`:760`) use `root.removeTiers` instead of `Model.TIERS`.

   → verify by `nix flake check` (the entry-point and no-hex-colour checks),
   and by `grep -n 'Model.TIERS' *.qml` returning nothing.

4. **Docs.**
   - `docs/usage.md`: a "Bound environments" section covering what the row
     shows and why the template is `custom`, that there is no edit and no
     deletion, that revoke drops the source and profiles and the row then
     leaves the list, and that a `devenv.nix` in the directory or above it
     wins.
   - `README.md`: one line where it says what is listed.

   → verify by reading it back, and by checking that no hex colours or
   forbidden words were introduced (`nix flake check`).

5. **The whole local check.**
   - `nix flake check`
   - `nix flake check --all-systems --no-build`
   - `nix build`
   - validate a fresh clone:
     `d=$(mktemp -d) && git clone -q . "$d/p" && rm -rf "$d/p/.git" && omarchy plugin validate "$d/p"`

   → verify by all of them passing. No commit unless something needed fixing.

6. **Live on razer.** The owner has said it is open and idle. Neither the
   plugin nor the CLI is installed there today (checked 2026-09-21: devenv
   2.3.1, `nixarchy-devenv` missing, no `nixarchy.devenv` in
   `~/.config/omarchy/plugins`).
   1. **Ship the build.** Send `git archive HEAD` to
      `~/.local/state/nixarchy-devenv-test/src` on razer, and build `.#plugin`
      and `.#cli` there with `-o ../plugin` and `-o ../cli` (these are the
      gcroots). *Deviation:* `nix copy` was refused because razer does not
      trust this machine's unsigned paths. Building there gave the same store
      paths, and razer's trust settings stay as they were.
      Over SSH, source `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`,
      `HYPRLAND_INSTANCE_SIGNATURE`, `DBUS_SESSION_BUS_ADDRESS`, `OMARCHY_PATH`
      and `PATH` from `/proc/<quickshell pid>/environ`. Without them
      `omarchy-shell` reports "not running".
   2. **Record razer's state first.**
      - `sha256sum ~/.local/share/devenv/allowed`, or "absent" (saved as
        `before`).
      - Is `~/.local/bin` on quickshell's PATH? Read it from
        `/proc/<quickshell pid>/environ`.
      - Save a copy of `~/.config/omarchy/shell.json`, if present.
   3. **Install the test copy** per AGENTS.md "Verifying live":
      - `cp -rL <plugin> ~/.config/omarchy/plugins/nixarchy.devenv` and
        `chmod -R u+w` it;
      - `ln -s <cli>/bin/nixarchy-devenv ~/.local/bin/nixarchy-devenv`;
      - `omarchy-shell shell rescanPlugins`;
      - `omarchy plugin enable nixarchy.devenv`;
      - `omarchy-restart-shell`, then wait for `omarchy-shell shell ping`.
   4. **Make the fixtures.**
      - Create `t=$(mktemp -d)`.
      - `$t/src`: a minimal `devenv.nix` (`{ ... }: { }`) and `devenv.yaml`,
        made with `devenv init` there.
      - `$t/t1`: an empty directory. Run
        `cd $t/t1 && devenv --from path:$t/src allow`. That is one
        user-initiated allow of a throwaway directory, which is exactly the
        binding under test.
   5. **Check the CLI.** `nixarchy-devenv list --json` has a `$t/t1` row with
      `from == "path:$t/src"` (normalised by devenv) and `allowed: true`.
      `nixarchy-devenv remove --tier files …` on it exits 2.
   6. **Check the GUI.** Before every `wtype`, check `hyprctl layers -j` for
      `nixarchy-devenv-menu` or `omarchy-keyboard-panel`, and stop if the
      screen shows input that was not sent.
      - Open the menu (`omarchy-shell shell toggle nixarchy.devenv '{}'`),
        filter to `t1`, and screenshot: the caption reads `from path:…`.
      - `e` does nothing.
      - `x` shows the revoke tier only, and the message names the source.
      - Confirm the revoke. The row leaves the list after refresh.
      - Open the bar popup with `omarchy shell nixarchy.devenv.bar open` and
        check that the row appeared there before the revoke.
      - Check `qs log -i <instance>` for errors.
   7. **Check the result.** `grep -c "$t" ~/.local/share/devenv/allowed` is 0.
      razer had **no** `allowed` file on 2026-09-21. devenv's revoke rewrites
      the whole file (`write_trust_lines`), so after this test it exists and
      is empty. If `before` was "absent" and the file is now empty, removing
      it restores razer exactly. If it is non-empty, or `before` was a real
      checksum, compare the line sets and report rather than edit: devenv
      also rewrites legacy plain-path lines as JSON on every allow and
      revoke, so a byte-for-byte match is not guaranteed.
   8. **Tear down.**
      - `rm -rf "$t"`.
      - Remove `~/.local/share/devenv/allowed` **only** if `before` was
        "absent" and the file is now empty.
      - `omarchy plugin disable nixarchy.devenv`.
      - Remove the plugin copy, the `~/.local/bin` symlink and the gcroots.
      - Restore `shell.json` if it changed.
      - `omarchy-restart-shell`, then ping.
      - `ls ~/.config/omarchy/plugins` matches the listing from before.

   → verify by steps 6.5 to 6.7 passing, screenshots saved to the scratchpad,
   and razer left as it was found.

6b. **Captures for both sites.** Added by the owner on 2026-09-21: "post this
   in nixarchy-devenv as well as the nixarchy gh page … add this to 4".
   The step 6 screenshots cannot be published: they show the owner's
   terminals, and a directory that is not named `demo-*`.
   - `docs/capture.sh --setup` also makes `demo-shared` (a `devenv init`
     project with `env.GREET = "demo-shared"`) and `demo-bound`: no
     `devenv.nix`, bound with `devenv --from path:<demo>/demo-shared allow`,
     recorded as `allowed` so `--teardown` revokes it. It builds the first
     shell during setup.
   - Follow AGENTS.md "Retaking the captures" and nixarchy's
     `docs/AGENTS.md`:
     - record razer's theme and wallpaper (Gruvbox, The Backwater), and
       switch to Tokyo Night with the Winding Road wallpaper;
     - turn Do Not Disturb on;
     - use an empty workspace (31), park the pointer, and reopen the surface;
     - check the layers before every `wtype`.
   - One `wl-screenrec` recording of the whole screen:
     1. open the menu, where `demo-bound` reads `from path:…/demo-shared`;
     2. `x` shows the revoke-only dialog; `esc`;
     3. `enter` opens `devenv shell`, which prints `hello from demo-shared`;
        `ls -A` there shows no `devenv.nix`;
     4. back in the menu, `x` and `enter` revoke it, and the row leaves the
        list.
   - This repository:
     - `docs/img/bound.png` (a 1056-wide still of the menu);
     - `docs/img/rec-bound.{webm,mp4}` (a panel crop, VP9 `-crf 40` and
       H.264 `-crf 28`);
     - a "Bound environments" section in `docs/index.md`;
     - `docs/img` stays under 8 MB.
   - nixarchy: a whole-desktop 16:10 GIF (900x563, 4 fps, at most 96
     colours, under 1 MB) and a still, for `docs/manual/plugins.md`. That is
     another repository, so it follows that repository's own
     intent/spec/plan workflow: an issue and a draft intent there, stopping
     for review before its site changes.
   - `docs/capture.sh --teardown`, then restore the theme, wallpaper, Do Not
     Disturb and workspace. Diff `shell.json` against the step 6.2 copy.

   → verify by looking at every still, and at a frame sheet of each video,
   before committing.

7. **PR.** Push the branch and open a PR that links the intent, spec and plan
   and says `Closes #4`, and add the razer results to its description.

## Tests

| Command | Expected |
| --- | --- |
| `node tests/run.js` | all pass, new cases included |
| `bash tests/cli.sh "$(nix build .#cli --print-out-paths)/bin/nixarchy-devenv"` | all pass, new list and remove cases included |
| `nix flake check` | passes |
| `nix flake check --all-systems --no-build` | evaluates |
| fresh-clone `omarchy plugin validate` | valid |
| razer, step 6 | bound row listed on both surfaces, no edit, revoke-only removal, allow file restored |

## Rollback

- **Code:** revert the step commits, or do not merge the PR. Nothing
  outside this repository changes, and no data format is written.
- **razer:** step 6.8 is the rollback. If the session is interrupted, run it
  by hand:
  - `rm -rf ~/.config/omarchy/plugins/nixarchy.devenv ~/.local/bin/nixarchy-devenv ~/.local/state/nixarchy-devenv-test`;
  - `omarchy plugin disable nixarchy.devenv`;
  - `cd <t1> && devenv revoke`, if the binding survived;
  - `omarchy-restart-shell`.
