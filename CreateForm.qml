import QtQuick
import QtQuick.Controls
import qs.Ui
import qs.Commons
import "Model.js" as Model

// The create form: name, where, template, providers for a generator, git and
// allow. Keyboard only; this scope owns the keyboard while it is open.
//
// Navigation is one function, navKey(), which every field forwards to. A text
// field keeps every printable key for itself (j and k included); Tab, the
// arrows, Enter and Esc mean the same thing everywhere.
//
// No Popup anywhere: the template and provider pickers are inline lists under
// their row. A Popup is reparented to the window overlay, so it escapes the
// menu's card -- it would draw outside the surface, ignore the card's clip and
// its scrolling, and take the keyboard from the panel that holds it.
FocusScope {
  id: root

  property var templates: []
  property var roots: []
  property string home: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // Set by DevenvView; the defaults are the bar popup's rungs.
  property int fontRow: Style.font.caption
  property int fontLabel: Style.font.body
  property int fontGlyph: Style.font.iconSmall
  readonly property color dim: Qt.darker(foreground, 1.5)

  // (form, result): the result is Model.validateForm's, argv included.
  signal submitted(var form, var result)
  signal canceled()

  // ------------------------------------------------------------------ state

  property var form: Model.emptyForm([], "")
  property int fieldIndex: 0
  property var touched: ({})
  property bool attempted: false
  // Cursor inside the template list and the provider list; -1 is the row itself.
  property int templateIndex: -1
  property string templateFilter: ""
  property int providerIndex: 0

  readonly property var fields: Model.formFields(templates, form.template)
  readonly property var current: fieldIndex >= 0 && fieldIndex < fields.length ? fields[fieldIndex] : null
  readonly property var check: Model.validateForm(form, templates, home)
  readonly property var chosen: Model.templateById(templates, form.template)
  readonly property var templateChoices: Model.templateChoices(root.templates, root.templateFilter)

  implicitHeight: formColumn.implicitHeight

  // Called every time the form opens: a clean form, cursor on the name.
  function start() {
    root.form = Model.emptyForm(root.roots, root.home)
    root.touched = ({})
    root.attempted = false
    root.templateIndex = -1
    root.templateFilter = ""
    root.providerIndex = 0
    root.fieldIndex = 0
    Qt.callLater(root.focusCurrent)
  }

  function setValue(key, value) {
    var next = Object.assign({}, root.form)
    next[key] = value
    root.form = next
  }

  function showError(key) {
    return (root.attempted || root.touched[key] === true) && root.check.errors[key] ? root.check.errors[key] : ""
  }

  // Not root.forceActiveFocus() for a non-text row: on a FocusScope that hands
  // focus back to the child that had it last, which is the text field just
  // left, and the next space would be typed into it.
  function focusCurrent() {
    var item = fieldRepeater.itemAt(root.fieldIndex)
    if (item && item.takesText) item.takeFocus()
    else keySink.forceActiveFocus()
    if (item) flick.ensureVisible(item)
  }

  function moveField(delta) {
    if (root.current) {
      var t = Object.assign({}, root.touched)
      t[root.current.key] = true
      root.touched = t
    }
    root.templateIndex = -1
    root.templateFilter = ""
    root.fieldIndex = Math.max(0, Math.min(root.fields.length - 1, root.fieldIndex + delta))
    Qt.callLater(root.focusCurrent)
  }

  function activate() {
    var f = root.current
    if (!f) return
    if (f.kind === "bool") { if (!f.locked) setValue(f.key, !root.form[f.key]) }
    else if (f.kind === "template") root.templateIndex = root.templateIndex >= 0 ? -1 : 0
    else if (f.kind === "providers" && root.chosen) {
      var p = root.chosen.providers[root.providerIndex]
      if (p) setValue("providers", Model.toggleProvider(root.form.providers, p))
    }
  }

  function submit() {
    root.attempted = true
    if (!root.check.ok) {
      var at = Model.firstErrorIndex(root.fields, root.check.errors)
      if (at !== -1) root.fieldIndex = at
      Qt.callLater(root.focusCurrent)
      return
    }
    root.submitted(Object.assign({}, root.form), root.check)
  }

  function pickTemplate(index) {
    if (index < 0 || index >= root.templateChoices.length) return
    var next = Object.assign({}, root.form)
    next.template = root.templateChoices[index].id
    next.providers = []
    root.form = next
    root.providerIndex = 0
    root.templateIndex = -1
    root.templateFilter = ""
  }

  // The one place a navigation key is decided. Returns true when handled.
  function navKey(event) {
    var key = event.key
    var kind = root.current ? root.current.kind : ""
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var providers = root.chosen ? root.chosen.providers : []

    if (key === Qt.Key_Escape) {
      if (kind === "template" && (root.templateIndex >= 0 || root.templateFilter !== "")) {
        root.templateIndex = -1
        root.templateFilter = ""
      } else root.canceled()
      return true
    }
    if (key === Qt.Key_Tab && !shift) { moveField(1); return true }
    if (key === Qt.Key_Backtab || (key === Qt.Key_Tab && shift)) { moveField(-1); return true }
    if (key === Qt.Key_Down) {
      if (kind === "template" && root.templateIndex < root.templateChoices.length - 1) { root.templateIndex += 1; return true }
      if (kind === "providers" && root.providerIndex < providers.length - 1) { root.providerIndex += 1; return true }
      moveField(1)
      return true
    }
    if (key === Qt.Key_Up) {
      if (kind === "template" && root.templateIndex >= 0) { root.templateIndex -= 1; return true }
      if (kind === "providers" && root.providerIndex > 0) { root.providerIndex -= 1; return true }
      moveField(-1)
      return true
    }
    if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      if (kind === "template" && root.templateIndex >= 0) { pickTemplate(root.templateIndex); return true }
      submit()
      return true
    }
    return false
  }

  // Keys that reach the scope itself: every row that is not a text field.
  Keys.onPressed: function(event) {
    if (root.navKey(event)) { event.accepted = true; return }
    // On the template row, typing filters the list (j and k included).
    if (root.current && root.current.kind === "template") {
      if (event.key === Qt.Key_Backspace) {
        root.templateFilter = root.templateFilter.slice(0, -1)
        event.accepted = true
        return
      }
      if (event.text.length === 1 && /[A-Za-z0-9 ._&-]/.test(event.text) && event.key !== Qt.Key_Space) {
        root.templateFilter += event.text
        root.templateIndex = root.templateChoices.length > 0 ? 0 : -1
        event.accepted = true
        return
      }
    }
    if (event.key === Qt.Key_Space) { root.activate(); event.accepted = true; return }
    if (event.key === Qt.Key_J) { root.moveField(1); event.accepted = true; return }
    if (event.key === Qt.Key_K) { root.moveField(-1); event.accepted = true; return }
  }

  Item { id: keySink }

  Column {
    id: formColumn
    anchors.fill: parent
    spacing: Style.spacing.md

    Row {
      width: parent.width
      spacing: Style.spacing.md

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Model.Glyph.plus
        textFormat: Text.PlainText
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: root.fontGlyph
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "New project"
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontLabel
        font.bold: true
      }
    }

    Flickable {
      id: flick
      width: parent.width
      height: Math.min(fieldsColumn.implicitHeight, Style.space(420))
      contentHeight: fieldsColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      function ensureVisible(item) {
        var y = item.mapToItem(fieldsColumn, 0, 0).y
        if (y < contentY) contentY = y
        else if (y + item.height > contentY + height) contentY = y + item.height - height
      }

      Column {
        id: fieldsColumn
        width: flick.width - Style.spacing.md
        spacing: Style.spacing.xs

        Repeater {
          id: fieldRepeater
          model: root.fields

          delegate: Item {
            id: fieldItem

            required property var modelData
            required property int index

            readonly property bool isCurrent: index === root.fieldIndex
            readonly property bool takesText: modelData.kind === "text"
            readonly property string error: root.showError(modelData.key)

            function takeFocus() { input.forceActiveFocus() }

            width: fieldsColumn.width
            implicitHeight: body.implicitHeight + Style.spacing.sm * 2
            opacity: modelData.locked === true ? 0.55 : 1.0

            CursorSurface {
              anchors.fill: parent
              hasCursor: fieldItem.isCurrent
              foreground: root.foreground
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                root.fieldIndex = fieldItem.index
                root.activate()
                Qt.callLater(root.focusCurrent)
              }
            }

            Column {
              id: body
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.lg
              anchors.rightMargin: Style.spacing.lg
              spacing: Style.spacing.xs

              // bool / template / providers: one line with a state glyph.
              Row {
                visible: !fieldItem.takesText
                width: parent.width
                spacing: Style.spacing.md

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: {
                    var f = fieldItem.modelData
                    if (f.kind === "template") return "≡"
                    if (f.kind === "providers") return "☁"
                    return root.form[f.key] === true ? "■" : "□"
                  }
                  textFormat: Text.PlainText
                  color: fieldItem.modelData.kind === "bool" && root.form[fieldItem.modelData.key] === true
                    ? Color.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fontLabel
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: {
                    var f = fieldItem.modelData
                    if (f.kind === "template") return f.label + ":  " + (root.chosen ? root.chosen.label + "  · " + root.chosen.group : "none") +
                      (root.templateFilter !== "" ? "      filter: " + root.templateFilter : "")
                    if (f.kind === "providers") return f.label + ":  " + (root.form.providers.length ? root.form.providers.join(", ") : "none yet")
                    return f.label
                  }
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fontRow
                  elide: Text.ElideRight
                  width: Math.min(implicitWidth, body.width - Style.space(24))
                }
              }

              // text: a label over a field.
              Text {
                visible: fieldItem.takesText
                text: fieldItem.modelData.label
                textFormat: Text.PlainText
                color: fieldItem.isCurrent ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fontRow
              }

              TextField {
                id: input
                visible: fieldItem.takesText
                width: parent.width
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fontRow
                placeholderText: fieldItem.modelData.hint || ""
                // Bound, never assigned: the delegates outlive a close, and a
                // one-time copy would leave last time's typing on screen while
                // the form's data had been reset (nixarchy-distrobox #4).
                text: fieldItem.takesText ? String(root.form[fieldItem.modelData.key] || "") : ""
                onTextEdited: root.setValue(fieldItem.modelData.key, text)
                onActiveFocusChanged: if (activeFocus && root.fieldIndex !== fieldItem.index) root.fieldIndex = fieldItem.index
                Keys.onPressed: function(event) {
                  if (root.navKey(event)) event.accepted = true
                }
              }

              // Templates, under their row, with the group in front.
              Column {
                visible: fieldItem.modelData.kind === "template" && fieldItem.isCurrent
                width: parent.width
                spacing: 0

                Repeater {
                  model: fieldItem.modelData.kind === "template" ? root.templateChoices : []

                  delegate: Text {
                    required property var modelData
                    required property int index
                    width: parent ? parent.width : 0
                    text: (index === root.templateIndex ? "›  " : "   ") + modelData.label +
                      "   · " + modelData.group + (modelData.id === root.form.template ? "   ✓" : "")
                    textFormat: Text.PlainText
                    color: index === root.templateIndex ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fontRow
                    elide: Text.ElideRight

                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.pickTemplate(parent.index)
                    }
                  }
                }
              }

              // Providers of a generator: space ticks the one under the cursor.
              Column {
                visible: fieldItem.modelData.kind === "providers" && fieldItem.isCurrent
                width: parent.width
                spacing: 0

                Repeater {
                  model: fieldItem.modelData.kind === "providers" && root.chosen ? root.chosen.providers : []

                  delegate: Text {
                    required property var modelData
                    required property int index
                    width: parent ? parent.width : 0
                    text: (index === root.providerIndex ? "›  " : "   ") +
                      (root.form.providers.indexOf(modelData) !== -1 ? "■  " : "□  ") + modelData
                    textFormat: Text.PlainText
                    color: index === root.providerIndex ? Color.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.fontRow

                    MouseArea {
                      anchors.fill: parent
                      onClicked: {
                        root.providerIndex = parent.index
                        root.setValue("providers", Model.toggleProvider(root.form.providers, parent.modelData))
                      }
                    }
                  }
                }
              }

              // The template's note says what it costs; then errors, then hints.
              Text {
                visible: text !== ""
                width: parent.width
                text: fieldItem.error !== "" ? fieldItem.error
                  : fieldItem.modelData.kind === "template" && root.chosen ? root.chosen.note
                  : (fieldItem.isCurrent && fieldItem.modelData.hint && !fieldItem.takesText ? fieldItem.modelData.hint : "")
                textFormat: Text.PlainText
                color: fieldItem.error !== "" ? Color.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: root.fontRow
                wrapMode: Text.WordWrap
              }
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: "The first devenv shell in the new project fetches its inputs: it needs the network once, and writes devenv.lock."
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: root.fontRow
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignRight
      text: {
        var f = root.current
        var move = "tab/↓ next   "
        if (!f) return ""
        if (f.kind === "template") return (root.templateIndex >= 0 ? "enter pick   " : "space list   ") + "type to filter   tab next   esc cancel"
        if (f.kind === "providers") return "↑↓ move   space tick   tab next   enter create"
        if (f.kind === "bool") return move + "space toggle   enter create   esc cancel"
        return move + "enter create   esc cancel"
      }
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.65
      font.family: root.fontFamily
      font.pixelSize: root.fontRow
    }
  }
}
