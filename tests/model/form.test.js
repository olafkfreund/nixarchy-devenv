const { test, eq, ok, templates, HOSTILE, HOME, Model } = require("../harness.js")

const form = o => Object.assign({ name: "app", parent: "~/Source", template: "python", providers: [], git: true, allow: false }, o || {})
const v = o => Model.validateForm(form(o), templates(), HOME)

test("a valid preset form builds the new argv, allow off, git on", () => {
  const r = v()
  eq(r.ok, true)
  eq(r.argv, ["nixarchy-devenv", "new", "--parent", "/home/user/Source", "--name", "app", "python"])
  eq(r.path, "/home/user/Source/app")
})

test("allow and no-git are flags only when asked", () => {
  eq(v({ allow: true, git: false }).argv, ["nixarchy-devenv", "new", "--allow", "--no-git",
    "--parent", "/home/user/Source", "--name", "app", "python"])
})

test("a generator needs providers from its own list, deduped", () => {
  eq(v({ template: "cloud" }).errors.providers, "Pick at least one provider")
  ok(v({ template: "cloud", providers: ["aws", "mars"] }).errors.providers)
  eq(v({ template: "cloud", providers: ["aws", "gcp", "aws"] }).argv.slice(-3), ["cloud", "aws", "gcp"])
})

test("a generator that always runs git init never gets --no-git", () => {
  const r = v({ template: "cloud", providers: ["aws"], git: false })
  eq(r.ok, true)
  ok(r.argv.indexOf("--no-git") === -1)
})

test("providers are ignored for presets", () => {
  eq(v({ providers: ["aws"] }).argv.slice(-1), ["python"])
})

test("every field refuses hostile input", () => {
  for (const bad of HOSTILE) {
    ok(!v({ name: bad }).ok, "name " + JSON.stringify(bad))
    ok(!v({ template: bad }).ok, "template " + JSON.stringify(bad))
    ok(!v({ template: "cloud", providers: [bad] }).ok, "provider " + JSON.stringify(bad))
    if (bad !== "~" && bad.charAt(0) !== "/") ok(!v({ parent: bad }).ok, "parent " + JSON.stringify(bad))
  }
})

test("names: letters, digits, . _ -, never leading - or .", () => {
  for (const good of ["app", "my-app", "a.b", "_x", "A1"]) ok(v({ name: good }).ok, good)
  for (const bad of ["-x", ".x", "..", ".", "a/b", "x".repeat(65)]) ok(!v({ name: bad }).ok, bad)
})

test("parent: ~ and absolute only, and no ~user", () => {
  eq(v({ parent: "~" }).argv[3], "/home/user")
  eq(v({ parent: "/srv/" }).argv[3], "/srv")
  for (const bad of ["rel", "~root", "~root/x", "/a/../b", ""]) ok(!v({ parent: bad }).ok, bad)
})

test("formSummary names the job", () => {
  eq(Model.formSummary(form({ template: "cloud", providers: ["aws", "gcp"] })), "create app (cloud: aws gcp)")
})
