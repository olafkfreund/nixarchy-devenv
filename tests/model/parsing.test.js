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
    template: "python", hasProcesses: false, ident: "2049:1234", mtime: 1000, from: "", profiles: [] })
})

// A directory on disk can be named anything; only names typed into the form go
// through the NAME allowlist. A discovered name is shown in the row and then
// typed back to confirm the folder tier, so a bidi override in it would let the
// row render as something other than what it is.
test("parseList strips bidi controls from a discovered name", () => {
  const RLO = "\u202E", PDF = "\u202C", LRI = "\u2066", PDI = "\u2069"
  const out = Model.parseList(list([listRow({ path: "/p/x", name: "safe" + RLO + "gpj.exe" + PDF })]))
  eq(out.rows[0].name, "safegpj.exe")
  const b = Model.parseList(list([listRow({ path: "/p/y", name: LRI + "a" + PDI + "b" })]))
  eq(/[\u202A-\u202E\u2066-\u2069]/.test(b.rows[0].name), false)
})

// Stripping the controls must not become "ASCII only": real project names in
// other scripts have to survive intact.
test("sanitize keeps legitimate non-ASCII names", () => {
  eq(Model.sanitize("проект", 80), "проект")
  eq(Model.sanitize("プロジェクト", 80), "プロジェクト")
  eq(Model.sanitize("café-app", 80), "café-app")
})

// hasControlChars is deliberately NOT widened: it gates isAbsPath, which gates
// every argv builder. Widening it would leave such a row visible but with every
// action silently returning null.
test("hasControlChars and isAbsPath are unchanged by the bidi strip", () => {
  eq(Model.hasControlChars("a\u202Eb"), false)
  eq(Model.isAbsPath("/p/a\u202Eb"), true)
  eq(Model.hasControlChars("a\u0000b"), true)
})

test("parseList drops rows without a safe absolute path", () => {
  const bad = ["", "relative", "/a/../b", "/a/./b", "/a" + NL + "b", null, 42, "/a//b"]
  const out = Model.parseList(list(bad.map(p => listRow({ path: p }))))
  eq(out.rows, [])
})

test("parseList defaults what an older or newer CLI leaves out", () => {
  const out = Model.parseList(list([{ path: "/p/x", extra: "ignored" }]))
  eq(out.rows[0], { path: "/p/x", name: "x", allowed: false, lockfile: false, template: "custom",
    hasProcesses: false, ident: "", mtime: 0, from: "", profiles: [] })
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

test("parseList keeps the canonical roots, safe ones only", () => {
  eq(Model.parseList(list([], { roots: ["/mnt/data/Source-home", "rel", "/a/../b"] })).roots, ["/mnt/data/Source-home"])
  eq(Model.parseList(list([])).roots, [])
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
  eq(Model.templateChoices(t, "").map(x => x.id), ["python", "ml", "flutter", "cloud", "mine", "z"])
})

test("templateChoices narrows by id, label or group, ignoring case", () => {
  const ids = q => Model.templateChoices(templates(), q).map(x => x.id)
  eq(ids(""), ["python", "ml", "flutter", "cloud", "mine"])
  eq(ids(undefined), ids(""))
  eq(ids("PYTH"), ["python"])
  eq(ids("cloud project"), ["cloud"])
  eq(ids("mobile"), ["flutter"])
  eq(ids("nothing-like-this"), [])
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

test("parseList keeps a bound row's source and only well-formed profile names", () => {
  const rows = r => Model.parseList(JSON.stringify({ rows: [Object.assign({ path: "/p/b" }, r)] })).rows[0]
  eq(rows({ from: "github:org/env?dir=x", profiles: ["backend", "fast.start_1"] }).from, "github:org/env?dir=x")
  eq(rows({ from: "github:org/env", profiles: ["backend", "fast.start_1"] }).profiles, ["backend", "fast.start_1"])
  eq(rows({ from: "git\u001b[31mhub:x\n" }).from, "git[31mhub:x")
  eq(rows({ from: "x".repeat(500) }).from.length, 200)
  eq(rows({ from: 42 }).from, "42")
  eq(rows({ profiles: ["a/b", "a b", "a\nb", "", 3, null, "x".repeat(65), "ok"] }).profiles, ["ok"])
  eq(rows({ profiles: "backend" }).profiles, [])
  eq(rows({ profiles: { length: 1, 0: "backend" } }).profiles, ["backend"])
})
