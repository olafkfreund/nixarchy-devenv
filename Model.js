.pragma library

// All of the plugin's logic. No QML in here: this file runs under plain Node
// in tests/, and the QML side only draws and wires.
//
// The plugin never touches a project directory itself. Everything that reads
// or changes one goes through the nixarchy-devenv CLI (pkgs/cli.sh), whose
// JSON this file parses and whose argv it builds; the one exception is
// opening a terminal. The checks here are the fast refusal in the UI -- the
// CLI repeats every one that protects a file, right before it acts.

var Glyph = {
  env: String.fromCodePoint(0xF1105),      // nf-md-nix
  enter: String.fromCodePoint(0xF018D),
  edit: String.fromCodePoint(0xF03EB),
  play: String.fromCodePoint(0xF040A),
  stop: String.fromCodePoint(0xF04DB),
  update: String.fromCodePoint(0xF06B0),
  allow: String.fromCodePoint(0xF0565),    // shield-check
  revoke: String.fromCodePoint(0xF099D),   // shield-off
  lock: String.fromCodePoint(0xF033E),
  logs: String.fromCodePoint(0xF0219),
  copy: String.fromCodePoint(0xF018F),
  refresh: String.fromCodePoint(0xF0450),
  search: String.fromCodePoint(0xF0349),
  remove: String.fromCodePoint(0xF0A7A),
  plus: String.fromCodePoint(0xF0415),
  alert: String.fromCodePoint(0xF002A),
  close: String.fromCodePoint(0xF0156),
  keyboard: String.fromCodePoint(0xF030C),
  broom: String.fromCodePoint(0xF00E2)
}

var CLI = "nixarchy-devenv"
var MAX_FIELD = 64

// ---------------------------------------------------------------- keys
//
// The one list of what the keyboard does. The `?` sheet renders it and the
// docs quote it, so the two cannot drift apart.

var SHORTCUTS = [
  { group: "Move", keys: "j  k  ↑ ↓", text: "Move the cursor down / up" },
  { group: "Move", keys: "/", text: "Jump into the filter box" },
  { group: "Move", keys: "esc", text: "Leave the filter, then close the panel" },

  { group: "Environment", keys: "enter", text: "Enter it: devenv shell in a new terminal" },
  { group: "Environment", keys: "e", text: "Edit its devenv.nix in your editor (not for bound environments)" },
  { group: "Environment", keys: "s", text: "Start its processes (devenv up -d), or stop them" },
  { group: "Environment", keys: "p", text: "Check whether its processes are running" },
  { group: "Environment", keys: "g", text: "Update its lock (devenv update), with the log in the panel" },
  { group: "Environment", keys: "a", text: "Allow or revoke automatic activation on cd" },
  { group: "Environment", keys: "x", text: "Remove it: revoke, remove devenv's files, or delete" },
  { group: "Environment", keys: "y", text: "Copy its path" },

  { group: "All", keys: "c", text: "Create a new project from a template" },
  { group: "All", keys: "G", text: "devenv gc: old shell generations, for every project" },

  { group: "Panel", keys: "o", text: "Show the create / update log" },
  { group: "Panel", keys: "u", text: "Refresh now" },
  { group: "Panel", keys: "?", text: "Show this list" },

  { group: "Create form", keys: "tab  ↓ / shift+tab  ↑", text: "Next / previous field" },
  { group: "Create form", keys: "space", text: "Flip a switch, pick a provider" },
  { group: "Create form", keys: "enter", text: "Create the project" },
  { group: "Create form", keys: "esc", text: "Cancel" },

  { group: "Log", keys: "j  k", text: "Scroll (stops following)" },
  { group: "Log", keys: "G  end", text: "Jump to the end and follow" },
  { group: "Log", keys: "esc", text: "Back to the list; the job keeps running" }
]

function shortcutGroups() {
  var order = []
  var byGroup = {}
  for (var i = 0; i < SHORTCUTS.length; i++) {
    var entry = SHORTCUTS[i]
    if (!byGroup[entry.group]) {
      byGroup[entry.group] = []
      order.push(entry.group)
    }
    byGroup[entry.group].push({ keys: entry.keys, text: entry.text })
  }
  var out = []
  for (var g = 0; g < order.length; g++) out.push({ title: order[g], entries: byGroup[order[g]] })
  return out
}

// ---------------------------------------------------------------- text

function str(value) {
  return String(value === undefined || value === null ? "" : value)
}

