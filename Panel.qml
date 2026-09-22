import QtQuick
// No Quickshell name appears below, but this import is not unused: without it
// the bar widget dies the first time shell.json changes (#8, found on razer).
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// The bar widget: a glyph for your devenv environments, and a keyboard popup
// under it. The data lives in the DevenvState singleton, shared with the
// full-screen menu (Menu.qml).
Panel {
  id: root

  moduleName: "nixarchy.devenv"
  ipcTarget: "nixarchy.devenv.bar"
  manageIpc: false

  readonly property string projectRoots: String(setting("projectRoots", Model.DEFAULT_ROOTS))
  readonly property int refreshIntervalSec: Number(setting("refreshIntervalSec", 60))
  readonly property string terminalEditor: String(setting("terminalEditor", ""))
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false) === true

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function pushSettings() {
    DevenvState.settings = {
      projectRoots: root.projectRoots,
      refreshIntervalSec: root.refreshIntervalSec,
      terminalEditor: root.terminalEditor
    }
  }

  onProjectRootsChanged: pushSettings()
  onRefreshIntervalSecChanged: pushSettings()
  onTerminalEditorChanged: pushSettings()

  Component.onCompleted: {
    pushSettings()
    DevenvState.acquire("bar")
  }
  Component.onDestruction: {
    DevenvState.release("bar")
    if (root.opened) DevenvState.release("view")
  }

  onOpenedChanged: {
    if (opened) {
      DevenvState.acquire("view")
      view.reset()
    } else {
      DevenvState.release("view")
      view.dismiss()
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { DevenvState.refresh() }
    function create(): void {
      root.open()
      view.openForm()
    }
    function select(path: string): void {
      root.open()
      view.selectPath(path)
    }
    function status(): string { return DevenvState.statusJson() }
  }

  // ------------------------------------------------------------------- bar

  implicitWidth: button.visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.Glyph.env
    visible: !root.hideWhenEmpty || DevenvState.counts.total > 0
    dimmed: DevenvState.counts.total === 0
    active: DevenvState.mutating
    useActiveColor: true
    activeColor: Color.accent
    tooltipText: "Dev environments · " + Model.summaryText(DevenvState.envs, DevenvState.deps)

    onPressed: function(b) {
      if (b === Qt.MiddleButton) DevenvState.refresh()
      else root.toggle()
    }
  }

  // ----------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: view.keyTarget
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(view.implicitHeight)

    DevenvView {
      id: view
      anchors.fill: parent
      foreground: root.foreground
      fontFamily: root.fontFamily
      onCloseRequested: root.close()
      onSwitchPanelRequested: function(direction) { root.switchPanel(direction) }
    }
  }
}
