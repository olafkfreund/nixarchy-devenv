import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Everything you can press: the list, the filter, the questions, and the
// create form and log once they are open. It draws the DevenvState singleton,
// so the bar popup and the full-screen menu share every key.
FocusScope {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.5)

  // KeyboardPanel focuses this directly: handing it the FocusScope instead
  // would restore whichever child held focus last, stale filter field included.
  readonly property alias keyTarget: keyCatcher

  implicitHeight: column.implicitHeight

  signal closeRequested()
  signal switchPanelRequested(int direction)

  // ------------------------------------------------------------------ state

  // list | form | log. The form and the log own the keyboard while open.
  property string mode: "list"

  property string filterText: ""

  property var confirmAction: null
  property string confirmMessage: ""
  property string confirmLabel: "Confirm"
  property bool confirmOpen: false
  property bool helpOpen: false

  property int cursorIndex: 0
  // The environment the cursor is on, remembered separately from the row
  // number: the list re-sorts on every refresh, so the row it sits in changes
  // under the cursor. Not a binding: a binding would follow the wrong one.
  property string cursorKey: ""
  property bool cursorActive: false
  property bool cursorFromKeyboard: false

  // ------------------------------------------------------------- derivation

  readonly property var visibleEnvs: Model.filterEnvs(DevenvState.envs, filterText)
  readonly property var rows: Model.rowsFor(visibleEnvs, DevenvState.hostHome)
  readonly property var cursorRow: cursorIndex >= 0 && cursorIndex < rows.length ? rows[cursorIndex] : null
  readonly property var cursorEnv: cursorRow ? Model.envByPath(DevenvState.envs, cursorRow.path) : null
  readonly property var lock: ({ mutating: DevenvState.mutating })

  onRowsChanged: root.rememberCursor(Model.cursorAfter(root.cursorActive ? root.cursorKey : "", root.rows, root.cursorIndex))

  // Process state is fetched for the row under the cursor only, and only for
  // an environment that has processes to be running.
  onCursorKeyChanged: {
    var env = Model.envByPath(DevenvState.envs, root.cursorKey)
    DevenvState.requestStatus(env && env.hasProcesses ? env.path : "")
  }

  // Every change of the cursor comes through here, so the row number and the
  // remembered environment never disagree.
  function rememberCursor(index) {
    root.cursorIndex = Model.clampCursor(index, root.rows.length)
    root.cursorKey = root.cursorActive && root.rows.length > 0 ? root.rows[root.cursorIndex].key : ""
  }

  // ------------------------------------------------------------ lifecycle

  // Called every time the surface opens: fresh cursor, empty filter, back to
  // the list. Never touches the stream or its log: a create in flight survives
  // any number of closes.
  function reset() {
    mode = "list"
    cursorActive = false
    cursorKey = ""
    filterText = ""
    filterField.text = ""
    rememberCursor(0)
    filterField.focus = false
    DevenvState.lastError = ""
    helpOpen = false
    closeConfirm()
    Qt.callLater(root.focusForMode)
  }

  // Deferred, and decided by the mode at the time it runs, so an open that
  // lands straight in the form (IPC create) keeps the form's focus.
  function focusForMode() {
    if (root.mode === "log") logView.forceActiveFocus()
    else if (root.mode === "form") createForm.focusCurrent()
    else keyCatcher.forceActiveFocus()
  }

  function setMode(next) {
    root.mode = next
    root.helpOpen = false
    Qt.callLater(root.focusForMode)
  }

  // c, IPC create, or the menu's {"create":true}.
  function openForm() {
    root.mode = "form"
    root.helpOpen = false
    createForm.start()
  }

  function submitForm(form, result) {
    if (DevenvState.create(form, result)) setMode("log")
    // Refused (another job holds the lock): the reason is in the error line
    // on the list, so go and show it.
    else setMode("list")
  }

  // o: back to whatever the last create or upgrade printed.
  function openLog() {
    if (DevenvState.log.length === 0) return
    setMode("log")
  }

  // IPC and the menu's {"path": …}: put the cursor on that environment.
  function selectPath(path) {
    root.filterText = ""
    filterField.text = ""
    root.cursorActive = true
    root.cursorFromKeyboard = true
    root.cursorKey = String(path || "")
    root.rememberCursor(Model.cursorAfter(root.cursorKey, root.rows, 0))
  }

  // Called when the surface closes.
  function dismiss() {
    helpOpen = false
    closeConfirm()
  }

  // --------------------------------------------------------------- actions

  // Every row button and key ends up here, so this is the one place a verb
  // turns into something that happens.
  function dispatch(path, verb) {
    var env = Model.envByPath(DevenvState.envs, path)
    if (!env) return
    var row = Model.rowsFor([env], DevenvState.hostHome)[0]
    var status = DevenvState.statusFor(env.path)
    if (verb === "copy") { DevenvState.copyPath(path); return }
    if (verb === "remove") { askRemove(env); return }
    if (!Model.allowsVerb(row, verb, root.lock, DevenvState.deps, status)) {
      if (DevenvState.mutating) DevenvState.lastError = DevenvState.busyText()
      else DevenvState.lastError = Model.dependencyText(DevenvState.deps) || ""
      return
    }
    if (verb === "enter") { if (DevenvState.enter(path)) root.closeRequested() }
    else if (verb === "edit") { if (DevenvState.edit(path)) root.closeRequested() }
    else if (verb === "update") { if (DevenvState.update(path)) setMode("log") }
    else if (verb === "up") DevenvState.up(path)
    else if (verb === "down") DevenvState.down(path)
    else if (verb === "allow") DevenvState.allow(path)
    else if (verb === "revoke") DevenvState.revoke(path)
  }

  // s: start or stop, by what the status fetch said.
  function toggleAtCursor() {
    if (!cursorActive || !cursorEnv || !cursorEnv.hasProcesses) return
    var status = DevenvState.statusFor(cursorEnv.path)
    dispatch(cursorEnv.path, status && status.state === "running" ? "down" : "up")
  }

  // ---------------------------------------------------------- confirmation

  function ask(action, message, label) {
    root.confirmAction = action
    root.confirmMessage = message
    root.confirmLabel = label
    // Cancel is the default answer to every question asked here. The shell's
    // ConfirmDialog would otherwise default to its confirm button.
    confirmDialog.selectedIndex = 0
    root.confirmOpen = true
  }

  // Removal arrives with plan step 13 (its own review point). Until then x
  // offers revoke only, which deletes nothing.
  function askRemove(env) {
    if (DevenvState.mutating) { DevenvState.lastError = DevenvState.busyText(); return }
    var path = env.path
    ask(function() { DevenvState.remove(path, "revoke", "") }, Model.removeMessage(env, "revoke", DevenvState.hostHome), "Revoke")
  }

  function askGc() {
    if (DevenvState.mutating) { DevenvState.lastError = DevenvState.busyText(); return }
    if (!DevenvState.deps.devenv) { DevenvState.lastError = Model.dependencyText(DevenvState.deps); return }
    ask(function() { if (DevenvState.runGc()) root.setMode("log") }, Model.gcMessage(), "Run gc")
  }

  function closeConfirm() {
    root.confirmOpen = false
    root.confirmAction = null
  }

  function confirmAccepted() {
    var action = root.confirmAction
    closeConfirm()
    if (action) action()
  }

  // -------------------------------------------------------------- keyboard

  function moveCursor(delta) {
    // Up from the first row lands in the filter, the mirror of the Down key
    // that walks out of it.
    if (delta < 0 && cursorActive && cursorIndex === 0) {
      filterField.forceActiveFocus()
      cursorActive = false
      cursorKey = ""
      return
    }
    if (rows.length === 0) {
      filterField.forceActiveFocus()
      return
    }
    cursorActive = true
    cursorFromKeyboard = true
    rememberCursor(cursorIndex + delta)
  }

  // Hover names the environment, not a row: while the list reconciles, a row number can
  // briefly point at a different one. One no longer listed is ignored.
  function setCursorKey(key) {
    var index = -1
    for (var i = 0; i < rows.length; i++) if (rows[i].key === key) { index = i; break }
    if (index === -1) return
    cursorActive = true
    cursorFromKeyboard = false
    rememberCursor(index)
  }

  function handleTextKey(key) {
    if (key === "?") { root.helpOpen = !root.helpOpen; return }
    if (root.helpOpen) { root.helpOpen = false; return }
    if (key === "/") { filterField.forceActiveFocus(); return }
    if (key === "u") { DevenvState.refresh(); return }
    if (key === "G") { askGc(); return }
    if (key === "o") { openLog(); return }
    if (key === "c") { openForm(); return }

    if (!cursorActive || !cursorEnv) return
    var path = cursorEnv.path
    if (key === "e") dispatch(path, "edit")
    else if (key === "s") toggleAtCursor()
    else if (key === "p") { DevenvState.statusPath = ""; DevenvState.requestStatus(path) }
    else if (key === "g") dispatch(path, "update")
    else if (key === "a") dispatch(path, cursorEnv.allowed ? "revoke" : "allow")
    else if (key === "y") dispatch(path, "copy")
    else if (key === "x") dispatch(path, "remove")
  }

  // ----------------------------------------------------------------- view

  // The confirmation lives outside PanelKeyCatcher on purpose: the catcher
  // goes `blocked` while a question is open, so the unhandled key bubbles
  // out to here and the dialog answers it.
  Item {
    id: keyRoot
    anchors.fill: parent

    Keys.onPressed: function(event) {
      if (!root.confirmOpen) return
      if (confirmDialog.handleKey(event)) event.accepted = true
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: filterField.activeFocus || root.confirmOpen || root.mode !== "list"

      // KeyboardPanel focuses this catcher when the popup opens, on its own
      // schedule. Outside the list, send the keyboard on to whatever owns it,
      // so an IPC create that opens straight into the form keeps the form.
      onActiveFocusChanged: if (activeFocus && root.mode !== "list") Qt.callLater(root.focusForMode)

      onMoveRequested: function(dx, dy) {
        if (root.helpOpen) { if (dy !== 0) helpSheet.scroll(dy); return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: {
        if (root.helpOpen) root.helpOpen = false
        else if (root.cursorActive && root.cursorEnv) root.dispatch(root.cursorEnv.path, "enter")
      }
      onDeleteRequested: if (!root.helpOpen && root.cursorActive && root.cursorEnv) root.dispatch(root.cursorEnv.path, "remove")
      onCloseRequested: {
        if (root.helpOpen) root.helpOpen = false
        else root.closeRequested()
      }
      onTabRequested: function(direction) { root.switchPanelRequested(direction) }
      onTextKey: function(text) { root.handleTextKey(text) }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.spacing.panelGap

        PanelHero {
          title: "Dev environments"
          meta: Model.summaryText(DevenvState.envs, DevenvState.deps)
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: DevenvState.counts.total > 0 ? 1.0 : 0.5

          iconComponent: Text {
            text: Model.Glyph.env
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          trailingControl: Row {
            spacing: Style.spacing.sm

            PanelActionButton {
              iconText: Model.Glyph.keyboard
              tooltipText: "Keyboard shortcuts  (?)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.helpOpen = !root.helpOpen
            }

            PanelActionButton {
              iconText: Model.Glyph.refresh
              tooltipText: "Refresh  (u)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: DevenvState.refresh()

              RotationAnimation on rotation {
                running: DevenvState.loading
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
                onRunningChanged: if (!running) rotation = 0
              }
            }

            PanelActionButton {
              enabled: DevenvState.deps.cli
              iconText: Model.Glyph.plus
              tooltipText: "New project  (c)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.openForm()
            }
          }
        }

        CreateForm {
          id: createForm
          visible: root.mode === "form"
          width: parent.width
          height: visible ? implicitHeight : 0
          templates: DevenvState.templates
          roots: DevenvState.roots
          home: DevenvState.hostHome
          foreground: root.foreground
          fontFamily: root.fontFamily
          onSubmitted: function(form, result) { root.submitForm(form, result) }
          onCanceled: root.setMode("list")
        }

        LogView {
          id: logView
          visible: root.mode === "log"
          width: parent.width
          height: visible ? implicitHeight : 0
          lines: DevenvState.log
          title: DevenvState.streamTitle
          running: DevenvState.streaming
          exitCode: DevenvState.streamExit
          foreground: root.foreground
          fontFamily: root.fontFamily
          onBackRequested: root.setMode("list")
        }

        TextField {
          id: filterField
          visible: root.mode === "list"
          width: parent.width
          foreground: root.foreground
          // The operator stays on the first line: a line that ends on a
          // complete expression gets a semicolon inserted for it, and the
          // rest of the binding is quietly dropped.
          placeholderText: Model.Glyph.search + "  Filter environments" +
            (activeFocus ? "" : "   /")
          onTextChanged: {
            // A new filter starts from the top, not from a remembered row.
            root.cursorKey = ""
            root.filterText = text
            root.rememberCursor(0)
          }
          Keys.onEscapePressed: {
            if (text.length > 0) text = ""
            else keyCatcher.forceActiveFocus()
          }
          Keys.onDownPressed: {
            keyCatcher.forceActiveFocus()
            root.moveCursor(0)
          }
        }

        EnvList {
          id: list
          visible: root.mode === "list"
          width: parent.width
          rows: root.rows
          mutating: DevenvState.mutating
          pendingName: DevenvState.pendingName
          pendingVerb: DevenvState.pendingVerb
          deps: DevenvState.deps
          statusPath: DevenvState.statusPath
          status: DevenvState.status
          cursorIndex: root.cursorIndex
          cursorActive: root.cursorActive
          cursorFromKeyboard: root.cursorFromKeyboard
          foreground: root.foreground
          fontFamily: root.fontFamily

          onActionRequested: function(path, verb) { root.dispatch(path, verb) }
          onCursorRequested: function(key) { root.setCursorKey(key) }
        }

        Column {
          visible: root.mode === "list" && list.count === 0
          width: parent.width
          spacing: Style.spacing.sm
          topPadding: Style.spacing.lg
          bottomPadding: Style.spacing.lg

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Model.emptyText({
              cli: DevenvState.deps.cli,
              everLoaded: DevenvState.everLoaded,
              filtered: DevenvState.envs.length > 0
            })
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: text !== ""
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: DevenvState.deps.cli ? DevenvState.warnings.join("\n") : Model.dependencyText(DevenvState.deps)
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            lineHeight: 1.3
          }
        }

        // ------------------------------------------------------------ footer
        //
        // nixarchy-pkg's shape: a hairline, then one line for whatever went
        // wrong or is running, then counts on the left and keys on the right.

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.dim
          opacity: 0.25
        }

        // devenv's and the CLI's refusals are more useful than anything
        // the panel could invent, so they get their own line until dismissed.
        Item {
          width: parent.width
          visible: DevenvState.lastError !== ""
          implicitHeight: visible ? Math.max(errorText.implicitHeight, errorDismiss.height) : 0
          height: implicitHeight

          Text {
            id: errorGlyph
            anchors.left: parent.left
            anchors.top: parent.top
            text: Model.Glyph.alert
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconSmall
          }

          Text {
            id: errorText
            anchors.left: errorGlyph.right
            anchors.leftMargin: Style.spacing.md
            anchors.right: errorDismiss.left
            anchors.rightMargin: Style.spacing.md
            anchors.top: parent.top
            text: DevenvState.lastError
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelActionButton {
            id: errorDismiss
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: -Style.spacing.xs
            iconText: Model.Glyph.close
            tooltipText: "Dismiss"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.iconSmall
            size: Style.space(20)
            onClicked: DevenvState.lastError = ""
          }
        }

        Text {
          width: parent.width
          visible: DevenvState.deps.cli && !DevenvState.deps.devenv && root.mode === "list"
          text: Model.dependencyText(DevenvState.deps)
          textFormat: Text.PlainText
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: text !== "" && DevenvState.lastError === "" && root.mode !== "log"
          text: {
            if (DevenvState.streaming) return DevenvState.streamTitle + " …   o to watch"
            if (DevenvState.streamExit >= 0) {
              return DevenvState.streamTitle + (DevenvState.streamExit === 0 ? " finished" : " failed") +
                "   o shows the log"
            }
            return ""
          }
          textFormat: Text.PlainText
          color: DevenvState.streaming ? Color.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Item {
          width: parent.width
          implicitHeight: countsText.implicitHeight
          height: implicitHeight

          Text {
            id: countsText
            anchors.left: parent.left
            text: Model.footerText(DevenvState.envs)
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            text: DevenvState.mutating ? "working…" : "? keys   c create   esc close"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    ShortcutSheet {
      id: helpSheet
      anchors.fill: parent
      z: 5
      opened: root.helpOpen
      foreground: root.foreground
      background: Color.popups.background
      fontFamily: root.fontFamily
      onDismissed: root.helpOpen = false
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      z: 10
      opened: root.confirmOpen
      message: root.confirmMessage
      confirmText: root.confirmLabel
      background: Color.popups.background
      foreground: root.foreground
      fontFamily: root.fontFamily
      onCanceled: root.closeConfirm()
      onConfirmed: root.confirmAccepted()
    }
  }
}