function hasControlChars(value) {
  return /[\x00-\x1f\x7f-\x9f]/.test(str(value))
}

function sanitize(value, maxLength) {
  var limit = maxLength > 0 ? maxLength : MAX_FIELD
  // Bidi controls too: a name is shown to you and then typed back to confirm
  // the folder tier, so a name that can render as something other than what
  // it is defeats that check. hasControlChars stays as it is -- it gates
  // isAbsPath, and a path has to stay byte-exact to remain actionable.
  var out = str(value).replace(/[\x00-\x1f\x7f-\x9f\u202A-\u202E\u2066-\u2069]/g, "").trim()
  if (out.length > limit) out = out.substring(0, limit - 1) + "…"
  return out
}

function trim(value) {
  return str(value).replace(/^\s+|\s+$/g, "")
}

function join(parts, separator) {
  var out = []
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] !== undefined && parts[i] !== null && String(parts[i]) !== "") out.push(String(parts[i]))
  }
  return out.join(separator === undefined ? " · " : separator)
}

function plural(count, noun) {
  return count + " " + noun + (count === 1 ? "" : "s")
}

// Terminal output from devenv and nix: colour codes, cursor moves, and
// spinners that redraw themselves with \r. Keep what the last redraw left on
// the line, drop every escape sequence.
function stripAnsi(line) {
  var text = str(line)
  var cr = text.lastIndexOf("\r", text.length - 2)
  if (cr !== -1) text = text.substring(cr + 1)
  return text
    .replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/g, "")
    .replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "")
    .replace(/\x1b[@-Z\\-_]/g, "")
    .replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "")
}

var LINE_CAP = 2048

// ponytail: a line longer than 2 KB is a progress bar or a binary blob, not
// something to read; cut it rather than let one line grow the log unbounded.
function capLine(line) {
  var text = str(line)
  return text.length > LINE_CAP ? text.substring(0, LINE_CAP - 1) + "…" : text
}

// ---------------------------------------------------------------- paths

// An absolute path we are willing to put in an argv slot: no control
// characters (a newline would split a log line and fool a reader), no `.` or
// `..` segment (the CLI compares canonical paths; one that is not canonical
// is a sign something else is going on), and not so long it is a blob.
function isAbsPath(value) {
  var p = str(value)
  if (p.length < 1 || p.length > 4096 || p.charAt(0) !== "/" || hasControlChars(p)) return false
  var parts = p.split("/")
  for (var i = 1; i < parts.length; i++) {
    if (parts[i] === "." || parts[i] === "..") return false
    if (parts[i] === "" && i !== parts.length - 1) return false
  }
  return true
}

function stripSlash(p) {
  var s = str(p)
  while (s.length > 1 && s.charAt(s.length - 1) === "/") s = s.substring(0, s.length - 1)
  return s
}

// "~" and "~/x" only; "~user" is somebody else's home and is refused.
function expandHome(value, home) {
  var p = trim(value)
  var h = stripSlash(home)
  if (p === "~") return h
  if (p.indexOf("~/") === 0) return h + p.substring(1)
  return p
}

function tildePath(path, home) {
  var p = str(path)
  var h = stripSlash(home)
  if (h && h !== "/" && (p === h || p.indexOf(h + "/") === 0)) return "~" + p.substring(h.length)
  return p
}

function isAncestorOrSelf(ancestor, path) {
  var a = stripSlash(ancestor)
  var p = stripSlash(path)
  if (a === "/") return true
  return p === a || p.indexOf(a + "/") === 0
}

// The configured roots, expanded, deduped, and without anything that would
// not be safe as an argv element. What is dropped comes back in `rejected` so
// the settings problem can be said out loud rather than silently shrink the
// list.
// The setting is a string separated by ':' like PATH -- the shell's settings
// form has no list type -- but a list is accepted too.
function rootsFor(setting, home) {
  var list = typeof setting === "string" ? setting.split(":")
    : setting && typeof setting === "object" && typeof setting.length === "number" ? setting : []
  var out = []
  var rejected = []
  for (var i = 0; i < list.length; i++) {
    var raw = str(list[i])
    if (!trim(raw)) continue
    var p = stripSlash(expandHome(raw, home))
    if (!isAbsPath(p)) { rejected.push(raw); continue }
    if (out.indexOf(p) === -1) out.push(p)
  }
  return { roots: out, rejected: rejected }
}

// ---------------------------------------------------------------- parsing

function parseJson(raw) {
  try { return JSON.parse(str(raw)) } catch (e) { return null }
}

