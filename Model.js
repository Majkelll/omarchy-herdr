var MAX_INPUT = 4 * 1024 * 1024
var MAX_FIELD = 512
var MAX_MACHINES = 32
var MAX_SESSIONS = 64
var MAX_AGENTS = 200

var MIN_TIMEOUT = 2
var MAX_TIMEOUT = 60
var DEFAULT_TIMEOUT = 6
var DEFAULT_PORT = 22

var LOCAL_ID = "local"
var LOCAL_LABEL = "This machine"

var GLYPH = {
  machine: "󰌘",
  machineOff: "󰌙",
  local: "󰟀",
  add: "󰐕",
  edit: "󰏫",
  remove: "󰩺",
  refresh: "󰑐",
  open: "󰆍",
  copy: "󰆏",
  alert: "󰀦"
}

var INSTALL_COMMAND = "curl -fsSL https://herdr.dev/install.sh | sh"

var STATUS_ORDER = { blocked: 0, done: 1, working: 2, idle: 3 }

var ERRORS = {
  "config-unreadable": "machines.json cannot be read",
  "bad-machine": "that machine is not in the list",
  "bad-session": "that session name is not one herdr would produce",
  "bad-pane": "that pane id is not one herdr would produce",
  "no-terminal": "no terminal emulator found to open a window with",
  "herdr-missing": "herdr is not installed on that machine",
  "unreachable": "ssh could not reach that machine",
  "auth-failed": "ssh was refused: set up key-based access first",
  "host-key": "the host key is unknown, connect once by hand to accept it",
  "timeout": "that machine did not answer in time",
  "no-server": "herdr is installed there but no server is running",
  "too-large": "that machine answered with more data than is safe to read",
  "bad-json": "that machine answered with something that is not herdr JSON",
  "unknown-command": "the helper was called with a command it does not have",
  "bad-host": "that host has characters an ssh target cannot have",
  "bad-user": "that user name has characters ssh will not take",
  "bad-port": "a port is a number between 1 and 65535",
  "bad-path": "the herdr path must be an absolute path or a plain command name",
  "bad-identity": "the identity file must be a plain path, with no spaces",
  "missing-jq": "jq is not installed on this machine",
  "missing-ps": "ps is not installed on this machine",
  "missing-timeout": "timeout (coreutils) is not installed on this machine",
  "no-tmpdir": "no temporary directory could be created",
  "no-bash": "bash is not installed on that machine"
}

function has(table, key) {
  return Object.prototype.hasOwnProperty.call(table, key)
}

var HERDR_STATE_TOKEN = { working: "yellow", blocked: "red", done: "teal", idle: "green", unknown: "overlay0" }

var HERDR_THEMES = {
  "catppuccin": { green: "#a6e3a1", yellow: "#f9e2af", red: "#f38ba8", teal: "#94e2d5", overlay0: "#6c7086" },
  "catppuccin-latte": { green: "#40a02b", yellow: "#df8e1d", red: "#d20f39", teal: "#179299", overlay0: "#9ca0b0" },
  "terminal": { green: "green", yellow: "yellow", red: "lightred", teal: "cyan", overlay0: "gray" },
  "tokyo-night": { green: "#9ece6a", yellow: "#e0af68", red: "#f7768e", teal: "#7dcfff", overlay0: "#565f89" },
  "tokyo-night-day": { green: "#587539", yellow: "#8c6c3e", red: "#f52a65", teal: "#118c74", overlay0: "#8990b3" },
  "dracula": { green: "#50fa7b", yellow: "#f1fa8c", red: "#ff5555", teal: "#8be9fd", overlay0: "#6272a4" },
  "nord": { green: "#a3be8c", yellow: "#ebcb8b", red: "#bf616a", teal: "#8fbcbb", overlay0: "#4c566a" },
  "gruvbox": { green: "#b8bb26", yellow: "#fabd2f", red: "#fb4934", teal: "#8ec07c", overlay0: "#928374" },
  "gruvbox-light": { green: "#79740e", yellow: "#b57614", red: "#9d0006", teal: "#427b58", overlay0: "#928374" },
  "one-dark": { green: "#98c379", yellow: "#e5c07b", red: "#e06c75", teal: "#56b6c2", overlay0: "#5c6370" },
  "one-light": { green: "#50a14f", yellow: "#c18401", red: "#e45649", teal: "#0184bc", overlay0: "#a0a1a7" },
  "solarized": { green: "#859900", yellow: "#b58900", red: "#dc322f", teal: "#2aa198", overlay0: "#586e75" },
  "solarized-light": { green: "#859900", yellow: "#b58900", red: "#dc322f", teal: "#2aa198", overlay0: "#93a1a1" },
  "kanagawa": { green: "#76946a", yellow: "#c0a36e", red: "#c34043", teal: "#7fb4ca", overlay0: "#727169" },
  "kanagawa-lotus": { green: "#6f894e", yellow: "#77713f", red: "#c84053", teal: "#4e8ca2", overlay0: "#a09cac" },
  "rose-pine": { green: "#31748f", yellow: "#f6c177", red: "#eb6f92", teal: "#9ccfd8", overlay0: "#6e6a86" },
  "rose-pine-dawn": { green: "#286983", yellow: "#ea9d34", red: "#b4637a", teal: "#56949f", overlay0: "#9893a5" },
  "vesper": { green: "#99ffe4", yellow: "#ffc799", red: "#ff8080", teal: "#66ddcc", overlay0: "#5c5c5c" }
}

