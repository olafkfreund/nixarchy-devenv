pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Everything the plugin knows about devenv environments, and every way it
// talks to them. Nothing here draws, and nothing here reads a project
// directory: the nixarchy-devenv CLI does that and answers in JSON.
//
// One instance for the bar and the menu (qmldir makes this a singleton), so
// that "one mutation at a time" holds across both surfaces and a log started
// in one is there to watch in the other.
Singleton {
  id: root

  // {projectRoots, refreshIntervalSec, terminalEditor}.
  // Whichever surface opened last writes it; both read the same bar entry.
  property var settings: ({})

  readonly property string hostHome: Quickshell.env("HOME") || ""
  readonly property int refreshIntervalSec: Math.max(10, Number(settings.refreshIntervalSec || 60))
  readonly property var rootsInfo: Model.rootsFor(
    settings.projectRoots === undefined ? Model.DEFAULT_ROOTS : settings.projectRoots, hostHome)
  readonly property var roots: rootsInfo.roots

  // Removal checks against these. The union of what is configured and what the
  // CLI resolved: a root on an unmounted drive drops out of canonicalRoots, and
  // it must still reach the CLI so the CLI can refuse the removal. Index loops,
  // because both sides are read through a var property and may be a Qt sequence
  // wrapper rather than a JS array.
  readonly property var guardRoots: {
    var out = []
    var i
    for (i = 0; i < (roots ? roots.length : 0); i++) out.push(roots[i])
    for (i = 0; i < (canonicalRoots ? canonicalRoots.length : 0); i++)
      if (out.indexOf(canonicalRoots[i]) === -1) out.push(canonicalRoots[i])
    return out
  }
  readonly property var editor: Model.editorWords(settings.terminalEditor, Quickshell.env("EDITOR") || "")

  // A token to prove from outside that every surface holds this one instance.
  readonly property string instanceId: Math.random().toString(36).substring(2, 10)

  // ------------------------------------------------------------ interest
  //
  // Surfaces say when they need data. A bar keeps the slow poll alive for its
  // glyph; an open view polls fast. Nothing polls when neither holds on.

  property int bars: 0
  property int views: 0
  readonly property bool background: bars > 0
  readonly property bool active: views > 0

  function acquire(kind) {
    if (kind === "bar") bars += 1
    else views += 1
  }

  function release(kind) {
    if (kind === "bar") bars = Math.max(0, bars - 1)
    else views = Math.max(0, views - 1)
  }

  // ------------------------------------------------------------ dependencies
  //
  // Probed once, on first interest, by running each command: `command -v`
  // would need a shell. Until a probe answers, assume present, so nothing
  // flashes "missing" on a machine that has everything.

  property var deps: ({ cli: true, devenv: true })
  property bool probed: false

  function probe() {
    if (root.probed) return
    root.probed = true
    cliProbe.running = true
    devenvProbe.running = true
  }

  Process {
    id: cliProbe
    command: Model.cliProbeArgv()
    onExited: function(code) {
      root.deps = { cli: code === 0, devenv: root.deps.devenv }
      if (code === 0) { root.loadTemplates(); root.refresh() }
    }
  }

  Process {
    id: devenvProbe
    command: Model.devenvProbeArgv()
    onExited: function(code) { root.deps = { cli: root.deps.cli, devenv: code === 0 } }
  }

  // ---------------------------------------------------------------- data

  property var envs: []
  // The roots as the CLI resolved them; removal checks against these.
  property var canonicalRoots: []
  property var rootMap: []
  property var warnings: []
  property var templates: []
  readonly property var counts: Model.counts(envs)

  property bool loading: false
  property bool everLoaded: false
  property string lastError: ""
  // How many list queries have run: the `status` hook reports it, so "does it
  // poll while closed" can be measured from outside rather than assumed.
  property int polls: 0

  // The selected row's process state, fetched on selection only. `statusPath`
  // names whose it is, so a late answer for another row is never shown.
  property string statusPath: ""
  property var status: null

  // ------------------------------------------------------------ the lock

  property string pendingName: ""
  readonly property string pendingText: pendingVerb + (pendingName ? " " + pendingName : "")
  property string pendingVerb: ""
  readonly property bool mutating: actionProcess.running || streamProcess.running

  // --------------------------------------------------------------- stream

  property var log: []
  property string streamTitle: ""
  property int streamExit: -1
  readonly property bool streaming: streamProcess.running

  // -------------------------------------------------------------- refresh

  function refresh() {
    if (!root.probed) { root.probe(); return }
    if (listProcess.running || !root.deps.cli) return
    var argv = Model.listArgv(root.roots)
    if (!argv) return
    root.loading = true
    root.polls += 1
    listProcess.command = argv
    listProcess.running = true
  }

  function loadTemplates() {
    if (templatesProcess.running || !root.deps.cli) return
    templatesProcess.command = Model.templatesArgv()
    templatesProcess.running = true
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.background || root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 5000
    running: root.active
    repeat: true
    onTriggered: root.refresh()
  }

  // Templates can change while the shell runs (a personal one added), so an
  // opening surface re-reads them; it is one small JSON document.
  onActiveChanged: if (active) { refresh(); loadTemplates() }
  onRootsChanged: if (root.active || root.background) refresh()

  // ------------------------------------------------------------- status

  // Debounced: walking the list with j/k should not start a devenv per row.
  function requestStatus(path) {
    if (path === root.statusPath && root.status) return
    root.statusPath = path || ""
    root.status = null
    statusDebounce.restart()
  }

  Timer {
    id: statusDebounce
    interval: 300
    onTriggered: {
      var argv = Model.statusArgv(root.statusPath)
      if (!argv || !root.deps.cli || statusProcess.running) return
      statusProcess.forPath = root.statusPath
      statusProcess.command = argv
      statusProcess.running = true
    }
  }

  function statusFor(path) {
    return path && path === root.statusPath ? root.status : null
  }

  // -------------------------------------------------------------- actions

  function clearBusyNotice() {
    if (root.lastError.indexOf("Busy: ") === 0) root.lastError = ""
  }

  function busyText() {
    if (streamProcess.running) return "Busy: " + root.streamTitle + " — press o to watch"
    return "Busy: " + root.pendingText + " — wait for it to finish"
  }

  // Only environments the CLI listed: a path that arrives by IPC or a stale
  // row never reaches a command.
  function envFor(path) {
    var env = Model.envByPath(root.envs, path)
    if (!env) root.lastError = "Not a listed environment: " + path
    return env
  }

  // Every short mutation comes through here; refused, with a reason, while
  // anything else mutates. stdin is closed so a question gets EOF, not a hang.
  // The shared door for every mutation: one at a time, and never a null argv.
  function canMutate(argv) {
    if (root.mutating) { root.lastError = root.busyText(); return false }
    if (!argv) return false
    root.lastError = ""
    return true
  }

  function run(argv, verb, name) {
    if (!canMutate(argv)) return false
    root.pendingVerb = verb
    root.pendingName = name || ""
    actionProcess.command = argv
    actionProcess.running = true
    return true
  }

  function allow(path) { var e = envFor(path); return !!e && run(Model.allowArgv(e.path), "allowing", e.name) }
  function revoke(path) { var e = envFor(path); return !!e && run(Model.revokeArgv(e.path), "revoking", e.name) }
  function up(path) { var e = envFor(path); return !!e && run(Model.upArgv(e.path), "starting processes of", e.name) }

  // Never refused by the lock: a long update elsewhere must not keep a
  // runaway process alive. Its own process, so it can run beside a mutation.
  function down(path) {
    var e = envFor(path)
    if (!e || downProcess.running) return false
    var argv = Model.downArgv(e.path)
    if (!argv) return false
    downProcess.name = e.name
    downProcess.command = argv
    downProcess.running = true
    return true
  }

  function startStream(argv, title) {
    if (!canMutate(argv)) return false
    root.streamTitle = title
    root.streamExit = -1
    root.log = ["$ " + title]
    streamProcess.command = argv
    streamProcess.running = true
    return true
  }

  function update(path) {
    var e = envFor(path)
    return !!e && startStream(Model.updateArgv(e.path), "update " + e.name)
  }

  // Not `gc`: that name is the QML engine's own garbage collector.
  function runGc() { return startStream(Model.gcArgv(root.hostHome), "devenv gc") }

  // `result` is Model.validateForm's answer; the form has already shown its
  // errors, so a not-ok result here is a no.
  function create(form, result) {
    if (!result || !result.ok) return false
    return startStream(result.argv, Model.formSummary(form))
  }

  function remove(path, tier, typedName) {
    var e = envFor(path)
    if (!e) return false
    var why = Model.removeRefusal(e, tier, root.guardRoots, root.hostHome, root.statusFor(e.path), typedName)
    if (why) { root.lastError = why; return false }
    return run(Model.removeArgv(e, tier, root.guardRoots), tier === "revoke" ? "revoking" : "removing", e.name)
  }

  function appendLog(line) {
    var next = root.log.slice()
    next.push(Model.capLine(Model.stripAnsi(line)))
    if (next.length > 2000) next.splice(0, next.length - 2000)
    root.log = next
  }

  // ----------------------------------------------------------- side effects

  // Not mutations: a terminal of its own, which the plugin never waits for.
  function enter(path) {
    var e = envFor(path)
    if (!e) return false
    if (!root.deps.devenv) { root.lastError = Model.dependencyText(root.deps); return false }
    var argv = Model.enterArgv(e.path)
    if (!argv) return false
    Quickshell.execDetached(argv)
    return true
  }

  function edit(path) {
    var e = envFor(path)
    var argv = e ? Model.editArgv(e.path, root.editor) : null
    if (!argv) return false
    Quickshell.execDetached(argv)
    return true
  }

  function copyPath(path) {
    var argv = Model.copyArgv(path)
    if (!argv || copyProcess.running) return
    copyProcess.command = argv
    copyProcess.running = true
  }

  function statusJson() {
    return JSON.stringify({
      instance: root.instanceId,
      bars: root.bars,
      views: root.views,
      polls: root.polls,
      deps: root.deps,
      roots: root.roots,
      mutating: root.mutating,
      pending: root.pendingText,
      streaming: root.streaming,
      stream: root.streamTitle,
      environments: root.envs.length,
      templates: root.templates.length,
      lastError: root.lastError
    })
  }

  // ------------------------------------------------------------ processes

  Process {
    id: listProcess
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    stderr: StdioCollector { id: listErr; waitForEnd: true }
    onExited: function(code) {
      root.loading = false
      root.everLoaded = true
      if (code !== 0) {
        root.lastError = Model.errorText(listErr.text) || ("listing failed (exit " + code + ")")
        return
      }
      var parsed = Model.parseList(listOut.text)
      if (!parsed.ok) return
      root.envs = parsed.rows
      root.canonicalRoots = parsed.roots
      root.rootMap = parsed.rootMap
      root.warnings = parsed.warnings.concat(root.rootsInfo.rejected.length
        ? ["Not a usable root: " + root.rootsInfo.rejected.join(", ")] : [])
    }
  }

  Process {
    id: templatesProcess
    stdout: StdioCollector { id: templatesOut; waitForEnd: true }
    onExited: function(code) { if (code === 0) root.templates = Model.parseTemplates(templatesOut.text) }
  }

  Process {
    id: statusProcess
    property string forPath: ""
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(code) {
      // A stale answer: the cursor moved while this ran, so ask for the row
      // it is on now.
      if (forPath !== root.statusPath) { if (root.statusPath) statusDebounce.restart(); return }
      root.status = code === 0 ? Model.parseStatus(statusOut.text) : { state: "unknown", devenv: true, processes: [] }
    }
  }

  Process {
    id: actionProcess
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(code) {
      root.clearBusyNotice()
      if (code !== 0) root.lastError = Model.errorText(actionErr.text) || (root.pendingVerb + " failed (exit " + code + ")")
      var verb = root.pendingVerb
      root.pendingVerb = ""
      root.pendingName = ""
      // Process state may have changed; ask again for the selected row.
      if (verb.indexOf("processes") !== -1) { root.status = null; if (root.active || root.background) statusDebounce.restart() }
      if (root.active || root.background) root.refresh()
    }
  }

  Process {
    id: downProcess
    property string name: ""
    stderr: StdioCollector { id: downErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.lastError = Model.errorText(downErr.text) || ("stopping " + name + " failed (exit " + code + ")")
      root.status = null
      if (root.active || root.background) statusDebounce.restart()
    }
  }

  Process {
    id: streamProcess
    stdout: SplitParser { onRead: function(line) { root.appendLog(line) } }
    stderr: SplitParser { onRead: function(line) { root.appendLog(line) } }
    onExited: function(code) {
      root.clearBusyNotice()
      root.streamExit = code
      root.appendLog("── exit " + code + " · " + (code === 0 ? "done" : "failed"))
      if (code !== 0) root.lastError = root.streamTitle + " failed (exit " + code + ") — o shows the log"
      if (root.active || root.background) root.refresh()
    }
  }

  Process { id: copyProcess }
}