// Saved profiles of a bound environment: names only, anything else dropped.
function parseProfiles(raw) {
  var out = []
  if (!raw || typeof raw !== "object" || raw.length === undefined) return out
  for (var i = 0; i < raw.length; i++) {
    if (typeof raw[i] === "string" && /^[A-Za-z0-9._-]{1,64}$/.test(raw[i])) out.push(raw[i])
  }
  return out
}

// Bound with `devenv --from`: the configuration is not in the directory.
function isBound(env) {
  return !!env && str(env.from) !== ""
}

// `list --json`. A row missing its path is dropped; every other field has a
// safe default, so an older or newer CLI never breaks the list.
function parseList(raw) {
  var data = parseJson(raw)
  var out = { rows: [], roots: [], rootMap: [], warnings: [], skipped: 0, ok: false }
  if (!data || typeof data !== "object") return out
  out.ok = true
  var rows = data.rows && data.rows.length !== undefined ? data.rows : []
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (!r || !isAbsPath(r.path)) continue
    out.rows.push({
      path: str(r.path),
      name: sanitize(r.name || r.path.split("/").pop(), 80),
      allowed: r.allowed === true,
      lockfile: r.lockfile === true,
      template: /^[a-z0-9-]+$/.test(str(r.template)) ? str(r.template) : "custom",
      hasProcesses: r.hasProcesses === true,
      ident: typeof r.ident === "string" && /^[0-9]+:[0-9]+$/.test(r.ident) ? r.ident : "",
      mtime: typeof r.mtime === "number" ? r.mtime : 0,
      from: sanitize(r.from, 200),
      profiles: parseProfiles(r.profiles)
    })
  }
  // The roots as the CLI resolved them (~/Source may be a symlink). Removal
  // compares canonical rows against these, never against the raw setting.
  var roots = data.roots && data.roots.length !== undefined ? data.roots : []
  for (var k = 0; k < roots.length; k++) if (isAbsPath(roots[k])) out.roots.push(stripSlash(roots[k]))
  var map = data.rootMap && data.rootMap.length !== undefined ? data.rootMap : []
  for (var m = 0; m < map.length; m++) {
    if (map[m] && isAbsPath(map[m].given) && isAbsPath(map[m].canonical))
      out.rootMap.push({ given: stripSlash(map[m].given), canonical: stripSlash(map[m].canonical) })
  }
  var warnings = data.warnings && data.warnings.length !== undefined ? data.warnings : []
  for (var w = 0; w < warnings.length; w++) out.warnings.push(sanitize(warnings[w], 200))
  out.skipped = typeof data.skipped === "number" ? data.skipped : 0
  return out
}

var GROUP_ORDER = ["Languages", "Data & ML", "Mobile", "Cloud", "Yours"]

function parseTemplates(raw) {
  var data = parseJson(raw)
  var out = []
  if (!data || data.length === undefined) return out
  for (var i = 0; i < data.length; i++) {
    var t = data[i]
    if (!t || !/^[a-z0-9-]+$/.test(str(t.id))) continue
    var kind = t.kind === "generator" || t.kind === "personal" ? t.kind : "preset"
    var providers = []
    if (kind === "generator" && t.providers && t.providers.length !== undefined) {
      for (var p = 0; p < t.providers.length; p++) {
        if (/^[a-z0-9-]+$/.test(str(t.providers[p]))) providers.push(str(t.providers[p]))
      }
    }
    out.push({
      id: str(t.id),
      kind: kind,
      group: sanitize(t.group || (kind === "personal" ? "Yours" : "Languages"), 40),
      label: sanitize(t.label || t.id, 60),
      note: sanitize(t.note, 400),
      providers: providers,
      honoursGit: kind !== "generator" || t.honours_git !== false,
      honoursAllow: kind !== "generator" || t.honours_allow !== false
    })
  }
  return out
}

// The first item whose `field` is `value`, or null.
function findBy(list, field, value) {
  var l = list || []
  for (var i = 0; i < l.length; i++) if (l[i][field] === value) return l[i]
  return null
}

function templateById(templates, id) { return findBy(templates, "id", id) }

// The picker's sections, in a fixed order; a group we do not know comes last
// rather than disappearing.
function templateGroups(templates) {
  var list = templates || []
  var order = GROUP_ORDER.slice()
  var by = {}
  for (var i = 0; i < list.length; i++) {
    var g = list[i].group
    if (!by[g]) by[g] = []
    by[g].push(list[i])
    if (order.indexOf(g) === -1) order.push(g)
  }
  var out = []
  for (var o = 0; o < order.length; o++) if (by[order[o]]) out.push({ title: order[o], templates: by[order[o]] })
  return out
}

