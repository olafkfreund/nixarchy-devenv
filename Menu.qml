import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Dev environments on a keybind (Super+Alt+E) or a menu row, over whatever
// you were working in.
//
// The same list, form and log as the bar popup (it hosts the same
// DevenvView, over the same DevenvState), but it does not need the widget to
// be in the bar, and it holds the keyboard for as long as it is up.
//
//   omarchy-shell shell toggle nixarchy.devenv '{}'
//   omarchy-shell shell toggle nixarchy.devenv '{"create":true}'
//   omarchy-shell shell toggle nixarchy.devenv '{"path":"/home/me/Source/app"}'
Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property var targetScreen: null

  // Style.space() already carries the theme's spacing scale, which in turn
  // carries its font scale, and the compositor has already applied the
  // monitor's own scale to these logical pixels. Multiplying again on top of
  // both is what made the menu ignore the desktop's size: it magnified a
  // figure that was already correct, and the card's clamp then cut off
  // whatever no longer fitted. The shell's own full-screen menu applies no
  // such transform either.
  readonly property int viewWidth: Style.space(680)

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    return null
  }

  function readSettings() {
    var defaults = manifest && manifest.barWidget && manifest.barWidget.defaults
      ? manifest.barWidget.defaults : ({})
    var id = manifest && manifest.id ? manifest.id : "nixarchy.devenv"
    return Model.settingsFor(shell ? shell.barConfig : null, id, defaults)
  }

  function payload(payloadJson) {
    try {
      var p = JSON.parse(String(payloadJson || "{}"))
      return p && typeof p === "object" ? p : ({})
    } catch (e) {
      return ({})
    }
  }

  // Plugin lifecycle: the host calls open(payloadJson) on summon and close()
  // on hide, and reads `opened` to decide what `toggle` means. keepLoaded, so
  // every open starts from a clean slate.
  function open(payloadJson) {
    DevenvState.settings = root.readSettings()
    root.targetScreen = root.focusedScreen()
    if (!root.opened) DevenvState.acquire("view")
    view.reset()
    var p = root.payload(payloadJson)
    if (p.create === true) view.openForm()
    else if (typeof p.path === "string") view.selectPath(p.path)
    root.opened = true
  }

  function close() {
    if (root.opened) DevenvState.release("view")
    view.dismiss()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // `omarchy-shell shell call nixarchy.devenv status ''`
  function status() { return DevenvState.statusJson() }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "nixarchy-devenv-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: if (visible) Qt.callLater(function() { view.focusForMode() })

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    // A click away closes, as every summoned surface here does. The card
    // swallows its own clicks so they never reach this.
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: Math.min(root.viewWidth + card.contentLeftInset + card.contentRightInset,
                      Math.round(panel.width * 0.9))
      height: Math.min(view.implicitHeight + card.contentTopInset + card.contentBottomInset,
                       Math.round(panel.height * 0.85))
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(Style.gapsOut, Math.round((panel.height - height) / 3))
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: frame
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        clip: true

        // The card is clamped to a fraction of the screen, so on a short
        // screen -- or with a large theme font -- the view can be taller than
        // the space it is given. It scrolls rather than losing its footer off
        // the bottom with no way to reach it.
        Flickable {
          id: flick
          anchors.fill: parent
          contentHeight: view.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          DevenvView {
            id: view
            width: flick.width
            height: implicitHeight
            // The one place the menu differs from the bar popup: a rung
            // higher on the shell's ladder, not a factor over it.
            large: true
            foreground: Color.foreground
            fontFamily: Style.font.family
            onCloseRequested: root.close()
          }
        }
      }
    }
  }
}
