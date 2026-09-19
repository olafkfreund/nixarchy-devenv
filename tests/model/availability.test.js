const { test, eq, env, HOME, Model } = require("../harness.js")

const row = o => Model.rowsFor([env(o)], HOME)[0]
const verbs = (r, lock, deps, status) => Model.actionsFor(r, lock, deps, status).map(a => a.verb + (a.enabled ? "" : "-"))
const ALL = { cli: true, devenv: true }
const RUNNING = { state: "running", devenv: true, processes: [] }

test("a plain environment: enter, edit, update, allow, remove", () => {
  eq(verbs(row(), {}, ALL, null), ["enter", "edit", "update", "allow", "remove"])
})

test("allowed shows revoke; processes add up or down by state", () => {
  eq(verbs(row({ allowed: true, hasProcesses: true }), {}, ALL, null), ["enter", "edit", "up", "update", "revoke", "remove"])
  eq(verbs(row({ hasProcesses: true }), {}, ALL, RUNNING), ["enter", "edit", "down", "update", "allow", "remove"])
})

test("a mutation locks everything that changes things -- except stopping", () => {
  const lock = { mutating: true }
  eq(verbs(row({ hasProcesses: true }), lock, ALL, RUNNING), ["enter", "edit", "down", "update-", "allow-", "remove-"])
  eq(verbs(row({ hasProcesses: true }), lock, ALL, null), ["enter", "edit", "up-", "update-", "allow-", "remove-"])
})

test("no devenv: only edit and remove remain", () => {
  eq(verbs(row({ hasProcesses: true }), {}, { cli: true, devenv: false }, null),
    ["enter-", "edit", "up-", "update-", "allow-", "remove"])
})

test("no CLI: remove goes too, since it is the CLI that removes", () => {
  eq(verbs(row(), {}, { cli: false, devenv: true }, null), ["enter", "edit", "update", "allow", "remove-"])
})

test("allowsVerb answers from the same table", () => {
  eq(Model.allowsVerb(row(), "update", { mutating: true }, ALL, null), false)
  eq(Model.allowsVerb(row(), "enter", { mutating: true }, ALL, null), true)
  eq(Model.allowsVerb(row(), "nonsense", {}, ALL, null), false)
})

test("dependencyText names what to install", () => {
  eq(Model.dependencyText(ALL), "")
  eq(/nix profile install/.test(Model.dependencyText({ cli: false, devenv: true })), true)
  eq(/nixarchy-service-enable devenv/.test(Model.dependencyText({ cli: true, devenv: false })), true)
})