// The flat order the picker's cursor walks, groups included.
// The form's template list: every group in order, narrowed by what was typed.
function templateChoices(templates, filter) {
  var q = str(filter).toLowerCase()
  var groups = templateGroups(templates)
  var out = []
  for (var g = 0; g < groups.length; g++) {
    for (var t = 0; t < groups[g].templates.length; t++) {
      var tpl = groups[g].templates[t]
      if (!q || (tpl.id + " " + tpl.label + " " + tpl.group).toLowerCase().indexOf(q) !== -1) out.push(tpl)
    }
  }
  return out
}

// `status --json`: running | stopped | unknown. Anything else is unknown.
function parseStatus(raw) {
  var data = parseJson(raw)
  var state = data && (data.state === "running" || data.state === "stopped") ? data.state : "unknown"
  var processes = []
  if (data && data.processes && data.processes.length !== undefined) {
    for (var i = 0; i < data.processes.length; i++) {
      var p = data.processes[i]
      if (p && p.name) processes.push({ name: sanitize(p.name, 60), status: sanitize(p.status, 30) })
    }
  }
  return { state: state, devenv: !(data && data.devenv === false), processes: processes }
}

function statusText(status) {
  if (!status) return ""
  if (status.state === "running") {
    var names = Array.prototype.map.call(status.processes, function(p) { return p.name })
    return "running" + (names.length ? ": " + names.join(", ") : "")
  }
  if (status.state === "stopped") return "no processes running"
  return status.devenv === false ? "unknown (devenv missing)" : "unknown"
}

// ---------------------------------------------------------------- rows

function envByPath(envs, path) { return findBy(envs, "path", path) }

// Allowed ones first (those are the projects you use), then the most
// recently edited devenv.nix, then name.
function compareEnvs(a, b) {
  if (a.allowed !== b.allowed) return a.allowed ? -1 : 1
  if (a.mtime !== b.mtime) return b.mtime - a.mtime
  return a.name < b.name ? -1 : a.name > b.name ? 1 : 0
}

function sortEnvs(envs) {
  return (envs || []).slice().sort(compareEnvs)
}

function filterEnvs(envs, query) {
  var q = trim(query).toLowerCase()
  if (!q) return (envs || []).slice()
  var out = []
  var list = envs || []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if ((e.name + " " + e.path + " " + e.template + " " + str(e.from)).toLowerCase().indexOf(q) !== -1) out.push(e)
  }
  return out
}

var ROW_FIELDS = ["name", "subtitle", "template", "detail", "path", "allowed", "lockfile", "hasProcesses", "bound"]
var ROW_BOOLEANS = ["allowed", "lockfile", "hasProcesses", "bound"]

// A ListModel takes its role types from the first object it is handed and
// drops any field it cannot type, so hand it a fresh plain object with every
// field present and explicitly typed.
function rowRecord(row) {
  var out = { key: str(row.key) }
  for (var i = 0; i < ROW_FIELDS.length; i++) {
    var field = ROW_FIELDS[i]
    out[field] = ROW_BOOLEANS.indexOf(field) !== -1 ? row[field] === true : str(row[field])
  }
  return out
}

// A canonical path shown the way you configured its root: with ~/Source a
// symlink to /mnt/data/Source-home, a row there reads ~/Source/..., not the
// mount. Display only -- every command still gets the canonical path.
function displayPath(path, rootMap, home) {
  var p = str(path)
  var map = rootMap || []
  for (var i = 0; i < map.length; i++) {
    var c = map[i].canonical
    if (c !== "/" && (p === c || p.indexOf(c + "/") === 0)) { p = map[i].given + p.substring(c.length); break }
  }
  return tildePath(p, home)
}

// The caption's middle part: the template, or where a bound one comes from.
function detailText(env) {
  if (!isBound(env)) return str(env && env.template)
  var profiles = Array.prototype.slice.call(env.profiles || []).join(", ")
  return join(["from " + str(env.from), profiles ? "profiles " + profiles : ""])
}