var HERDR_THEME_ALIASES = {
  "catppuccin-mocha": "catppuccin", "latte": "catppuccin-latte", "light": "catppuccin-latte",
  "tokyonight": "tokyo-night", "tokyo-day": "tokyo-night-day", "tokyonight-day": "tokyo-night-day",
  "gruvbox-dark": "gruvbox", "onedark": "one-dark", "onelight": "one-light",
  "solarized-dark": "solarized", "lotus": "kanagawa-lotus", "rosepine": "rose-pine",
  "rosepine-dawn": "rose-pine-dawn", "dawn": "rose-pine-dawn"
}

var HERDR_THEME_PAIRS = [
  ["catppuccin", "catppuccin-latte"], ["tokyo-night", "tokyo-night-day"], ["gruvbox", "gruvbox-light"],
  ["one-dark", "one-light"], ["solarized", "solarized-light"], ["kanagawa", "kanagawa-lotus"],
  ["rose-pine", "rose-pine-dawn"]
]

var ANSI_INDEX = {
  black: 0, red: 1, green: 2, yellow: 3, blue: 4, magenta: 5, purple: 5, cyan: 6, gray: 7, grey: 7,
  darkgray: 8, darkgrey: 8, lightred: 9, lightgreen: 10, lightyellow: 11, lightblue: 12,
  lightmagenta: 13, lightcyan: 14, white: 15
}

var ANSI_FALLBACK = ["#000000", "#cd0000", "#00cd00", "#cdcd00", "#0000ee", "#cd00cd", "#00cdcd", "#e5e5e5",
  "#7f7f7f", "#ff0000", "#00ff00", "#ffff00", "#5c5cff", "#ff00ff", "#00ffff", "#ffffff"]

var OMARCHY_ANSI = ["background", "red", "green", "yellow", "blue", "magenta", "cyan", "foreground",
  "muted", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan",
  "bright_foreground"]

