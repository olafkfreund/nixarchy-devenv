const { test, eq, ok, listRow, templates, Model } = require("../harness.js")

const list = (rows, extra) => JSON.stringify(Object.assign({ rows: rows, warnings: [], skipped: 0 }, extra || {}))
const ESC = String.fromCharCode(27)
const BEL = String.fromCharCode(7)
const NL = String.fromCharCode(10)
const CR = String.fromCharCode(13)

test("parseList keeps well-formed rows and types every field", () => {
  const out = Model.parseList(list([listRow({ allowed: true })]))
  eq(out.ok, true)
  eq(out.rows.length, 1)
  eq(out.rows[0], { path: "/home/user/Source/app", name: "app", allowed: true, lockfile: true,
    template: "python", hasProcesses: false, dev: 2049, mtime: 1000 })
})

test("parseList drops rows without a safe absolute path", () => {
  const bad = ["", "relative", "/a/../b", "/a/./b", "/a" + NL + "b", null, 42, "/a//b"]
  const out = Model.parseList(list(bad.map(p => listRow({ path: p }))))
  eq(out.rows, [])
})

test("parseList defaults what an older or newer CLI leaves out", () => {
  const out = Model.parseList(list([{ path: "/p/x", extra: "ignored" }]))
  eq(out.rows[0], { path: "/p/x", name: "x", allowed: false, lockfile: false, template: "custom",
    hasProcesses: false, dev: -1, mtime: 0 })
})

test("parseList: a template that is not an id is custom; truthy non-booleans are false", () => {
  const out = Model.parseList(list([listRow({ template: "../../etc", allowed: "yes", lockfile: 1 })]))
  eq(out.rows[0].template, "custom")
  eq(out.rows[0].allowed, false)
  eq(out.rows[0].lockfile, false)
})

test("parseList carries warnings and the skipped count, sanitised", () => {
  const out = Model.parseList(list([], { warnings: ["/nope is missing" + BEL], skipped: 3 }))
  eq(out.warnings, ["/nope is missing"])
  eq(out.skipped, 3)
})

test("parseList of garbage is an empty, not-ok list", () => {
  for (const raw of ["", "not json", "null", "[]x", undefined]) {
    const out = Model.parseList(raw)
    eq(out.rows, [])
    eq(out.ok, false)
  }
})

test("parseTemplates reads each kind and keeps generator fields", () => {
  const t = templates()
  eq(t.map(x => x.id), ["python", "flutter", "ml", "cloud", "mine"])
  const cloud = Model.templateById(t, "cloud")
  eq(cloud.kind, "generator")
  eq(cloud.providers, ["aws", "azure", "gcp"])
  eq(cloud.honoursGit, false)
  eq(Model.templateById(t, "python").honoursGit, true)
  eq(Model.templateById(t, "python").providers, [])
})

test("parseTemplates drops bad ids and bad providers", () => {
  const t = Model.parseTemplates(JSON.stringify([
    { id: "Bad Id", kind: "preset" },
    { id: "g", kind: "generator", providers: ["aws", "x y", "$(id)"] }
  ]))
  eq(t.map(x => x.id), ["g"])
  eq(t[0].providers, ["aws"])
})

test("templateGroups orders sections, unknown groups last", () => {
  const t = templates().concat(Model.parseTemplates(JSON.stringify([{ id: "z", group: "Weird" }])))
  eq(Model.templateGroups(t).map(g => g.title), ["Languages", "Data & ML", "Mobile", "Cloud", "Yours", "Weird"])
  eq(Model.templateOrder(t), ["python", "ml", "flutter", "cloud", "mine", "z"])
})

test("parseStatus: running, stopped, everything else unknown", () => {
  const running = Model.parseStatus(JSON.stringify({ state: "running", devenv: true,
    processes: [{ name: "web", status: "ready" }] }))
  eq(running.state, "running")
  eq(Model.statusText(running), "running: web")
  eq(Model.parseStatus('{"state":"stopped","devenv":true,"processes":[]}').state, "stopped")
  for (const raw of ["", "x", '{"state":"weird"}', '{"state":"RUNNING"}']) eq(Model.parseStatus(raw).state, "unknown")
  const missing = Model.parseStatus('{"state":"unknown","devenv":false,"processes":[]}')
  eq(missing.devenv, false)
  eq(Model.statusText(missing), "unknown (devenv missing)")
})

test("errorText prefers the CLI's own reason, else the last line", () => {
  eq(Model.errorText(["progress", "nixarchy-devenv: first", "nixarchy-devenv: the reason", ""].join(NL)), "the reason")
  eq(Model.errorText("• Validating" + NL + "  " + ESC + "[31m×" + ESC + "[0m Failed to lock inputs" + NL), "Failed to lock inputs")
  eq(Model.errorText(""), "")
})

test("stripAnsi keeps what the last redraw left", () => {
  eq(Model.stripAnsi(ESC + "[32mok" + ESC + "[0m"), "ok")
  eq(Model.stripAnsi("10%" + CR + "50%" + CR + "100% done"), "100% done")
  ok(Model.capLine("x".repeat(5000)).length <= Model.LINE_CAP)
})