function rowsFor(envs, home, rootMap) {
  var out = []
  var sorted = sortEnvs(envs)
  for (var i = 0; i < sorted.length; i++) {
    var e = sorted[i]
    var parent = e.path.substring(0, e.path.lastIndexOf("/")) || "/"
    out.push({
      key: e.path,
      name: e.name,
      subtitle: displayPath(parent, rootMap, home),
      template: e.template,
      detail: detailText(e),
      path: e.path,
      allowed: e.allowed,
      lockfile: e.lockfile,
      hasProcesses: e.hasProcesses,
      bound: isBound(e)
    })
  }
  return out
}

function clampCursor(cursorIndex, total) {
  if (total <= 0) return 0
  if (cursorIndex < 0) return 0
  if (cursorIndex > total - 1) return total - 1
  return cursorIndex
}

// Where the cursor belongs after the rows changed: on the same environment if
// it is still listed, otherwise on the same row number, clamped. The list
// re-sorts (allowed first, newest first) on every refresh.
function cursorAfter(prevKey, rows, prevIndex) {
  var next = rows || []
  if (prevKey) {
    for (var i = 0; i < next.length; i++) if (next[i].key === prevKey) return i
  }
  return clampCursor(prevIndex, next.length)
}

// The smallest list of ListModel operations that turns currentKeys into the
// keys of nextRows, so rows the cursor is on are moved rather than rebuilt.
function reconcilePlan(currentKeys, nextRows) {
  var keys = (currentKeys || []).slice()
  var next = nextRows || []
  var ops = []
  var wanted = {}
  for (var i = 0; i < next.length; i++) wanted[next[i].key] = true
  for (var r = keys.length - 1; r >= 0; r--) {
    if (wanted[keys[r]]) continue
    ops.push({ op: "remove", index: r })
    keys.splice(r, 1)
  }
  for (var n = 0; n < next.length; n++) {
    if (keys[n] === next[n].key) continue
    var found = keys.indexOf(next[n].key, n)
    if (found > n) {
      ops.push({ op: "move", from: found, to: n })
      keys.splice(n, 0, keys.splice(found, 1)[0])
    } else {
      ops.push({ op: "insert", index: n, row: next[n] })
      keys.splice(n, 0, next[n].key)
    }
  }
  return ops
}

// ---------------------------------------------------------------- summaries

function counts(envs) {
  var list = envs || []
  var out = { total: list.length, allowed: 0 }
  for (var i = 0; i < list.length; i++) if (list[i].allowed) out.allowed++
  return out
}

function summaryText(envs, deps) {
  if (deps && deps.cli === false) return "nixarchy-devenv missing"
  var c = counts(envs)
  if (c.total === 0) return "No environments"
  return plural(c.total, "environment") + " · " + c.allowed + " allowed"
}

function footerText(envs) {
  var c = counts(envs)
  return plural(c.total, "environment") + " · " + c.allowed + " auto-activate"
}

function emptyText(state) {
  if (state.cli === false) return "The nixarchy-devenv command is not installed"
  if (!state.everLoaded) return "Loading…"
  if (state.filtered) return "Nothing matches that filter"
  return "No devenv environments under your project roots — press c to create one"
}

// What to install when a dependency is missing. The plugin can be added with
// `omarchy plugin add`, which clones and builds nothing, so the CLI may not
// exist at all.
function dependencyText(deps) {
  if (deps && deps.cli === false) {
    return "Install the nixarchy-devenv command: on nixarchy it comes with the plugin; " +
      "elsewhere, nix profile install github:olafkfreund/nixarchy-devenv#cli"
  }
  if (deps && deps.devenv === false) {
    return "devenv is not installed, so create, enter and processes are off. " +
      "On nixarchy: nixarchy-service-enable devenv && nixarchy apply"
  }
  return ""
}

// The CLI prefixes its own messages with "nixarchy-devenv:"; the last one is
// the reason. Otherwise the last meaningful line, which is where devenv and
// nix put theirs.
function errorText(raw) {
  var lines = str(raw).split("\n")
  var ours = ""
  var last = ""
  for (var i = 0; i < lines.length; i++) {
    var line = trim(stripAnsi(lines[i])).replace(/^[×x]\s+/, "")
    if (!line) continue
    last = line
    if (line.indexOf("nixarchy-devenv: ") === 0) ours = line.substring("nixarchy-devenv: ".length)
  }
  return sanitize(ours || last, 200)
}

// ---------------------------------------------------------------- settings

