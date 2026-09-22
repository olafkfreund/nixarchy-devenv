const { test, eq, ok, env, HOME, Model } = require("../harness.js")

const ROOTS = ["/home/user/Source", "/srv/projects"]
const STOPPED = { state: "stopped", devenv: true, processes: [] }
const refuse = (o, tier, status, typed) => Model.removeRefusal(env(o), tier || "files", ROOTS, HOME, status === undefined ? STOPPED : status, typed)

test("a stopped environment under a root may lose its devenv files", () => {
  eq(refuse({}), "")
  eq(refuse({}, "state"), "")
})

test("revoke is always allowed: it deletes nothing", () => {
  eq(refuse({ path: "/home/user" }, "revoke", null), "")
  eq(Model.removeArgv(env(), "revoke", ROOTS), ["env", "-C", "/home/user/Source/app", "devenv", "revoke"])
})

test("never /, HOME, a root, or anything containing a root", () => {
  ok(/\//.test(refuse({ path: "/" })))
  ok(/home directory/.test(refuse({ path: "/home/user" })))
  ok(/project root/.test(refuse({ path: "/home/user/Source" })))
  ok(/project root/.test(refuse({ path: "/srv" })))
  ok(/project root/.test(refuse({ path: "/srv/projects" })))
  eq(refuse({ path: "/srv/projects-old/x" }), "")
})

test("running or unknown processes block every deleting tier", () => {
  for (const tier of ["files", "state", "folder"]) {
    ok(/stop them/.test(refuse({}, tier, { state: "running", devenv: true, processes: [] }, "app")))
    ok(/Could not tell/.test(refuse({}, tier, { state: "unknown", devenv: true, processes: [] }, "app")))
    ok(/Could not tell/.test(refuse({}, tier, null, "app")))
  }
})

test("without devenv there is nothing that could be running", () => {
  eq(refuse({}, "files", { state: "unknown", devenv: false, processes: [] }), "")
})

test("the folder tier needs the name typed exactly", () => {
  ok(/Type the folder name/.test(refuse({}, "folder", STOPPED, "")))
  ok(/Type the folder name/.test(refuse({}, "folder", STOPPED, "App")))
  eq(refuse({}, "folder", STOPPED, " app "), "")
})

test("a row with no device number is refused: refresh first", () => {
  ok(/Refresh/.test(refuse({ dev: undefined })))
})

test("unknown tiers and missing environments are refused", () => {
  ok(Model.removeRefusal(null, "files", ROOTS, HOME, STOPPED, ""))
  ok(Model.removeRefusal(env(), "everything", ROOTS, HOME, STOPPED, ""))
  eq(Model.removeArgv(env(), "everything", ROOTS), null)
})

test("removeArgv confirms the exact path, device and roots", () => {
  eq(Model.removeArgv(env(), "state", ROOTS), ["nixarchy-devenv", "remove", "--tier", "state",
    "--confirm", "/home/user/Source/app", "--dev", "2049",
    "--root", "/home/user/Source", "--root", "/srv/projects", "/home/user/Source/app"])
  eq(Model.removeArgv(env(), "files", ["rel"]), null)
  eq(Model.removeArgv(env({ dev: -1 }), "files", ROOTS), null)
})

test("the tiers say what they keep, and gc says it is for every project", () => {
  ok(Model.tiersFor(env())[1].text.indexOf(".devenv/state") !== -1)
  ok(/every project/.test(Model.gcMessage()))
})

test("a bound environment offers revoke only, and says what revoke forgets", () => {
  const b = { from: "github:org/env", profiles: ["backend"] }
  eq(Model.tiersFor(env(b)).map(t => t.id), ["revoke"])
  ok(/bound to github:org\/env/.test(Model.tiersFor(env(b))[0].text), "the chooser's own text names the source")
  eq(Model.TIERS[0].text, "Stop it activating on cd. Nothing is deleted.")
  eq(Model.tiersFor(env()).map(t => t.id), ["revoke", "files", "state", "folder"])
  eq(Model.tiersFor(null).length, 4)
  eq(refuse(b, "revoke"), "")
  for (const tier of ["files", "state", "folder"]) ok(/^Bound to github:org\/env: nothing here to remove/.test(refuse(b, tier, STOPPED, "app")))
  const text = Model.tiersFor(env(b))[0].text
  ok(/saved profiles/.test(text) && /Nothing is deleted/.test(text))
  ok(!/bound to/.test(Model.tiersFor(env())[0].text))
})
