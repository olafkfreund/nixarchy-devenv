const { test, eq, HOME, Model } = require("../harness.js")

const DEFAULTS = { projectRoots: "~/Source:~/Projects", refreshIntervalSec: 60, terminalEditor: "", hideWhenEmpty: false }
const NL = String.fromCharCode(10)

test("settingsFor reads the bar entry, type-checked", () => {
  const bar = { layout: { right: ["clock", { id: "nixarchy.devenv", refreshIntervalSec: 30, hideWhenEmpty: "yes", projectRoots: "/x" }] } }
  const s = Model.settingsFor(bar, "nixarchy.devenv", DEFAULTS)
  eq(s.refreshIntervalSec, 30)
  eq(s.hideWhenEmpty, false)
  eq(s.projectRoots, "/x")
})

test("settingsFor accepts Qt sequence wrappers, which are not arrays", () => {
  const seq = { length: 1, 0: { id: "nixarchy.devenv", terminalEditor: "hx" } }
  eq(Model.settingsFor({ layout: { left: seq } }, "nixarchy.devenv", DEFAULTS).terminalEditor, "hx")
})

test("settingsFor falls back to defaults", () => {
  eq(Model.settingsFor(null, "nixarchy.devenv", DEFAULTS), DEFAULTS)
  eq(Model.settingsFor({ layout: { right: ["nixarchy.devenv"] } }, "nixarchy.devenv", DEFAULTS), DEFAULTS)
})

test("rootsFor expands ~, dedupes, and rejects what is not a safe absolute path", () => {
  const out = Model.rootsFor(["~/Source", "~/Source/", "/srv", "rel", "~root/x", "/a/../b", "/a" + NL + "b"], HOME)
  eq(out.roots, ["/home/user/Source", "/srv"])
  eq(out.rejected, ["rel", "~root/x", "/a/../b", "/a" + NL + "b"])
  eq(Model.rootsFor({ length: 1, 0: "~" }, HOME).roots, ["/home/user"])
  eq(Model.rootsFor(undefined, HOME).roots, [])
  eq(Model.rootsFor("~/Source:/srv::  :~/Source", HOME).roots, ["/home/user/Source", "/srv"])
  eq(Model.rootsFor(Model.DEFAULT_ROOTS, HOME).roots, ["/home/user/Source", "/home/user/Projects"])
})

test("editorWords: setting, then $EDITOR, then nvim; plain words only", () => {
  eq(Model.editorWords("", "code --wait"), ["code", "--wait"])
  eq(Model.editorWords("hx", "code"), ["hx"])
  eq(Model.editorWords("", ""), ["nvim"])
  for (const bad of ["vim; rm -rf ~", "$(id)", "-x", "a `b`", "a|b", "e" + NL + "f"]) eq(Model.editorWords(bad, ""), ["nvim"])
  eq(Model.editorWords("bad;", "emacs -nw"), ["emacs", "-nw"])
})