// The menu entry point is not a bar widget, so it has no setting(). It reads
// the widget's entry out of the bar layout instead: `bar.layout.<region>[]`,
// where an entry is either a bare id or {id, ...settings}. Only keys the
// defaults know about, carrying the same type, get through.
function settingsFor(barConfig, id, defaults) {
  var result = {}
  for (var key in defaults) result[key] = defaults[key]
  if (!barConfig || typeof barConfig !== "object") return result
  var layout = barConfig.layout && typeof barConfig.layout === "object" ? barConfig.layout : barConfig
  var regions = ["left", "center", "right"]
  for (var r = 0; r < regions.length; r++) {
    // Not Array.isArray: read through a QObject property, the layout's lists
    // are Qt sequence wrappers, which have a length but are not JS arrays.
    var list = layout[regions[r]]
    var entries = list && typeof list === "object" && typeof list.length === "number" ? list : []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (!entry || typeof entry !== "object" || entry.id !== id) continue
      for (var k in result) {
        if (k in entry && typeof entry[k] === typeof result[k]) result[k] = entry[k]
      }
      return result
    }
  }
  return result
}

var DEFAULT_ROOTS = "~/Source:~/Projects"

// ---------------------------------------------------------------- editor

var EDITOR_WORD = /^[A-Za-z0-9_.\/+=:,@%-]+$/

// $EDITOR may carry arguments ("code --wait"). Split on whitespace -- no shell,
// no quotes -- and allow only plain words, the first of which must be a
// command rather than an option. Anything else falls back to nvim.
function editorWords(setting, envEditor) {
  var candidates = [trim(setting), trim(envEditor)]
  for (var c = 0; c < candidates.length; c++) {
    if (!candidates[c] || hasControlChars(candidates[c])) continue
    var words = candidates[c].split(/\s+/)
    var ok = words.length <= 8 && words[0].charAt(0) !== "-"
    for (var i = 0; ok && i < words.length; i++) if (!EDITOR_WORD.test(words[i])) ok = false
    if (ok) return words
  }
  return ["nvim"]
}

// ---------------------------------------------------------------- commands
//
// Argv arrays only. Each returns null when an input would not be safe in its
// slot, and the caller does nothing. `env -C DIR` sets the working directory
// without a shell: omarchy-launch-tui goes through setsid, uwsm-app and
// xdg-terminal-exec, and nothing promises a working directory survives that.

function inDir(path, argv) {
  if (!isAbsPath(path)) return null
  return ["env", "-C", str(path)].concat(argv)
}

// ["--root", r, ...] for every root, or null if any is not a safe absolute path.
function rootArgs(roots) {
  var list = roots || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (!isAbsPath(list[i])) return null
    out.push("--root", str(list[i]))
  }
  return out
}

function listArgv(roots) {
  var r = rootArgs(roots)
  return r ? [CLI, "list", "--json"].concat(r) : null
}

function templatesArgv() { return [CLI, "templates", "--json"] }
function cliProbeArgv() { return [CLI, "help"] }
function devenvProbeArgv() { return ["devenv", "version"] }

function statusArgv(path) {
  if (!isAbsPath(path)) return null
  return [CLI, "status", "--json", str(path)]
}

function enterArgv(path) {
  var inner = inDir(path, ["devenv", "shell"])
  return inner ? ["omarchy-launch-tui", "--app-id=org.omarchy.devenv-enter"].concat(inner) : null
}

function editArgv(path, words) {
  var editor = words && words.length ? words : ["nvim"]
  var inner = inDir(path, editor.concat(["devenv.nix"]))
  return inner ? ["omarchy-launch-tui", "--app-id=org.omarchy.devenv-edit"].concat(inner) : null
}

// -d: the lock is held only while the process manager starts, never for as
// long as the processes run, so Stop is always reachable.
function upArgv(path) { return inDir(path, ["devenv", "up", "-d"]) }
function downArgv(path) { return inDir(path, ["devenv", "processes", "down"]) }
function updateArgv(path) { return inDir(path, ["devenv", "update"]) }
function allowArgv(path) { return inDir(path, ["devenv", "allow"]) }
function revokeArgv(path) { return inDir(path, ["devenv", "revoke"]) }

// Not a project action: devenv gc removes old shell generations for the
// user, across every project. Run from HOME so it is plainly not "this one".
function gcArgv(home) { return inDir(stripSlash(home), ["devenv", "gc"]) }

function copyArgv(path) {
  if (!isAbsPath(path)) return null
  return ["wl-copy", "--trim-newline", "--", str(path)]
}

// ---------------------------------------------------------------- create form

var NAME = /^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$/

