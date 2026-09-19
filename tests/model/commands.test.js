const { test, eq, ok, HOSTILE, HOME, Model } = require("../harness.js")

const P = "/home/user/Source/my app"

test("every devenv argv sets its directory with env -C, never a shell", () => {
  eq(Model.upArgv(P), ["env", "-C", P, "devenv", "up", "-d"])
  eq(Model.downArgv(P), ["env", "-C", P, "devenv", "processes", "down"])
  eq(Model.updateArgv(P), ["env", "-C", P, "devenv", "update"])
  eq(Model.allowArgv(P), ["env", "-C", P, "devenv", "allow"])
  eq(Model.revokeArgv(P), ["env", "-C", P, "devenv", "revoke"])
})

test("enter and edit open a terminal, in the project", () => {
  eq(Model.enterArgv(P), ["omarchy-launch-tui", "--app-id=org.omarchy.devenv-enter", "env", "-C", P, "devenv", "shell"])
  eq(Model.editArgv(P, ["code", "--wait"]), ["omarchy-launch-tui", "--app-id=org.omarchy.devenv-edit",
    "env", "-C", P, "code", "--wait", "devenv.nix"])
  eq(Model.editArgv(P, []).slice(-2), ["nvim", "devenv.nix"])
})

test("gc runs from HOME and is not tied to a project", () => {
  eq(Model.gcArgv(HOME + "/"), ["env", "-C", HOME, "devenv", "gc"])
})

test("list passes each root, and refuses one that is not a safe path", () => {
  eq(Model.listArgv(["/a", "/b c"]), ["nixarchy-devenv", "list", "--json", "--root", "/a", "--root", "/b c"])
  eq(Model.listArgv([]), ["nixarchy-devenv", "list", "--json"])
  eq(Model.listArgv(["/a", "rel"]), null)
})

test("status, copy", () => {
  eq(Model.statusArgv(P), ["nixarchy-devenv", "status", "--json", P])
  eq(Model.copyArgv(P), ["wl-copy", "--trim-newline", "--", P])
})

test("every path-taking builder refuses hostile paths", () => {
  const builders = [Model.upArgv, Model.downArgv, Model.updateArgv, Model.allowArgv, Model.revokeArgv,
    Model.enterArgv, p => Model.editArgv(p, ["nvim"]), Model.statusArgv, Model.copyArgv, Model.gcArgv]
  const paths = HOSTILE.concat(["/a/../b", "/a/./b", "relative", "/x" + String.fromCharCode(10) + "y"])
  for (const b of builders) {
    for (const p of paths) {
      // "a b" and friends are fine as long as they are absolute; none of the
      // hostile strings are.
      eq(b(p), null, b.name + " " + JSON.stringify(p))
    }
  }
})

test("probes", () => {
  eq(Model.cliProbeArgv(), ["nixarchy-devenv", "help"])
  eq(Model.devenvProbeArgv(), ["devenv", "version"])
  eq(Model.templatesArgv(), ["nixarchy-devenv", "templates", "--json"])
})
