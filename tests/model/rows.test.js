const { test, eq, ok, env, HOME, Model } = require("../harness.js")

const envs = () => [
  env({ path: "/home/user/Source/old", name: "old", mtime: 1 }),
  env({ path: "/home/user/Source/new", name: "new", mtime: 9 }),
  env({ path: "/srv/used", name: "used", allowed: true, mtime: 0 })
]

test("rows: allowed first, then newest devenv.nix", () => {
  eq(Model.rowsFor(envs(), HOME).map(r => r.name), ["used", "new", "old"])
})

test("rows are keyed by path and show the parent with ~", () => {
  const r = Model.rowsFor(envs(), HOME)
  eq(r[1].key, "/home/user/Source/new")
  eq(r[1].subtitle, "~/Source")
  eq(r[0].subtitle, "/srv")
})

test("tildePath does not match a sibling that shares a prefix", () => {
  eq(Model.tildePath("/home/username/x", HOME), "/home/username/x")
  eq(Model.tildePath("/home/user", HOME), "~")
})

test("rowRecord types every field", () => {
  const rec = Model.rowRecord({ key: "/a", name: 3, allowed: "yes" })
  eq(rec.name, "3")
  eq(rec.allowed, false)
  eq(rec.lockfile, false)
  eq(rec.template, "")
})

test("filter matches name, path or template, case-insensitively", () => {
  eq(Model.filterEnvs(envs(), "SRV").map(e => e.name), ["used"])
  eq(Model.filterEnvs(envs(), "python").length, 3)
  eq(Model.filterEnvs(envs(), "  ").length, 3)
  eq(Model.filterEnvs(envs(), "zzz"), [])
})

test("cursor follows the environment across a re-sort, else clamps", () => {
  const rows = Model.rowsFor(envs(), HOME)
  eq(Model.cursorAfter("/home/user/Source/old", rows, 0), 2)
  eq(Model.cursorAfter("/gone", rows, 7), 2)
  eq(Model.cursorAfter("", [], 3), 0)
})

test("reconcilePlan turns one key list into the next", () => {
  const apply = (keys, ops) => {
    const k = keys.slice()
    for (const o of ops) {
      if (o.op === "remove") k.splice(o.index, 1)
      else if (o.op === "move") k.splice(o.to, 0, k.splice(o.from, 1)[0])
      else k.splice(o.index, 0, o.row.key)
    }
    return k
  }
  const next = ["c", "a", "d"].map(key => ({ key }))
  eq(apply(["a", "b", "c"], Model.reconcilePlan(["a", "b", "c"], next)), ["c", "a", "d"])
})

test("summaries count environments and allowed ones", () => {
  eq(Model.summaryText(envs(), { cli: true }), "3 environments · 1 allowed")
  eq(Model.summaryText([], {}), "No environments")
  eq(Model.summaryText(envs(), { cli: false }), "nixarchy-devenv missing")
  eq(Model.footerText([envs()[0]]), "1 environment · 0 auto-activate")
})

test("emptyText says why", () => {
  ok(/not installed/.test(Model.emptyText({ cli: false })))
  eq(Model.emptyText({ everLoaded: false }), "Loading…")
  ok(/filter/.test(Model.emptyText({ everLoaded: true, filtered: true })))
  ok(/press c/.test(Model.emptyText({ everLoaded: true, filtered: false })))
})

test("shortcut groups keep their order", () => {
  eq(Model.shortcutGroups().map(g => g.title), ["Move", "Environment", "All", "Panel", "Create form", "Log"])
})

test("rows under a symlinked root read through the configured name", () => {
  const map = [{ given: "/home/user/Source", canonical: "/mnt/data/src" }]
  const rows = Model.rowsFor([env({ path: "/mnt/data/src/GitHub/app" }), env({ path: "/mnt/data/srcx/b", name: "b" })], HOME, map)
  eq(rows.map(r => r.subtitle).sort(), ["/mnt/data/srcx", "~/Source/GitHub"])
  eq(rows.find(r => r.name === "app").path, "/mnt/data/src/GitHub/app")
  eq(Model.parseList(JSON.stringify({ rows: [], rootMap: [{ given: "/a", canonical: "/b" }, { given: "rel", canonical: "/c" }] })).rootMap,
    [{ given: "/a", canonical: "/b" }])
})

test("a bound row reads where it comes from, and filters on it", () => {
  const b = env({ path: "/tmp/b", name: "b", allowed: true, from: "github:org/env", profiles: ["backend", "db"] })
  const r = Model.rowsFor([b], HOME)[0]
  eq(r.bound, true)
  eq(r.detail, "from github:org/env · profiles backend, db")
  eq(Model.rowsFor([env({ path: "/tmp/c", from: "path:/x" })], HOME)[0].detail, "from path:/x")
  const local = Model.rowsFor([env({ template: "python" })], HOME)[0]
  eq(local.bound, false)
  eq(local.detail, "python")
  eq(Model.filterEnvs([b, env({ path: "/tmp/other", name: "other" })], "org/env").map(e => e.name), ["b"])
  eq(Model.rowRecord(r).bound, true)
  eq(Model.rowRecord(local).detail, "python")
})