// {name, parent, template, providers[], git, allow} → {ok, errors{field}, argv}.
// The CLI checks every one of these again; this is the fast answer in the form.
function validateForm(form, templates, home) {
  var f = form || {}
  var errors = {}
  var name = trim(f.name)
  if (!name) errors.name = "Give the project a name"
  else if (!NAME.test(name)) errors.name = "Letters, digits, '.', '_' and '-', starting with a letter, digit or '_'"

  var parentRaw = trim(f.parent)
  var parent = stripSlash(expandHome(parentRaw, home))
  if (!parentRaw) errors.parent = "Pick where it goes"
  else if (parentRaw.charAt(0) === "~" && parentRaw !== "~" && parentRaw.indexOf("~/") !== 0) errors.parent = "Only your own ~ is expanded"
  else if (!isAbsPath(parent)) errors.parent = "An absolute path, or one starting with ~"

  var t = templateById(templates, str(f.template))
  var providers = []
  if (!t) errors.template = "Pick a template"
  else if (t.kind === "generator") {
    var picked = f.providers && f.providers.length !== undefined ? f.providers : []
    for (var i = 0; i < picked.length; i++) {
      var p = str(picked[i])
      if (t.providers.indexOf(p) === -1) { errors.providers = "Not a provider of " + t.label + ": " + sanitize(p, 20); break }
      if (providers.indexOf(p) === -1) providers.push(p)
    }
    if (!errors.providers && providers.length === 0) errors.providers = "Pick at least one provider"
  }

  var git = f.git !== false
  if (t && !t.honoursGit) git = true

  var ok = true
  for (var k in errors) ok = false
  if (!ok) return { ok: false, errors: errors, argv: null }

  var argv = [CLI, "new"]
  if (f.allow === true) argv.push("--allow")
  if (!git) argv.push("--no-git")
  argv.push("--parent", parent, "--name", name, t.id)
  return { ok: true, errors: {}, argv: argv.concat(providers), path: parent + "/" + name }
}

// A fresh form: a python project in the first root, git on, allow off.
function emptyForm(roots, home) {
  var list = roots || []
  return {
    name: "",
    parent: list.length ? tildePath(list[0], home) : "~",
    template: "python",
    providers: [],
    git: true,
    allow: false
  }
}

// The rows the form shows, in order. Providers only for a generator.
function formFields(templates, templateId) {
  var t = templateById(templates, templateId)
  var out = [
    { key: "name", kind: "text", label: "Name", hint: "my-app" },
    { key: "parent", kind: "text", label: "Create it in", hint: "~/Source" },
    { key: "template", kind: "template", label: "Template" }
  ]
  if (t && t.kind === "generator") out.push({ key: "providers", kind: "providers", label: "Providers" })
  out.push({ key: "git", kind: "bool", label: "git init",
    hint: t && !t.honoursGit ? "This template always runs git init" : "A new repository, unless it is already inside one",
    locked: !!(t && !t.honoursGit) })
  out.push({ key: "allow", kind: "bool", label: "Allow automatic activation",
    hint: "Runs devenv allow: the environment activates when you cd in. Off: use devenv shell." })
  return out
}

function firstErrorIndex(fields, errors) {
  for (var i = 0; i < fields.length; i++) if (errors[fields[i].key]) return i
  return -1
}

function toggleProvider(list, provider) {
  var out = Array.prototype.slice.call(list || [])
  var at = out.indexOf(provider)
  if (at === -1) out.push(provider)
  else out.splice(at, 1)
  return out
}

function formSummary(form) {
  var f = form || {}
  return "create " + sanitize(f.name, 40) + " (" + sanitize(f.template, 20) +
    (f.providers && f.providers.length ? ": " + Array.prototype.slice.call(f.providers).join(" ") : "") + ")"
}

// ---------------------------------------------------------------- removal
//
// Four answers to "take this away", least destructive first. The CLI
// re-checks every refusal below right before it deletes; these exist so the
// dialog can say no before asking anything.

var TIERS = [
  { id: "revoke", label: "Revoke", text: "Stop it activating on cd. Nothing is deleted." },
  { id: "files", label: "Remove devenv files", text: "Delete devenv.nix, devenv.yaml, devenv.lock and .devenv, keeping .devenv/state (databases live there) and your code." },
  { id: "state", label: "Remove files and state", text: "The above, and .devenv/state too: service data such as databases is gone. Your code stays." },
  { id: "folder", label: "Delete the folder", text: "Delete the whole project folder, code included. Type its name to confirm." }
]

