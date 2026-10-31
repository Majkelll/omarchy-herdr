import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.majkelll.herdr"

  readonly property string ctlPath:
    String(Qt.resolvedUrl("bin/herdr-ctl")).replace(/^file:\/\//, "")

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: Quickshell.env("HERDR_WIDGET_CONFIG")
    || ((Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/omarchy-herdr/machines.json")
  readonly property string configDir: configPath.replace(/\/[^\/]*$/, "")

  property var machines: []
  property var state: Model.emptyState()
  property string configError: ""
  property string actionError: ""
  property bool loading: false

  property string attentionKey: ""
  property var wantingBefore: ({})
  property bool attentionPrimed: false

  property var probeResult: null
  property bool probing: false
  property string probingKey: ""

  property bool refreshPending: false

  property var pathTried: ({})

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property var totals: (root.state && root.state.totals) ? root.state.totals
    : Model.emptyState().totals
  readonly property string badgeState: Model.badgeState(root.totals)
  readonly property bool badgeActive: root.badgeState !== ""
  readonly property int badgeCount: Model.badgeCount(root.totals)
  readonly property bool anyUnreachable: Model.unreachable(root.state || Model.emptyState()).length > 0

  readonly property int refreshSec: Math.max(3, Number(root.setting("refreshSec", 15)) || 15)
  readonly property int openRefreshSec: Math.max(2, Number(root.setting("openRefreshSec", 4)) || 4)

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent

  readonly property string herdrConfigPath:
    (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/herdr/config.toml"
  readonly property string themeColorsPath: home + "/.local/state/omarchy/current/theme/colors.toml"
  property string herdrConfigText: ""
  property string themeColorsText: ""
  readonly property var herdrColors: Model.herdrPalette(root.herdrConfigText, root.themeColorsText)

  function reloadColors() {
    herdrConfigFile.reload()
    themeColorsFile.reload()
  }

  function stateColor(status) {
    var raw = root.herdrColors[status] || root.herdrColors.unknown
    return Model.readable(raw, String(Commons.Color.background))
  }
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var mirroredProperties: ["bar", "settings", "machines", "state",
    "configError", "actionError", "loading", "attentionKey", "probeResult", "probing", "herdrColors"]

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    for (var i = 0; i < root.mirroredProperties.length; i++) {
      var name = root.mirroredProperties[i]
      if (!(name in target)) continue
      try {
        target[name] = root[name]
      } catch (e) {
        console.warn("herdr: could not mirror " + name + ": " + e)
      }
    }
  }

  function peers() {
    var items = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : []
    return items && items.length > 0 ? items : [root]
  }

  function leader() {
    var items = root.peers()
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i].adoptHerd === "function") return items[i]
    }
    return root
  }

  function isLeader() {
    return root.leader() === root
  }

  function adoptHerd(state, attentionKey, loading) {
    root.state = state
    root.attentionKey = attentionKey
    root.loading = loading
    root.injectPanel()
  }

  function shareHerd() {
    var items = root.peers()
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i] !== root && typeof items[i].adoptHerd === "function")
        items[i].adoptHerd(root.state, root.attentionKey, root.loading)
    }
  }

  function badgeColor() {
    if (root.badgeState === "") return root.foreground
    return root.stateColor(root.badgeState)
  }

  function tooltip() {
    if (root.configError !== "") return "machines.json: " + root.configError
    return Model.plain(Model.summary(root.state || Model.emptyState()))
  }

  function loadConfig(raw) {
    var parsed = Model.parseConfig(raw)
    root.configError = parsed.error
    if (parsed.error === "" || root.machines.length === 0) root.machines = parsed.machines
    root.injectPanel()
    Qt.callLater(root.refresh)
    Qt.callLater(root.fillNextHerdrPath)
  }

  function fillNextHerdrPath() {
    if (!root.isLeader()) return
    if (pathProc.running) return
    for (var i = 0; i < (root.machines || []).length; i++) {
      var machine = root.machines[i]
      if (root.pathTried[machine.id] === Model.targetLabel(machine)) continue
      if (machine.herdrPath === "" && machine.enabled) {
        root.fillHerdrPath(machine.id)
        return
      }
    }
  }

  function writeConfig() {
    configFile.setText(Model.serializeConfig(root.machines))
  }

  function saveMachines(next) {
    if (root.configError !== "")
      return "machines.json has an error in it (" + root.configError + "). Fix it by hand first."
    root.machines = next
    root.writeConfig()
    root.injectPanel()
    return ""
  }

  function addMachine(fields) {
    var problem = Model.validate(fields, root.machines, "")
    if (problem !== "") return problem
    var machine = Model.buildMachine(fields, root.machines)
    if (!machine) return "That machine cannot be stored as written."
    var saved = root.saveMachines(root.machines.concat([machine]))
    if (saved !== "") return saved
    Qt.callLater(function() { root.fillHerdrPath(machine.id) })
    return ""
  }

  function editMachine(id, fields) {
    var problem = Model.validate(fields, root.machines, id)
    if (problem !== "") return problem
    var before = Model.findMachine(root.machines, id)
    var next = {}
    for (var key in fields) next[key] = fields[key]
    if (before && Model.clip(next.herdrPath) === before.herdrPath
        && Model.targetLabel(before) !== Model.targetLabel({
             host: Model.clip(next.host), user: Model.clip(next.user), port: Model.intOr(Model.clip(next.port), 0)
           }))
      next.herdrPath = ""
    var saved = root.saveMachines(Model.updateMachine(root.machines, id, next))
    if (saved !== "") return saved
    Qt.callLater(function() { root.fillHerdrPath(id) })
    return ""
  }

  function removeMachine(id) {
    var saved = root.saveMachines(Model.withoutMachine(root.machines, id))
    if (saved !== "") { root.actionError = saved; root.injectPanel(); return }
    root.refresh()
  }

  function openRow(machineId, session, pane) {
    if (!Model.validMachineId(machineId)) return
    if (!Model.validSessionName(session)) return
    if (pane !== undefined && pane !== "" && !Model.validPaneId(pane)) return
    if (openProc.running) return
    root.actionError = ""
    var args = [root.ctlPath, "open", machineId, session]
    if (pane !== undefined && pane !== "") args.push(pane)
    openProc.command = args
    openProc.running = true
  }

  function probe(fields) {
    if (root.probing) return
    var key = Model.probeKey(fields)
    var problem = Model.validate(fields, [], "")
    if (problem !== "") {
      root.probeResult = { key: key, reachable: false, error: problem, errorText: problem }
      root.injectPanel()
      return
    }
    root.probing = true
    root.probingKey = key
    root.probeResult = null
    root.injectPanel()
    probeProc.command = [root.ctlPath, "probe", Model.clip(fields.host),
      Model.clip(fields.port), Model.clip(fields.user), Model.clip(fields.identityFile),
      String(Model.intOr(Model.clip(fields.connectTimeoutSec), Model.DEFAULT_TIMEOUT)),
      Model.clip(fields.herdrPath)]
    probeProc.running = true
  }

  function clearProbe() {
    root.probeResult = null
    root.injectPanel()
  }

  function applyProbe(text, errText, code) {
    root.probing = false
    var result = null
    try {
      result = JSON.parse(String(text || ""))
    } catch (e) {
      result = null
    }
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      result = { reachable: false,
        error: code === 0 ? "bad-json" : (Model.clip(errText) || Model.clip(text) || "unreachable") }
    }
    result.key = root.probingKey
    result.errorText = Model.errorText(result.error)
    root.probingKey = ""
    root.probeResult = result
    root.injectPanel()
  }

  function fillHerdrPath(id) {
    var lead = root.leader()
    if (lead !== root) { lead.fillHerdrPath(id); return }
    var machine = Model.findMachine(root.machines, id)
    if (!machine || machine.herdrPath !== "") { root.refresh(); return }
    if (pathProc.running) return
    var tried = {}
    for (var key in root.pathTried) tried[key] = root.pathTried[key]
    tried[id] = Model.targetLabel(machine)
    root.pathTried = tried
    pathProc.machineId = id
    pathProc.target = Model.targetLabel(machine)
    pathProc.command = [root.ctlPath, "probe", machine.host, machine.port > 0 ? String(machine.port) : "",
      machine.user, machine.identityFile, String(machine.connectTimeoutSec), ""]
    pathProc.running = true
  }

  function applyHerdrPath(id, target, text) {
    var result = null
    try {
      result = JSON.parse(String(text || ""))
    } catch (e) {
      result = null
    }
    var machine = Model.findMachine(root.machines, id)
    if (machine && Model.targetLabel(machine) !== target) machine = null
    if (result && machine && machine.herdrPath === "" && Model.clip(result.herdrPath) !== ""
        && Model.validHerdrPath(Model.clip(result.herdrPath))) {
      var fields = {
        label: machine.label, host: machine.host,
        port: machine.port > 0 ? String(machine.port) : "",
        user: machine.user, identityFile: machine.identityFile,
        herdrPath: Model.clip(result.herdrPath),
        connectTimeoutSec: String(machine.connectTimeoutSec)
      }
      root.saveMachines(Model.updateMachine(root.machines, id, fields))
    }
    root.refresh()
    Qt.callLater(root.fillNextHerdrPath)
  }

  function install(id) {
    var machine = Model.findMachine(root.machines, id)
    if (!machine) return
    root.actionError = ""
    Quickshell.execDetached([root.ctlPath, "install", machine.host,
      machine.port > 0 ? String(machine.port) : "", machine.user,
      machine.identityFile, String(machine.connectTimeoutSec)])
  }

  function refresh() {
    var lead = root.leader()
    if (lead !== root) { lead.refresh(); return }
    if (snapshotProc.running) { root.refreshPending = true; return }
    root.refreshPending = false
    root.loading = true
    snapshotProc.command = [root.ctlPath, "snapshot"]
    snapshotProc.running = true
    snapshotWatchdog.restart()
    root.shareHerd()
  }

  function applySnapshot(text, errText, code) {
    snapshotWatchdog.stop()
    root.loading = false
    var next = Model.parseSnapshot(text)
    if (!next.ok && next.error === "" && code !== 0)
      next.error = Model.errorText(Model.clip(errText) || "unknown-command")

    if (next.ok) {
      var now = Model.carryWanting(root.wantingBefore, next)
      if (root.attentionPrimed) {
        var spoke = Model.spokeLast(root.wantingBefore, next)
        if (spoke !== "") root.attentionKey = spoke
      } else {
        root.attentionPrimed = true
      }
      root.wantingBefore = now
    }

    if (root.attentionKey !== "" && root.wantingBefore[root.attentionKey] === undefined) {
      root.attentionKey = ""
    }

    root.state = next
    root.injectPanel()
    root.shareHerd()
    if (root.refreshPending) Qt.callLater(root.refresh)
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
    root.refresh()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  onBarChanged: root.injectPanel()
  onSettingsChanged: root.injectPanel()
  onOpenedChanged: {
    root.leader().notePanels()
    if (root.opened) { root.refresh(); root.reloadColors() }
  }
  onHerdrColorsChanged: root.injectPanel()

  property bool anyOpened: false
  function notePanels() {
    var items = root.peers()
    var open = false
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].opened === true) open = true
    root.anyOpened = open
  }

  Component.onCompleted: ensureFileProc.running = true

  readonly property int barContentWidth: Style.bar.iconFont + Style.space(4)
  readonly property int barSlot: barContentWidth + Style.space(10)

  implicitWidth: root.vertical ? root.barSize : root.barSlot
  implicitHeight: root.vertical ? root.barSlot : root.barSize

  Timer {
    interval: ((root.opened || root.anyOpened) ? root.openRefreshSec : (root.badgeActive ? root.refreshSec : root.refreshSec * 2)) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (root.isLeader()) root.refresh()
  }

  Timer {
    id: snapshotWatchdog
    interval: (Model.MAX_TIMEOUT * 3 + 30) * 1000
    repeat: false
    onTriggered: if (snapshotProc.running) snapshotProc.running = false
  }

  FileView {
    id: herdrConfigFile
    path: root.herdrConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.herdrConfigText = text()
    onLoadFailed: root.herdrConfigText = ""
  }

  FileView {
    id: themeColorsFile
    path: root.themeColorsPath
    watchChanges: false
    printErrors: false
    onLoaded: root.themeColorsText = text()
    onLoadFailed: root.themeColorsText = ""
  }

  Connections {
    target: Commons.Color
    function onBackgroundChanged() { themeColorsFile.reload() }
    function onForegroundChanged() { themeColorsFile.reload() }
    function onAccentChanged() { themeColorsFile.reload() }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("")
  }

  Process {
    id: ensureFileProc
    command: ["sh", "-c",
      'mkdir -p -- "$1" && { [ -e "$2" ] || printf \'{\\n  "version": 1,\\n  "machines": []\\n}\\n\' > "$2"; }',
      "_", root.configDir, root.configPath]
    onExited: configFile.reload()
  }

  Process {
    id: snapshotProc
    property string outText: ""
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: snapshotProc.outText = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: snapshotProc.errText = text }
    onExited: function(code) {
      root.applySnapshot(snapshotProc.outText, snapshotProc.errText, code)
      snapshotProc.outText = ""
      snapshotProc.errText = ""
    }
  }

  Process {
    id: openProc
    property string errText: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: openProc.errText = text }
    onExited: function(code) {
      root.actionError = code === 0 ? "" : Model.errorText(Model.clip(openProc.errText))
      openProc.errText = ""
      root.injectPanel()
      refreshSoon.restart()
    }
  }

  Process {
    id: probeProc
    property string outText: ""
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: probeProc.outText = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: probeProc.errText = text }
    onExited: function(code) {
      root.applyProbe(probeProc.outText, probeProc.errText, code)
      probeProc.outText = ""
      probeProc.errText = ""
    }
  }

  Process {
    id: pathProc
    property string machineId: ""
    property string target: ""
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: pathProc.outText = text }
    onExited: function(code) {
      var id = pathProc.machineId
      var target = pathProc.target
      var text = code === 0 ? pathProc.outText : ""
      pathProc.outText = ""
      pathProc.machineId = ""
      pathProc.target = ""
      root.applyHerdrPath(id, target, text)
    }
  }

  Timer {
    id: refreshSoon
    interval: 1200
    repeat: false
    onTriggered: root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.majkelll.herdr"
    function list(): string { return Model.summary(root.state || Model.emptyState()) }
    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function jump(machine: string, session: string): void { root.openRow(machine, session, "") }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    opticalSize: root.barContentWidth
    opacity: root.anyUnreachable ? 0.65 : 1
    active: root.badgeState === "blocked" || root.configError !== ""
    tooltipText: root.tooltip()

    iconComponent: Component {
      Item {
        Text {
          id: glyph
          anchors.centerIn: parent
          text: root.anyUnreachable ? Model.GLYPH.machineOff : Model.GLYPH.machine
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering
          color: root.opened ? root.accent : root.foreground
        }

        Rectangle {
          id: badge
          anchors.horizontalCenter: glyph.horizontalCenter
          anchors.horizontalCenterOffset: Math.round(Style.bar.iconFont * 0.42)
          anchors.verticalCenter: glyph.verticalCenter
          anchors.verticalCenterOffset: -Math.round(Style.bar.iconFont * 0.40)
          visible: root.badgeActive && root.badgeCount > 0
          height: Math.round(Style.bar.iconFont * 0.95)
          width: Math.max(height, countText.implicitWidth + Math.round(height * 0.45))
          radius: height / 2
          color: root.badgeColor()
          border.width: Math.round(Style.bar.iconFont * 0.06)
          border.color: Commons.Color.bar.background

          Text {
            id: countText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(font.pixelSize * 0.1)
            text: String(root.badgeCount)
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Math.round((badge.height - 2 * badge.border.width) * 0.88)
            font.bold: true
            renderType: Text.NativeRendering
            color: Model.textOn(String(badge.color), String(Commons.Color.background),
              String(Commons.Color.foreground))
          }
        }
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) {
        root.refresh()
        return
      }
      root.toggle()
    }
  }
}
