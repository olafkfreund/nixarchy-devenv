const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

function load(file) {
  const source = fs.readFileSync(path.join(__dirname, "..", file), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "")

  const before = new Set(Object.getOwnPropertyNames(globalThis))
  vm.runInThisContext(source, { filename: file })

  const namespace = {}
  for (const name of Object.getOwnPropertyNames(globalThis)) {
    if (!before.has(name)) namespace[name] = globalThis[name]
  }
  return namespace
}

const Model = load("Model.js")

let passed = 0
const failures = []

function test(name, fn) {
  try {
    fn()
    passed += 1
  } catch (error) {
    failures.push({ name: name, error: error })
  }
}

function report() {
  for (const failure of failures) {
    console.error("FAIL  " + failure.name)
    console.error("      " + String(failure.error.message).split("\n").join("\n      "))
  }
  console.log(`${passed} passed, ${failures.length} failed`)
  return failures.length === 0 ? 0 : 1
}

const HOME = "/home/user"

// One row of `nixarchy-devenv list --json`, as pkgs/cli.sh prints it.
function listRow(overrides) {
  return Object.assign({
    path: "/home/user/Source/app",
    name: "app",
    allowed: false,
    lockfile: true,
    template: "python",
    hasProcesses: false,
    dev: 2049,
    mtime: 1000
  }, overrides || {})
}

function env(overrides) {
  return Model.parseList(JSON.stringify({ rows: [listRow(overrides)], warnings: [], skipped: 0 })).rows[0]
}

// The templates index, trimmed to one of each kind.
const TEMPLATES = [
  { id: "python", kind: "preset", group: "Languages", label: "Python", note: "n" },
  { id: "flutter", kind: "preset", group: "Mobile", label: "Flutter", note: "n" },
  { id: "ml", kind: "preset", group: "Data & ML", label: "ML", note: "n" },
  { id: "cloud", kind: "generator", group: "Cloud", label: "Cloud project", note: "n",
    flake: "github:o/c", rev: "abc", providers: ["aws", "azure", "gcp"], honours_git: false, honours_allow: true },
  { id: "mine", kind: "personal", group: "Yours", label: "Mine", note: "" }
]

function templates() {
  return Model.parseTemplates(JSON.stringify(TEMPLATES))
}

// Inputs that must never reach an argv slot or a path.
const HOSTILE = [
  "", " ", "a;b", "$(id)", "`id`", "a\nb", "a\u0000b", "../x", "-rf", "--root", "a b",
  "~root/x", "x".repeat(300), "\u202Eevil", "a|b", "a&b", "a>b"
]

module.exports = {
  test: test,
  eq: assert.deepStrictEqual,
  ok: assert.ok,
  report: report,
  listRow: listRow,
  env: env,
  templates: templates,
  TEMPLATES: TEMPLATES,
  HOSTILE: HOSTILE,
  HOME: HOME,
  Model: Model
}