// A bound environment has nothing of its own to delete: revoke only, and the
// chooser draws each tier's `text`, so revoke says what else it forgets.
function tiersFor(env) {
  if (!isBound(env)) return TIERS
  return [{ id: "revoke", label: TIERS[0].label, text: boundRevokeText(env) }]
}

function boundRevokeText(env) {
  return "Forgets that it is bound to " + sanitize(env.from, 120) +
    ", and its saved profiles. Nothing is deleted. It leaves this list: without the binding devenv sees no environment here."
}

function tierById(id) { return findBy(TIERS, "id", id) }

// "" when removing is allowed, otherwise the reason. `status` is the parsed
// status of this environment; unknown blocks, because a running database
// would lose its files underneath it.
function removeRefusal(env, tier, roots, home, status, typedName) {
  if (!env || !isAbsPath(env.path)) return "No environment selected"
  var t = tierById(tier)
  if (!t) return "Pick what to remove"
  if (t.id === "revoke") return ""
  if (isBound(env)) return "Bound to " + sanitize(env.from, 80) + ": nothing here to remove; revoke forgets the binding"
  var p = stripSlash(env.path)
  if (p === "/") return "Refusing to touch /"
  if (p === stripSlash(home)) return "Refusing to touch your home directory"
  var list = roots || []
  if (!list.length) return "No project roots are configured; fix projectRoots and refresh"
  for (var i = 0; i < list.length; i++) {
    if (isAncestorOrSelf(p, list[i])) return p + " is a project root, or contains one"
  }
  if (!env.ident) return "Refresh the list first"
  if (!status || status.devenv !== false) {
    if (!status || status.state === "unknown") return "Could not tell whether its processes are running (p checks)"
    if (status.state === "running") return "Its processes are running; stop them first (s)"
  }
  if (t.id === "folder" && trim(typedName) !== env.name) return "Type the folder name, " + env.name + ", to confirm"
  return ""
}

function removeArgv(env, tier, roots) {
  var t = tierById(tier)
  if (!env || !t || !isAbsPath(env.path)) return null
  if (t.id === "revoke") return revokeArgv(env.path)
  if (!env.ident || !/^[0-9]+:[0-9]+$/.test(env.ident)) return null
  var r = rootArgs(roots)
  // The root guard lives in the CLI; never call it disarmed. An empty list is
  // a truthy [], so the length is the part that matters.
  if (!r || !r.length) return null
  return [CLI, "remove", "--tier", t.id, "--confirm", str(env.path), "--ident", str(env.ident)].concat(r, [str(env.path)])
}

function gcMessage() {
  return "Run devenv gc? It deletes old devenv shell generations for your user, across every project, not just this one."
}

// ---------------------------------------------------------------- row actions

function action(verb, glyph, tooltip, danger, enabled) {
  return { verb: verb, glyph: glyph, tooltip: tooltip, danger: danger === true, enabled: enabled !== false }
}

// `lock` is {mutating}; `deps` is {cli, devenv}; `status` is the selected
// row's parsed status or null (not checked). Stop is never locked out: a
// long update elsewhere must not keep a runaway process alive.
function actionsFor(row, lock, deps, status) {
  if (!row) return []
  var free = !(lock && lock.mutating)
  var cli = !(deps && deps.cli === false)
  var devenv = !(deps && deps.devenv === false)
  var out = [
    action("enter", Glyph.enter, "Enter: devenv shell  (enter)", false, devenv)
  ]
  // A bound environment's devenv.nix is not here to edit.
  if (!row.bound) out.push(action("edit", Glyph.edit, "Edit devenv.nix  (e)", false, true))
  if (row.hasProcesses) {
    if (status && status.state === "running") out.push(action("down", Glyph.stop, "Stop processes  (s)", true, devenv))
    else out.push(action("up", Glyph.play, "Start processes  (s)", false, devenv && free))
  }
  out.push(action("update", Glyph.update, "Update the lock  (g)", false, devenv && free))
  out.push(row.allowed
    ? action("revoke", Glyph.revoke, "Revoke automatic activation  (a)", false, devenv && free)
    : action("allow", Glyph.allow, "Allow automatic activation  (a)", false, devenv && free))
  out.push(action("remove", Glyph.remove, "Remove  (x)", true, cli && free))
  return out
}

function allowsVerb(row, verb, lock, deps, status) {
  var actions = actionsFor(row, lock, deps, status)
  for (var i = 0; i < actions.length; i++) if (actions[i].verb === verb) return actions[i].enabled
  return false
}
