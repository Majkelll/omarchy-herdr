import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.majkelll.herdr"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property var machines: []
  property var state: Model.emptyState()
  property string configError: ""
  property string actionError: ""
  property bool loading: false
  property string attentionKey: ""
  property var probeResult: null
  property bool probing: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color faint: Qt.darker(foreground, 1.7)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  property var herdrColors: Model.herdrPalette("", "")
  readonly property string panelBackground: String(Commons.Color.popups.background)
  readonly property bool symbolMarks: !!root.herdrColors && root.herdrColors.indicators === "symbols"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property real labelColumn: Style.space(96)
  readonly property real dotColumn: Style.space(16)

  property var collapsed: ({})
  property var rows: []
  property string rowsSignature: ""

  property string selectedKey: ""

  property bool formOpen: false
  property string editingId: ""
  property string draftLabel: ""
  property string draftHost: ""
  property string draftPort: ""
  property string draftUser: ""
  property string draftIdentity: ""
  property string draftHerdrPath: ""
  property string draftTimeout: ""
  property string formError: ""
  property bool advancedOpen: false

  property string removeArmed: ""
  property string copiedFor: ""

  property int selectedIndex: 0
  property bool cursorActive: false
  property bool cursorPlaced: false

  readonly property var totals: (root.state && root.state.totals) ? root.state.totals
    : Model.emptyState().totals
  readonly property bool alarmed: root.configError !== "" || root.totals.blocked > 0
  readonly property bool anySessions: {
    var list = root.rows || []
    for (var i = 0; i < list.length; i++) if (list[i].kind === "session") return true
    return false
  }

  readonly property bool probeCurrent: !!root.probeResult
    && root.probeResult.key === Model.probeKey(root.draftFields())

  function toneFor(status) {
    if (status === "unreachable") return root.urgent
    var palette = root.herdrColors || Model.herdrPalette("", "")
    if (status === "blocked" || status === "done" || status === "working" || status === "idle")
      return Model.readable(palette[status], root.panelBackground)
    return root.faint
  }

  function glyphFor(row) {
    if (row.kind === "machine") {
      if (!row.remote) return Model.GLYPH.local
      return row.reachable ? Model.GLYPH.machine : Model.GLYPH.machineOff
    }
    return ""
  }

  function open() {
    root.controller.show()
    root.cursorPlaced = false
    Qt.callLater(function() {
      if (!root.opened) return
      keyCatcher.forceActiveFocus()
      root.placeCursor()
    })
  }

  function close() {
    root.controller.hide()
    root.cursorActive = false
    root.removeArmed = ""
    root.cancelForm()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function placeCursor() {
    if (root.cursorPlaced) return
    var list = root.rows || []
    if (list.length === 0) return
    root.setSelected(Math.min(Model.bestRow(root.state || Model.emptyState(), root.collapsed || ({})),
      list.length - 1))
    root.cursorPlaced = true
  }

  function rowKey(row) {
    return row ? [row.kind, row.machine, row.session, row.pane].join("\u0000") : ""
  }

  function setSelected(index) {
    var list = root.rows || []
    root.selectedIndex = Math.max(0, Math.min(list.length - 1, index))
    if (list.length > 0) root.selectedKey = root.rowKey(list[root.selectedIndex])
  }

  function syncRows() {
    var next = Model.rows(root.state || Model.emptyState(), root.collapsed || ({})) || []
    var signature = JSON.stringify(next)
    if (signature === root.rowsSignature) return
    root.rowsSignature = signature
    root.rows = next
    for (var i = 0; i < next.length; i++) {
      if (root.rowKey(next[i]) === root.selectedKey) { root.selectedIndex = i; return }
    }
    root.setSelected(root.selectedIndex)
  }

  function refresh() {
    if (root.hostWidget) root.hostWidget.refresh()
  }

  function land(row) {
    if (!Model.actionable(row)) return
    if (row.kind === "machine") { root.toggleCollapsed(row.machine); return }
    if (!root.hostWidget) return
    root.hostWidget.openRow(row.machine, row.session, row.pane)
    root.close()
  }

  function toggleCollapsed(id) {
    var next = {}
    for (var key in root.collapsed) next[key] = root.collapsed[key]
    next[id] = next[id] === true ? false : true
    root.collapsed = next
  }

  function startAdd() {
    root.formOpen = true
    root.editingId = ""
    root.draftLabel = ""
    root.draftHost = ""
    root.draftPort = ""
    root.draftUser = ""
    root.draftIdentity = ""
    root.draftHerdrPath = ""
    root.draftTimeout = ""
    root.formError = ""
    root.advancedOpen = false
    if (root.hostWidget) root.hostWidget.clearProbe()
    Qt.callLater(function() { if (root.opened) hostField.forceActiveFocus() })
  }

  function startEdit(id) {
    var machine = Model.findMachine(root.machines || [], id)
    if (!machine) return
    root.formOpen = true
    root.editingId = id
    root.draftLabel = machine.label
    root.draftHost = machine.host
    root.draftPort = machine.port > 0 ? String(machine.port) : ""
    root.draftUser = machine.user
    root.draftIdentity = machine.identityFile
    root.draftHerdrPath = machine.herdrPath
    root.draftTimeout = String(machine.connectTimeoutSec)
    root.formError = ""
    root.advancedOpen = machine.port > 0 || machine.user !== "" || machine.identityFile !== ""
      || machine.herdrPath !== ""
    if (root.hostWidget) root.hostWidget.clearProbe()
    Qt.callLater(function() { if (root.opened) hostField.forceActiveFocus() })
  }

  function cancelForm() {
    root.formOpen = false
    root.editingId = ""
    root.formError = ""
    root.advancedOpen = false
    if (root.hostWidget) root.hostWidget.clearProbe()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function draftFields() {
    return {
      label: root.draftLabel,
      host: root.draftHost,
      port: root.draftPort,
      user: root.draftUser,
      identityFile: root.draftIdentity,
      herdrPath: root.draftHerdrPath,
      connectTimeoutSec: root.draftTimeout
    }
  }

  function submitForm() {
    if (!root.hostWidget) return
    var fields = root.draftFields()
    if (root.probeCurrent && root.probeResult.reachable && Model.clip(root.probeResult.herdrPath) !== ""
        && Model.clip(fields.herdrPath) === "") {
      fields.herdrPath = Model.clip(root.probeResult.herdrPath)
    }
    var problem = root.editingId === ""
      ? root.hostWidget.addMachine(fields)
      : root.hostWidget.editMachine(root.editingId, fields)
    if (problem !== "") {
      root.formError = problem
      return
    }
    root.cancelForm()
  }

  function testForm() {
    if (!root.hostWidget) return
    root.formError = ""
    root.hostWidget.probe(root.draftFields())
  }

  function removeMachine(id) {
    if (!root.hostWidget) return
    if (root.editingId === id) root.cancelForm()
    root.removeArmed = ""
    root.hostWidget.removeMachine(id)
  }

  function armRemove(id) {
    root.removeArmed = id
    armTimer.restart()
  }

  function copyInstallCommand(id) {
    Quickshell.clipboardText = Model.INSTALL_COMMAND
    root.copiedFor = id
    copiedTimer.restart()
  }

  function probeLine() {
    if (root.probing) return "Asking…"
    if (!root.probeCurrent) return ""
    var result = root.probeResult
    if (!result.reachable) return Model.errorText(result.error) || "Could not reach it"
    if (Model.clip(result.error) === "herdr-missing")
      return "Reached it, but herdr is not installed there. Run this over there, then Test again: "
        + Model.INSTALL_COMMAND
    var text = "Reached it · herdr " + (Model.clip(result.version) || "?")
    text += result.server ? " · a server is running" : " · no server running yet"
    return text
  }

  function probeOk() {
    return root.probeCurrent && root.probeResult.reachable
      && Model.clip(root.probeResult.error) === ""
  }

  function probeNeedsInstall() {
    return root.probeCurrent && root.probeResult.reachable
      && Model.clip(root.probeResult.error) === "herdr-missing"
  }

  function hasCursorAt(index) { return root.cursorActive && root.selectedIndex === index }
  function takeCursor(index) { root.cursorActive = true; root.setSelected(index) }

  function moveCursor(delta) {
    var list = root.rows || []
    if (list.length === 0) return
    if (!root.cursorActive) { root.cursorActive = true; return }
    var next = root.selectedIndex + delta
    if (next < 0) next = list.length - 1
    if (next >= list.length) next = 0
    root.setSelected(next)
  }

  function selectedRow() {
    var list = root.rows || []
    if (root.selectedIndex < 0 || root.selectedIndex >= list.length) return null
    return list[root.selectedIndex]
  }

  function deleteCursor() {
    var row = root.selectedRow()
    if (!row || row.kind !== "machine" || !row.remote) return
    if (root.removeArmed === row.machine) root.removeMachine(row.machine)
    else root.armRemove(row.machine)
  }

  function activateCursor() {
    var row = root.selectedRow()
    if (row) root.land(row)
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  onMachinesChanged: {
    var list = root.machines || []
    if (root.editingId !== "" && !Model.findMachine(list, root.editingId)) root.cancelForm()
  }

  onStateChanged: {
    root.syncRows()
    if (root.opened) root.placeCursor()
  }
  onCollapsedChanged: root.syncRows()
  Component.onCompleted: root.syncRows()

  onDraftHostChanged: root.formError = ""
  onDraftPortChanged: root.formError = ""
  onDraftUserChanged: root.formError = ""
  onDraftIdentityChanged: root.formError = ""
  onDraftHerdrPathChanged: root.formError = ""
  onDraftTimeoutChanged: root.formError = ""

  Timer {
    id: armTimer
    interval: 4000
    repeat: false
    onTriggered: root.removeArmed = ""
  }

  Timer {
    id: copiedTimer
    interval: 4000
    repeat: false
    onTriggered: root.copiedFor = ""
  }

  component ListRow: CursorSurface {
    id: rowSurface

    required property int rowIndex
    property bool activeRow: false

    readonly property bool selected: root.hasCursorAt(rowIndex)

    signal activated()

    width: parent ? parent.width : 0
    hasCursor: selected
    current: activeRow
    foreground: root.foreground
    accent: Commons.Color.accent

    onSelectedChanged: if (selected) scrollArea.ensureVisible(rowSurface)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) root.takeCursor(rowSurface.rowIndex)
      onClicked: rowSurface.activated()
    }
  }

  component StateBanner: BorderSurface {
    id: banner

    property color tone: root.foreground
    property string glyph: ""
    property string title: ""
    property string detail: ""

    width: parent ? parent.width : 0
    implicitHeight: bannerRow.implicitHeight + Style.spacing.xxl
    radius: Style.cornerRadius
    color: Style.hoverFillFor(banner.tone, banner.tone)
    borderSpec: Border.controlSpec("selected", banner.tone, banner.tone)

    Row {
      id: bannerRow
      anchors.centerIn: parent
      width: parent.width - Style.spacing.huge * 2
      spacing: Style.spacing.controlGap

      Text {
        text: banner.glyph
        color: banner.tone
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(28)
        spacing: Style.spacing.xxs
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          text: banner.title
          color: banner.tone
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          visible: text !== ""
          width: parent.width
          text: banner.detail
          color: banner.tone
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  component FormRow: Item {
    id: formRow

    property string label: ""
    default property alias content: formHolder.children

    width: parent ? parent.width : 0
    implicitHeight: Math.max(labelText.implicitHeight, formHolder.childrenRect.height)

    Text {
      id: labelText
      text: formRow.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      width: root.labelColumn
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Item {
      id: formHolder
      anchors.left: labelText.right
      anchors.leftMargin: Style.spacing.controlGap
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      implicitHeight: childrenRect.height
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(780))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: labelField.activeFocus || hostField.activeFocus || portField.activeFocus
        || userField.activeFocus || identityField.activeFocus || pathField.activeFocus
        || timeoutField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveCursor(dx !== 0 ? dx : dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.deleteCursor()
      onCloseRequested: {
        if (root.formOpen) { root.cancelForm(); return }
        root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "\x7f") { root.deleteCursor(); return }
        var lower = String(text || "").toLowerCase()
        if (lower === "a") { root.startAdd(); return }
        if (lower === "r") { root.refresh(); return }
        var row = root.selectedRow()
        if (!row) return
        if (lower === "e" && row.kind === "machine" && row.remote) root.startEdit(row.machine)
        else if (lower === "o") root.land(row)
      }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        function ensureVisible(item) {
          if (!item || contentHeight <= height) return
          var top = item.mapToItem(contentColumn, 0, 0).y
          var margin = Style.spacing.lg
          if (top - margin < contentY) contentY = Math.max(0, top - margin)
          else if (top + item.height + margin > contentY + height)
            contentY = Math.min(contentHeight - height, top + item.height + margin - height)
        }

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: scrollArea.width
          spacing: Style.spacing.panelGap

          PanelHero {
            title: "Herdr"
            meta: root.configError !== "" ? "machines.json cannot be read"
              : Model.summary(root.state || Model.emptyState())
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: root.alarmed ? Model.GLYPH.machineOff : Model.GLYPH.machine
                color: root.alarmed ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              Row {
                spacing: Style.spacing.xs

                PanelActionButton {
                  iconText: Model.GLYPH.add
                  tooltipText: "Add a machine"
                  foreground: root.foreground
                  hoverColor: Commons.Color.accent
                  fontFamily: root.fontFamily
                  onClicked: root.formOpen && root.editingId === "" ? root.cancelForm() : root.startAdd()
                }

                PanelActionButton {
                  iconText: Model.GLYPH.refresh
                  tooltipText: "Refresh now"
                  enabled: !root.loading
                  foreground: root.foreground
                  hoverColor: Commons.Color.accent
                  fontFamily: root.fontFamily
                  onClicked: root.refresh()
                }
              }
            }
          }

          StateBanner {
            visible: root.configError !== ""
            tone: root.urgent
            glyph: Model.GLYPH.alert
            title: "machines.json"
            detail: root.configError
          }

          Text {
            visible: text !== ""
            width: parent.width
            text: root.actionError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Column {
            width: parent.width
            spacing: Style.spacing.xxs

            Repeater {
              model: root.rows

              delegate: ListRow {
                required property var modelData
                required property int index

                rowIndex: index
                activeRow: modelData.kind === "session" && modelData.showing === true
                implicitHeight: rowContent.implicitHeight + Style.spacing.md

                onActivated: root.land(modelData)

                Row {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.spacing.rowPaddingX
                    + (modelData.kind === "session" ? Style.space(14)
                       : (modelData.kind === "agent" ? Style.space(28) : 0))
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  spacing: Style.spacing.controlGap

                  Item {
                    width: root.dotColumn
                    height: Math.max(mark.height, machineGlyph.implicitHeight)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      id: machineGlyph
                      anchors.centerIn: parent
                      visible: modelData.kind === "machine"
                      text: root.glyphFor(modelData)
                      color: modelData.kind === "machine" && !modelData.reachable && modelData.enabled
                        ? root.urgent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.iconSmall
                    }

                    Item {
                      id: mark
                      anchors.centerIn: parent
                      visible: modelData.kind !== "machine"
                      width: Style.space(8)
                      height: width

                      readonly property string status: modelData.status || ""
                      readonly property bool active: status === "blocked" || status === "working"
                        || status === "done"
                      readonly property bool ring: status === "idle" || status === "stopped"
                      readonly property color tone: root.toneFor(status)

                      Rectangle {
                        visible: !root.symbolMarks || !(mark.active || mark.ring)
                        anchors.centerIn: parent
                        width: mark.active || mark.ring ? parent.width : Math.round(parent.width * 0.5)
                        height: width
                        radius: width / 2
                        color: mark.active || !mark.ring ? mark.tone : "transparent"
                        border.width: mark.ring ? Math.max(1, Math.round(parent.width * 0.18)) : 0
                        border.color: mark.tone
                      }

                      Text {
                        visible: root.symbolMarks && (mark.active || mark.ring)
                        anchors.centerIn: parent
                        text: Model.stateMark(mark.status === "stopped" ? "idle" : mark.status, "symbols")
                        textFormat: Text.PlainText
                        color: mark.tone
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                      }

                      SequentialAnimation on opacity {
                        running: modelData.kind === "agent" && modelData.key === root.attentionKey
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { from: 1.0; to: 0.25; duration: 700 }
                        NumberAnimation { from: 0.25; to: 1.0; duration: 700 }
                      }
                    }
                  }

                  Column {
                    width: parent.width - root.dotColumn - actions.width
                      - Style.spacing.controlGap * 2
                    spacing: Style.spacing.xxs
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      width: parent.width
                      text: modelData.label
                      textFormat: Text.PlainText
                      color: modelData.kind === "agent" && modelData.status === "blocked"
                        ? root.toneFor("blocked") : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: modelData.kind === "agent" ? Style.font.bodySmall : Style.font.body
                      font.bold: modelData.kind === "machine"
                        || (modelData.kind === "session" && modelData.showing === true)
                      elide: Text.ElideRight
                    }

                    Text {
                      visible: text !== ""
                      width: parent.width
                      text: modelData.line || ""
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Row {
                    id: actions
                    spacing: Style.spacing.xxs
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      visible: modelData.kind === "session" && modelData.showing === true
                      text: Model.GLYPH.open
                      color: Commons.Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.iconSmall
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    PanelActionButton {
                      visible: modelData.kind === "machine" && modelData.remote === true
                        && modelData.errorCode === "herdr-missing" && modelData.enabled === true
                      iconText: Model.GLYPH.copy
                      tooltipText: root.copiedFor === modelData.machine
                        ? "Copied. Run it on that machine to install herdr"
                        : "Copy herdr's install command: " + Model.INSTALL_COMMAND
                      foreground: root.foreground
                      hoverColor: Commons.Color.accent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.iconSmall
                      onClicked: root.copyInstallCommand(modelData.machine)
                    }

                    PanelActionButton {
                      visible: modelData.kind === "machine" && modelData.remote === true
                      iconText: Model.GLYPH.edit
                      tooltipText: "Edit this machine"
                      foreground: root.foreground
                      hoverColor: Commons.Color.accent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.iconSmall
                      onClicked: root.startEdit(modelData.machine)
                    }

                    PanelActionButton {
                      visible: modelData.kind === "machine" && modelData.remote === true
                      iconText: Model.GLYPH.remove
                      tooltipText: root.removeArmed === modelData.machine
                        ? "Press again to remove it" : "Remove this machine"
                      foreground: root.removeArmed === modelData.machine ? root.urgent : root.foreground
                      hoverColor: root.urgent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.iconSmall
                      onClicked: root.removeArmed === modelData.machine
                        ? root.removeMachine(modelData.machine)
                        : root.armRemove(modelData.machine)
                    }

                    Text {
                      visible: modelData.kind === "machine" && modelData.sessions > 0
                      text: modelData.collapsed === true ? "󰅂" : "󰅀"
                      color: root.faint
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.iconSmall
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: !root.anySessions
            width: parent.width
            text: root.loading && (root.rows || []).length === 0 ? "Asking every machine…"
              : "No herdr sessions on any machine yet."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { foreground: root.foreground }

          Button {
            visible: !root.formOpen
            text: "Add a machine"
            iconText: Model.GLYPH.add
            bordered: true
            focusable: false
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.startAdd()
          }

          PanelSectionHeader {
            visible: root.formOpen
            text: root.editingId === "" ? "ADD A MACHINE" : "EDIT MACHINE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            visible: root.formOpen
            width: parent.width
            spacing: Style.spacing.md

            FormRow {
              label: "Host"
              TextField {
                id: hostField
                width: parent.width
                placeholderText: "build-box.local, or an alias from ~/.ssh/config"
                text: root.draftHost
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onTextChanged: root.draftHost = text
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.cancelForm()
              }
            }

            FormRow {
              label: "Name"
              TextField {
                id: labelField
                width: parent.width
                placeholderText: "What you'll call it here"
                text: root.draftLabel
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onTextChanged: root.draftLabel = text
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.cancelForm()
              }
            }

            Button {
              text: root.advancedOpen ? "Fewer options" : "More options"
              iconText: root.advancedOpen ? "󰅀" : "󰅂"
              focusable: false
              foreground: root.dim
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.advancedOpen = !root.advancedOpen
            }

            Column {
              width: parent.width
              spacing: Style.spacing.md
              visible: root.advancedOpen

              FormRow {
                label: "Port"
                TextField {
                  id: portField
                  width: Style.space(90)
                  placeholderText: "22"
                  text: root.draftPort
                  foreground: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  onTextChanged: root.draftPort = text
                  onAccepted: root.submitForm()
                  Keys.onEscapePressed: root.cancelForm()
                }
              }

              FormRow {
                label: "User"
                TextField {
                  id: userField
                  width: parent.width
                  placeholderText: "ssh's own default"
                  text: root.draftUser
                  foreground: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  onTextChanged: root.draftUser = text
                  onAccepted: root.submitForm()
                  Keys.onEscapePressed: root.cancelForm()
                }
              }

              FormRow {
                label: "Identity file"
                TextField {
                  id: identityField
                  width: parent.width
                  placeholderText: "ssh-agent, or ~/.ssh/config"
                  text: root.draftIdentity
                  foreground: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  onTextChanged: root.draftIdentity = text
                  onAccepted: root.submitForm()
                  Keys.onEscapePressed: root.cancelForm()
                }
              }

              FormRow {
                label: "herdr path"
                TextField {
                  id: pathField
                  width: parent.width
                  placeholderText: "found automatically"
                  text: root.draftHerdrPath
                  foreground: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  onTextChanged: root.draftHerdrPath = text
                  onAccepted: root.submitForm()
                  Keys.onEscapePressed: root.cancelForm()
                }
              }

              FormRow {
                label: "Timeout"
                Row {
                  spacing: Style.spacing.controlGap

                  TextField {
                    id: timeoutField
                    width: Style.space(90)
                    placeholderText: String(Model.DEFAULT_TIMEOUT)
                    text: root.draftTimeout
                    foreground: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    onTextChanged: root.draftTimeout = text
                    onAccepted: root.submitForm()
                    Keys.onEscapePressed: root.cancelForm()
                  }

                  Text {
                    text: "seconds"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }

            Text {
              visible: text !== ""
              width: parent.width
              text: root.probeLine()
              color: root.probing ? root.dim
                : (root.probeOk() ? root.toneFor("idle")
                  : (root.probeNeedsInstall() ? root.toneFor("working") : root.urgent))
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: text !== ""
              width: parent.width
              text: root.formError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Item {
              width: parent.width
              implicitHeight: saveButton.implicitHeight

              Button {
                visible: root.probeNeedsInstall()
                text: root.copiedFor === "form" ? "Copied" : "Copy"
                iconText: Model.GLYPH.copy
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                height: saveButton.height
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.copyInstallCommand("form")
              }

              Button {
                text: root.probing ? "Testing…" : "Test"
                enabled: !root.probing && Model.clip(root.draftHost) !== ""
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                height: saveButton.height
                anchors.right: cancelButton.left
                anchors.rightMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.testForm()
              }

              Button {
                id: cancelButton
                text: "Cancel"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                height: saveButton.height
                anchors.right: saveButton.left
                anchors.rightMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.cancelForm()
              }

              Button {
                id: saveButton
                text: root.editingId === "" ? "Add machine" : "Save changes"
                iconText: root.editingId === "" ? Model.GLYPH.add : Model.GLYPH.edit
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.submitForm()
              }
            }
          }

          Text {
            width: parent.width
            text: "Enter opens what the cursor is on · a adds a machine · r refreshes · e edits · x or Del removes"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