function parseTomlFlat(text) {
  var out = {}
  var lines = String(text || "").split(/\r?\n/)
  var section = ""
  for (var i = 0; i < lines.length && i < 20000; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (line === "" || line.charAt(0) === "#") continue
    var head = line.match(/^\[\s*([A-Za-z0-9_.-]+)\s*\]\s*(#.*)?$/)
    if (head) { section = head[1]; continue }
    var kv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([A-Za-z0-9_#.-]+))\s*(#.*)?$/)
    if (!kv) continue
    var value = kv[2] !== undefined ? kv[2] : (kv[3] !== undefined ? kv[3] : kv[4])
    out[(section === "" ? "" : section + ".") + kv[1]] = String(value)
  }
  return out
}

function hexOf(value) {
  var text = String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  var m = text.match(/^#([0-9a-f]{6})$/)
  if (m) return "#" + m[1]
  m = text.match(/^#[0-9a-f]{2}([0-9a-f]{6})$/)
  if (m) return "#" + m[1]
  m = text.match(/^#([0-9a-f])([0-9a-f])([0-9a-f])$/)
  if (m) return "#" + m[1] + m[1] + m[2] + m[2] + m[3] + m[3]
  m = text.match(/^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$/)
  if (m) {
    var parts = [m[1], m[2], m[3]]
    var hex = "#"
    for (var i = 0; i < 3; i++) {
      var n = parseInt(parts[i], 10)
      if (n > 255) return ""
      hex += (n < 16 ? "0" : "") + n.toString(16)
    }
    return hex
  }
  return ""
}

function ansiPalette(colorsToml) {
  var values = parseTomlFlat(colorsToml)
  var palette = []
  for (var i = 0; i < 16; i++) {
    var hex = hexOf(values["color" + i]) || hexOf(values[OMARCHY_ANSI[i]])
    if (!hex && i === 15) hex = hexOf(values["foreground"])
    if (!hex && i === 8) hex = hexOf(values["foreground"])
    palette.push(hex || ANSI_FALLBACK[i])
  }
  return palette
}

function herdrColor(value, ansi) {
  var text = String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "" || text === "reset" || text === "default" || text === "none" || text === "transparent") return ""
  var hex = hexOf(text)
  if (hex) return hex
  if (has(ANSI_INDEX, text)) return (ansi || ANSI_FALLBACK)[ANSI_INDEX[text]]
  return (ansi || ANSI_FALLBACK)[6]
}

function canonicalTheme(name) {
  var key = String(name || "").replace(/^\s+|\s+$/g, "").toLowerCase().replace(/[ _]/g, "-")
  if (has(HERDR_THEMES, key)) return key
  if (has(HERDR_THEME_ALIASES, key)) return HERDR_THEME_ALIASES[key]
  return ""
}

function themeSibling(name, light) {
  var key = canonicalTheme(name) || String(name || "")
  for (var i = 0; i < HERDR_THEME_PAIRS.length; i++) {
    if (HERDR_THEME_PAIRS[i][0] === key || HERDR_THEME_PAIRS[i][1] === key)
      return HERDR_THEME_PAIRS[i][light ? 1 : 0]
  }
  return key
}

function luminance(hex) {
  var h = hexOf(hex)
  if (!h) return 0
  var channels = [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]
  for (var i = 0; i < 3; i++) {
    var c = channels[i] / 255
    channels[i] = c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
}

function contrast(a, b) {
  var la = luminance(a), lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

function mix(a, b, amount) {
  var x = hexOf(a), y = hexOf(b)
  if (!x || !y) return x || y
  var out = "#"
  for (var i = 1; i < 7; i += 2) {
    var n = Math.round(parseInt(x.substr(i, 2), 16) * (1 - amount) + parseInt(y.substr(i, 2), 16) * amount)
    out += (n < 16 ? "0" : "") + n.toString(16)
  }
  return out
}

function readable(color, background, minimum) {
  var fg = hexOf(color), bg = hexOf(background)
  if (!fg || !bg) return fg || String(color || "")
  var target = minimum || 3
  if (contrast(fg, bg) >= target) return fg
  var toward = luminance(bg) < 0.5 ? "#ffffff" : "#000000"
  for (var step = 1; step <= 10; step++) {
    var moved = mix(fg, toward, step / 10)
    if (contrast(moved, bg) >= target) return moved
  }
  return toward
}

function textOn(fill, dark, light) {
  var best = contrast(fill, dark) >= contrast(fill, light) ? hexOf(dark) : hexOf(light)
  if (best && contrast(fill, best) >= 3) return best
  return contrast(fill, "#000000") >= contrast(fill, "#ffffff") ? "#000000" : "#ffffff"
}

function herdrPalette(herdrToml, colorsToml) {
  var config = parseTomlFlat(herdrToml)
  var colors = parseTomlFlat(colorsToml)
  var ansi = ansiPalette(colorsToml)

  var mode = String(colors["mode"] || "").toLowerCase()
  var light = mode === "light" || (mode !== "dark" && hexOf(colors["background"]) !== ""
    && luminance(colors["background"]) > 0.5)

  var manual = config["theme.name"] || "catppuccin"
  var name = manual
  var fallback = "catppuccin"
  var modeSection = ""
  if (String(config["theme.auto_switch"]).toLowerCase() === "true") {
    name = light ? (config["theme.light_name"] || themeSibling(manual, true))
                 : (config["theme.dark_name"] || themeSibling(manual, false))
    fallback = light ? "catppuccin-latte" : "catppuccin"
    modeSection = light ? "theme.custom.light." : "theme.custom.dark."
  }
  var theme = canonicalTheme(name) || fallback

  var out = { theme: theme, indicators: "dots" }
  var tokens = ["green", "yellow", "red", "teal", "overlay0"]
  var resolved = {}
  for (var i = 0; i < tokens.length; i++) {
    var token = tokens[i]
    var raw = HERDR_THEMES[theme][token]
    if (has(config, "theme.custom." + token)) raw = config["theme.custom." + token]
    if (modeSection !== "" && has(config, modeSection + token)) raw = config[modeSection + token]
    resolved[token] = herdrColor(raw, ansi) || ansi[7]
  }
  for (var state in HERDR_STATE_TOKEN) {
    if (has(HERDR_STATE_TOKEN, state)) out[state] = resolved[HERDR_STATE_TOKEN[state]]
  }
  if (String(config["ui.status_indicators"]).toLowerCase() === "symbols") out.indicators = "symbols"
  return out
}

function stateMark(status, indicators) {
  var symbols = indicators === "symbols"
  if (status === "blocked") return symbols ? "×" : "●"
  if (status === "working") return symbols ? "◐" : "●"
  if (status === "done") return symbols ? "✓" : "●"
  if (status === "idle") return "○"
  return "·"
}

function clip(value) {
  var text = String(value === undefined || value === null ? "" : value)
  text = text.replace(
    /[\x00-\x1f\x7f-\x9f\xad\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u2064\u2066-\u2069\ufeff\ufff9-\ufffb]/g, "")
  text = text.trim()
  if (text.length > MAX_FIELD) text = text.slice(0, MAX_FIELD)
  var last = text.charCodeAt(text.length - 1)
  if (last >= 0xd800 && last <= 0xdbff) text = text.slice(0, -1)
  return text
}

function plain(value) {
  return clip(value).replace(/[<>]/g, "")
}

function intOr(value, fallback) {
  if (typeof value === "number")
    return isFinite(value) && Math.floor(value) === value && Math.abs(value) <= 9007199254740991
      ? value : fallback
  var text = String(value === undefined || value === null ? "" : value).trim()
  if (!/^[+-]?\d{1,15}$/.test(text)) return fallback
  return parseInt(text, 10)
}

function validSessionName(name) {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(String(name || ""))
}

function validPaneId(pane) {
  return /^[A-Za-z0-9_-]{1,32}:[A-Za-z0-9_-]{1,32}$/.test(String(pane || ""))
}

function validMachineId(id) {
  return /^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$/.test(String(id || ""))
}

function validHost(host) {
  return /^[A-Za-z0-9][A-Za-z0-9._@:-]{0,254}$/.test(String(host || ""))
}

function validUser(user) {
  return user === "" || /^[A-Za-z0-9._][A-Za-z0-9._-]{0,63}$/.test(String(user || ""))
}

function validHerdrPath(path) {
  if (path === "") return true
  return /^(\/[A-Za-z0-9._\/-]{1,255}|[A-Za-z0-9._][A-Za-z0-9._-]{0,63})$/.test(String(path || ""))
}

function validIdentity(path) {
  if (path === "") return true
  return /^[A-Za-z0-9._~\/][A-Za-z0-9._~\/-]{0,254}$/.test(String(path || ""))
}

function parseConfig(text) {
  var raw = String(text || "")
  if (raw.length > MAX_INPUT) return { machines: [], error: ERRORS["too-large"] }
  if (raw.trim() === "") return { machines: [], error: "" }

  var parsed
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    return { machines: [], error: "not valid JSON: " + String(e.message || e) }
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    return { machines: [], error: "not a JSON object" }

  var list = parsed.machines
  if (list === undefined || list === null) list = []
  if (!Array.isArray(list)) return { machines: [], error: "\"machines\" is not a list" }

  var machines = []
  for (var i = 0; i < list.length && machines.length < MAX_MACHINES; i++) {
    var machine = normalizeMachine(list[i])
    if (machine && !findMachine(machines, machine.id)) machines.push(machine)
  }
  return { machines: machines, error: "" }
}

function normalizeMachine(entry) {
  if (!entry || typeof entry !== "object") return null
  var id = clip(entry.id)
  var host = clip(entry.host)
  if (!validMachineId(id) || id === LOCAL_ID) return null
  if (!validHost(host)) return null

  var user = clip(entry.user)
  if (!validUser(user)) user = ""
  var herdrPath = clip(entry.herdrPath)
  if (!validHerdrPath(herdrPath)) herdrPath = ""

  var port = intOr(entry.port, 0)
  if (port < 1 || port > 65535) port = 0

  var timeout = intOr(entry.connectTimeoutSec, DEFAULT_TIMEOUT)
  if (timeout < MIN_TIMEOUT) timeout = MIN_TIMEOUT
  if (timeout > MAX_TIMEOUT) timeout = MAX_TIMEOUT

  return {
    id: id,
    label: clip(entry.label) || host,
    host: host,
    port: port,
    user: user,
    identityFile: clip(entry.identityFile),
    herdrPath: herdrPath,
    connectTimeoutSec: timeout,
    enabled: entry.enabled !== false
  }
}

function serializeConfig(machines) {
  var list = []
  for (var i = 0; i < machines.length && i < MAX_MACHINES; i++) {
    var machine = normalizeMachine(machines[i])
    if (machine) list.push(machine)
  }
  return JSON.stringify({ version: 1, machines: list }, null, 2) + "\n"
}

function findMachine(machines, id) {
  for (var i = 0; i < machines.length; i++) if (machines[i].id === id) return machines[i]
  return null
}

function makeId(label, host, machines) {
  var base = clip(label || host).toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "")
  if (base === "" || !/^[a-z0-9]/.test(base)) base = "m" + (base === "" ? "" : "-" + base)
  base = base.slice(0, 24)
  var candidate = base
  var n = 2
  while (candidate === LOCAL_ID || findMachine(machines || [], candidate)) {
    candidate = base.slice(0, 20) + "-" + n
    n++
  }
  return candidate
}

function validate(fields, machines, editingId) {
  var host = clip(fields.host)
  var label = clip(fields.label)
  if (host === "") return "A host is needed: a name, an address, or an alias from ~/.ssh/config."
  if (!validHost(host)) return "That host has characters an ssh target cannot have."
  if (label.length > 64) return "That name is too long."

  var port = clip(fields.port)
  if (port !== "" && (!/^\d{1,5}$/.test(port) || intOr(port, 0) < 1 || intOr(port, 0) > 65535))
    return "A port is a number between 1 and 65535."

  var user = clip(fields.user)
  if (!validUser(user)) return "That user name has characters ssh will not take."

  var herdrPath = clip(fields.herdrPath)
  if (!validHerdrPath(herdrPath))
    return "The herdr path must be an absolute path or a plain command name."

  var identity = clip(fields.identityFile)
  if (!validIdentity(identity))
    return "The identity file must be a plain path, with no spaces in it."

  if (user !== "" && host.indexOf("@") !== -1)
    return "Give the user in the User field or in the host, not both."

  var timeout = clip(fields.connectTimeoutSec)
  if (timeout !== "" && (!/^\d{1,3}$/.test(timeout)
      || intOr(timeout, 0) < MIN_TIMEOUT || intOr(timeout, 0) > MAX_TIMEOUT))
    return "A timeout is between " + MIN_TIMEOUT + " and " + MAX_TIMEOUT + " seconds."

  var list = machines || []
  for (var i = 0; i < list.length; i++) {
    if (editingId && list[i].id === editingId) continue
    if (target(list[i]).toLowerCase() === target({ host: host, user: user }).toLowerCase()
        && (list[i].port || DEFAULT_PORT) === (intOr(port, 0) || DEFAULT_PORT))
      return "That machine is already in the list, as \"" + list[i].label + "\"."
  }
  if (list.length >= MAX_MACHINES && !editingId)
    return "That is as many machines as this widget holds."
  return ""
}

function buildMachine(fields, machines) {
  var host = clip(fields.host)
  return normalizeMachine({
    id: makeId(fields.label, host, machines),
    label: clip(fields.label) || host,
    host: host,
    port: intOr(fields.port, 0),
    user: clip(fields.user),
    identityFile: clip(fields.identityFile),
    herdrPath: clip(fields.herdrPath),
    connectTimeoutSec: intOr(fields.connectTimeoutSec, DEFAULT_TIMEOUT),
    enabled: true
  })
}

function updateMachine(machines, id, fields) {
  var next = []
  for (var i = 0; i < machines.length; i++) {
    if (machines[i].id !== id) { next.push(machines[i]); continue }
    var merged = normalizeMachine({
      id: id,
      label: clip(fields.label) || clip(fields.host),
      host: clip(fields.host),
      port: intOr(fields.port, 0),
      user: clip(fields.user),
      identityFile: clip(fields.identityFile),
      herdrPath: clip(fields.herdrPath),
      connectTimeoutSec: intOr(fields.connectTimeoutSec, machines[i].connectTimeoutSec),
      enabled: machines[i].enabled
    })
    next.push(merged || machines[i])
  }
  return next
}

function withoutMachine(machines, id) {
  var next = []
  for (var i = 0; i < machines.length; i++) if (machines[i].id !== id) next.push(machines[i])
  return next
}

function target(machine) {
  if (!machine) return ""
  var host = clip(machine.host)
  var user = clip(machine.user)
  return user === "" ? host : user + "@" + host
}

function targetLabel(machine) {
  if (!machine) return ""
  var text = target(machine)
  var port = intOr(machine.port, 0)
  if (port > 0 && port !== DEFAULT_PORT) text += ":" + port
  return text
}

function emptyState() {
  return {
    ok: false,
    error: "",
    machines: [],
    totals: { machines: 0, servers: 0, agents: 0, blocked: 0, done: 0, working: 0 }
  }
}

function parseSnapshot(text) {
  var raw = String(text || "")
  if (raw.trim() === "") return emptyState()
  if (raw.length > MAX_INPUT) {
    var tooBig = emptyState()
    tooBig.error = ERRORS["too-large"]
    return tooBig
  }

  var parsed
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    var bad = emptyState()
    bad.error = ERRORS["bad-json"]
    return bad
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    var notObject = emptyState()
    notObject.error = ERRORS["bad-json"]
    return notObject
  }

  var machines = []
  var list = Array.isArray(parsed.machines) ? parsed.machines : []
  for (var i = 0; i < list.length && machines.length <= MAX_MACHINES; i++) {
    var view = normalizeView(list[i])
    if (view && !findMachine(machines, view.id)) machines.push(view)
  }

  var state = {
    ok: parsed.ok === true,
    error: errorText(parsed.error),
    machines: machines,
    totals: totalsOf(machines)
  }
  return state
}

function normalizeView(entry) {
  if (!entry || typeof entry !== "object") return null
  var machine = entry
  var id = clip(machine.id)
  if (!validMachineId(id)) return null
  var sessions = []
  var list = Array.isArray(machine.sessions) ? machine.sessions : []
  for (var i = 0; i < list.length && i < MAX_SESSIONS; i++) {
    sessions.push(normalizeSession(list[i]))
  }
  sessions.sort(function(a, b) {
    if (a.isDefault !== b.isDefault) return a.isDefault ? -1 : 1
    if (a.running !== b.running) return a.running ? -1 : 1
    return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
  })

  return {
    id: id,
    label: clip(machine.label) || (id === LOCAL_ID ? LOCAL_LABEL : id),
    remote: machine.remote === true,
    target: clip(machine.target),
    enabled: machine.enabled !== false,
    reachable: machine.reachable === true,
    error: errorText(machine.error),
    errorCode: clip(machine.error),
    version: clip(machine.version),
    sessions: sessions,
    counts: countsOf(sessions)
  }
}

function normalizeSession(entry) {
  var session = entry && typeof entry === "object" ? entry : {}
  var agents = []
  var list = Array.isArray(session.agents) ? session.agents : []
  for (var i = 0; i < list.length && i < MAX_AGENTS; i++) {
    var agent = list[i] && typeof list[i] === "object" ? list[i] : {}
    var title = plain(agent.title)
    if (title === "") continue
    agents.push({
      pane: clip(agent.pane),
      title: title,
      status: statusOf(agent.status),
      workspace: plain(agent.workspace),
      seq: typeof agent.seq === "number" && isFinite(agent.seq) ? Math.floor(agent.seq) : intOr(agent.seq, 0)
    })
  }
  agents.sort(function(a, b) { return rank(a.status) - rank(b.status) })

  var projects = []
  var rawProjects = Array.isArray(session.projects) ? session.projects : []
  for (var p = 0; p < rawProjects.length && p < 24; p++) {
    var name = plain(rawProjects[p])
    if (name !== "" && projects.indexOf(name) === -1) projects.push(name)
  }

  return {
    name: clip(session.name),
    isDefault: session.isDefault === true,
    running: session.running === true,
    window: clip(session.window),
    projects: projects,
    agents: agents
  }
}

function statusOf(value) {
  var status = clip(value).toLowerCase()
  return has(STATUS_ORDER, status) ? status : "idle"
}

function rank(status) {
  return has(STATUS_ORDER, status) ? STATUS_ORDER[status] : 4
}

function countsOf(sessions) {
  var counts = { running: 0, agents: 0, blocked: 0, done: 0, working: 0, idle: 0 }
  for (var i = 0; i < sessions.length; i++) {
    if (sessions[i].running) counts.running++
    var agents = sessions[i].agents
    for (var a = 0; a < agents.length; a++) {
      counts.agents++
      if (has(STATUS_ORDER, agents[a].status)) counts[agents[a].status]++
    }
  }
  return counts
}

function totalsOf(machines) {
  var totals = { machines: machines.length, servers: 0, agents: 0, blocked: 0, done: 0, working: 0 }
  for (var i = 0; i < machines.length; i++) {
    totals.servers += machines[i].counts.running
    totals.agents += machines[i].counts.agents
    totals.blocked += machines[i].counts.blocked
    totals.done += machines[i].counts.done
    totals.working += machines[i].counts.working
  }
  return totals
}

function badgeState(totals) {
  if (!totals) return ""
  if (totals.blocked > 0) return "blocked"
  if (totals.done > 0) return "done"
  if (totals.working > 0) return "working"
  return ""
}

function badgeCount(totals) {
  if (!totals) return 0
  if (totals.blocked > 0) return totals.blocked
  if (totals.done > 0) return totals.done
  if (totals.working > 0) return totals.working
  return totals.servers
}

function unreachable(state) {
  var names = []
  for (var i = 0; i < state.machines.length; i++) {
    var machine = state.machines[i]
    if (machine.enabled && !machine.reachable) names.push(machine.label)
  }
  return names
}

function summary(state) {
  if (!state) return "Herdr"
  if (state.error !== "") return state.error
  var totals = state.totals
  if (totals.machines === 0) return "No machines yet"

  var parts = []
  parts.push(count(totals.servers, "server", "servers"))
  if (totals.machines > 1) parts.push("on " + count(totals.machines, "machine", "machines"))
  if (totals.agents > 0) parts.push(count(totals.agents, "agent", "agents"))
  if (totals.blocked > 0) parts.push(totals.blocked + " waiting on you")
  else if (totals.done > 0) parts.push(totals.done + " finished")
  else if (totals.working > 0) parts.push(totals.working + " working")

  var down = unreachable(state)
  if (down.length > 0) parts.push(down.join(", ") + (down.length === 1 ? " is unreachable" : " are unreachable"))
  return parts.join(" · ")
}

function count(n, one, many) {
  return n + " " + (n === 1 ? one : many)
}

function sessionLine(session) {
  if (!session.running) return "stopped"
  var parts = []
  if (session.projects.length > 0) parts.push(session.projects.join(", "))
  var agents = session.agents.length
  parts.push(agents === 0 ? "no agents" : count(agents, "agent", "agents"))
  return parts.join(" · ")
}

function machineLine(machine) {
  if (!machine.enabled) return "disabled"
  if (!machine.reachable) return machine.error !== "" ? machine.error : ERRORS["unreachable"]
  var parts = []
  if (machine.target !== "") parts.push(machine.target)
  parts.push(count(machine.counts.running, "server", "servers"))
  if (machine.counts.agents > 0) parts.push(count(machine.counts.agents, "agent", "agents"))
  if (machine.version !== "") parts.push("herdr " + machine.version)
  return parts.join(" · ")
}

function errorText(code) {
  var key = clip(code)
  if (key === "") return ""
  return has(ERRORS, key) ? ERRORS[key] : key
}

function rows(state, collapsed) {
  var folded = collapsed || {}
  var list = []
  for (var i = 0; i < state.machines.length; i++) {
    var machine = state.machines[i]
    var isFolded = folded[machine.id] === true
    list.push({
      kind: "machine",
      machine: machine.id,
      session: "",
      pane: "",
      label: machine.label,
      line: machineLine(machine),
      status: machine.enabled && !machine.reachable ? "unreachable" : "",
      remote: machine.remote,
      enabled: machine.enabled,
      reachable: machine.reachable,
      errorCode: machine.errorCode || "",
      collapsed: isFolded,
      sessions: machine.sessions.length
    })
    if (isFolded) continue
    for (var s = 0; s < machine.sessions.length; s++) {
      var session = machine.sessions[s]
      list.push({
        kind: "session",
        machine: machine.id,
        session: session.name,
        pane: "",
        label: session.name,
        line: sessionLine(session),
        status: sessionStatus(session),
        showing: session.window !== ""
      })
      for (var a = 0; a < session.agents.length; a++) {
        var agent = session.agents[a]
        list.push({
          kind: "agent",
          machine: machine.id,
          session: session.name,
          pane: agent.pane,
          label: agent.title,
          line: agent.workspace,
          status: agent.status,
          key: key(machine.id, session.name, agent.pane)
        })
      }
    }
  }
  return list
}

function sessionStatus(session) {
  if (!session.running) return "stopped"
  var best = "idle"
  var bestRank = 9
  for (var i = 0; i < session.agents.length; i++) {
    var r = rank(session.agents[i].status)
    if (r < bestRank) { bestRank = r; best = session.agents[i].status }
  }
  return session.agents.length === 0 ? "empty" : best
}

function bestRow(state, collapsed) {
  var all = rows(state, collapsed || {})
  var best = -1
  var bestRank = 99
  for (var i = 0; i < all.length; i++) {
    if (all[i].kind !== "agent") continue
    var r = rank(all[i].status)
    if (r < bestRank) { bestRank = r; best = i }
    if (bestRank === 0) break
  }
  if (best >= 0 && bestRank <= 1) return best
  for (var j = 0; j < all.length; j++) if (all[j].kind === "session") return j
  return 0
}

function actionable(row) {
  if (!row) return false
  if (!validMachineId(row.machine)) return false
  if (row.kind === "machine") return true
  if (!validSessionName(row.session)) return false
  if (row.kind === "session") return true
  return validPaneId(row.pane)
}

function wanting(state) {
  var set = {}
  for (var i = 0; i < state.machines.length; i++) {
    var machine = state.machines[i]
    for (var s = 0; s < machine.sessions.length; s++) {
      var session = machine.sessions[s]
      for (var a = 0; a < session.agents.length; a++) {
        var agent = session.agents[a]
        if (agent.status !== "blocked" && agent.status !== "done") continue
        set[key(machine.id, session.name, agent.pane)] = agent.status
      }
    }
  }
  return set
}

function key(machine, session, pane) {
  return machine + "\u0000" + session + "\u0000" + pane
}

function spokeLast(previous, state) {
  if (!previous) return ""
  var now = wanting(state)
  var best = ""
  var bestSeq = -1
  for (var k in now) {
    if (has(previous, k) && previous[k] === now[k]) continue
    var seq = seqFor(state, k)
    if (seq > bestSeq) { bestSeq = seq; best = k }
  }
  return best
}

function carryWanting(previous, state) {
  var now = wanting(state)
  if (!previous) return now
  var down = {}
  for (var i = 0; i < state.machines.length; i++) {
    if (!state.machines[i].reachable) down[state.machines[i].id] = true
  }
  for (var k in previous) {
    if (!has(previous, k) || has(now, k)) continue
    var machine = String(k).split("\u0000")[0]
    if (has(down, machine)) now[k] = previous[k]
  }
  return now
}

function probeKey(fields) {
  var f = fields || {}
  return [clip(f.host), clip(f.port), clip(f.user), clip(f.identityFile), clip(f.herdrPath)]
    .join("\u0000")
}

function seqFor(state, wantedKey) {
  for (var i = 0; i < state.machines.length; i++) {
    var machine = state.machines[i]
    for (var s = 0; s < machine.sessions.length; s++) {
      var session = machine.sessions[s]
      for (var a = 0; a < session.agents.length; a++) {
        if (key(machine.id, session.name, session.agents[a].pane) === wantedKey)
          return session.agents[a].seq
      }
    }
  }
  return -1
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_INPUT: MAX_INPUT,
    MAX_FIELD: MAX_FIELD,
    MAX_MACHINES: MAX_MACHINES,
    MIN_TIMEOUT: MIN_TIMEOUT,
    MAX_TIMEOUT: MAX_TIMEOUT,
    DEFAULT_TIMEOUT: DEFAULT_TIMEOUT,
    DEFAULT_PORT: DEFAULT_PORT,
    LOCAL_ID: LOCAL_ID,
    LOCAL_LABEL: LOCAL_LABEL,
    GLYPH: GLYPH,
    INSTALL_COMMAND: INSTALL_COMMAND,
    ERRORS: ERRORS,
    clip: clip,
    plain: plain,
    validSessionName: validSessionName,
    validPaneId: validPaneId,
    validMachineId: validMachineId,
    validHost: validHost,
    validUser: validUser,
    validHerdrPath: validHerdrPath,
    validIdentity: validIdentity,
    intOr: intOr,
    parseConfig: parseConfig,
    normalizeMachine: normalizeMachine,
    serializeConfig: serializeConfig,
    findMachine: findMachine,
    makeId: makeId,
    validate: validate,
    buildMachine: buildMachine,
    updateMachine: updateMachine,
    withoutMachine: withoutMachine,
    target: target,
    targetLabel: targetLabel,
    emptyState: emptyState,
    parseSnapshot: parseSnapshot,
    badgeState: badgeState,
    badgeCount: badgeCount,
    unreachable: unreachable,
    summary: summary,
    sessionLine: sessionLine,
    machineLine: machineLine,
    errorText: errorText,
    rows: rows,
    sessionStatus: sessionStatus,
    bestRow: bestRow,
    actionable: actionable,
    wanting: wanting,
    spokeLast: spokeLast,
    carryWanting: carryWanting,
    probeKey: probeKey,
    HERDR_THEMES: HERDR_THEMES,
    parseTomlFlat: parseTomlFlat,
    hexOf: hexOf,
    ansiPalette: ansiPalette,
    herdrColor: herdrColor,
    canonicalTheme: canonicalTheme,
    contrast: contrast,
    readable: readable,
    textOn: textOn,
    herdrPalette: herdrPalette,
    stateMark: stateMark
  }
}
