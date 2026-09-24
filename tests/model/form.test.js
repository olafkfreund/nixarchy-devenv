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

// The mirror of the git rule above. honours_allow was parsed and plumbed all
// the way from data/templates.nix into the template model, and then never read
// by anything -- so a generator declaring it does not allow would still have
// been handed --allow.
test("a generator that never allows automatic activation is not sent --allow", () => {
  const INDEX = JSON.stringify([
    { id: "noallow", kind: "generator", group: "Cloud", label: "No allow", note: "n",
      flake: "github:o/n", rev: "def", providers: ["aws"], honours_git: true, honours_allow: false }
  ])
  const ts = Model.parseTemplates(INDEX)
  eq(ts[0].honoursAllow, false)

  const r = Model.validateForm({ template: "noallow", providers: ["aws"], name: "app",
    parent: "~/Source", git: true, allow: true }, ts, HOME)
  eq(r.ok, true)
  ok(r.argv.indexOf("--allow") === -1)

  // and the form says so, rather than offering a toggle that does nothing
  const allow = Model.formFields(ts, "noallow").filter(f => f.key === "allow")[0]
  eq(allow.locked, true)
  ok(/never allows/.test(allow.hint))
})

// The ordinary case is unchanged: a generator that does honour it still gets
// the flag when the toggle is on.
test("a generator that honours allow still gets --allow", () => {
  const r = v({ template: "cloud", providers: ["aws"], allow: true })
  eq(r.ok, true)
  ok(r.argv.indexOf("--allow") !== -1)
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

test("emptyForm starts in the first root, python, git on, allow off", () => {
  eq(Model.emptyForm(["/home/user/Source", "/srv"], HOME), { name: "", parent: "~/Source", template: "python",
    providers: [], git: true, allow: false })
  eq(Model.emptyForm([], HOME).parent, "~")
})

test("formFields adds providers for a generator and locks git where it cannot be honoured", () => {
  eq(Model.formFields(templates(), "python").map(f => f.key), ["name", "parent", "template", "git", "allow"])
  const cloud = Model.formFields(templates(), "cloud")
  eq(cloud.map(f => f.key), ["name", "parent", "template", "providers", "git", "allow"])
  eq(cloud.find(f => f.key === "git").locked, true)
  eq(Model.firstErrorIndex(cloud, { providers: "x" }), 3)
})

test("toggleProvider adds and removes", () => {
  eq(Model.toggleProvider(["aws"], "gcp"), ["aws", "gcp"])
  eq(Model.toggleProvider(["aws", "gcp"], "aws"), ["gcp"])
})
