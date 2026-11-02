const { describe, test } = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

function snapshotText(overrides) {
  const base = {
    ok: true,
    error: "",
    machines: [
      {
        id: "local",
        label: "This machine",
        remote: false,
        target: "",
        enabled: true,
        reachable: true,
        error: "",
        version: "0.8.2",
        sessions: [
          {
            name: "default",
            isDefault: true,
            running: true,
            window: "0xabc",
            workspace: "4",
            projects: ["manaw", "ChessLab"],
            agents: [
              { pane: "w1:p1", title: "idle one", status: "idle", workspace: "ChessLab", seq: 3 },
              { pane: "w2:p1", title: "waiting one", status: "blocked", workspace: "manaw", seq: 9 },
              { pane: "w3:p1", title: "busy one", status: "working", workspace: "manaw", seq: 7 }
            ]
          }
        ]
      },
      {
        id: "lab",
        label: "lab",
        remote: true,
        target: "dev@192.0.2.10",
        enabled: true,
        reachable: true,
        error: "",
        version: "0.9.1",
        sessions: [
          {
            name: "default",
            isDefault: true,
            running: true,
            window: "",
            workspace: "",
            projects: ["Repos"],
            agents: [
              { pane: "w1:p1", title: "finished one", status: "done", workspace: "Repos", seq: 12 }
            ]
          }
        ]
      }
    ]
  }
  return JSON.stringify(Object.assign(base, overrides || {}))
}

describe("clip and plain", () => {
  test("trims, truncates, and strips control characters", () => {
    assert.equal(Model.clip("  spaced  "), "spaced")
    assert.equal(Model.clip("a\nb\tc\x00d\x7fe"), "abcde")
    assert.equal(Model.clip("x".repeat(Model.MAX_FIELD + 50)).length, Model.MAX_FIELD)
    assert.equal(Model.clip(undefined), "")
    assert.equal(Model.clip(null), "")
  })

  test("plain drops the two characters a rich-text tooltip would read", () => {
    assert.equal(Model.plain("<b>bold</b>"), "bbold/b")
  })
})

describe("shapes on the wire", () => {
  test("session names are what herdr produces and nothing else", () => {
    assert.ok(Model.validSessionName("default"))
    assert.ok(Model.validSessionName("work-2.a_b"))
    assert.ok(!Model.validSessionName(""))
    assert.ok(!Model.validSessionName(".hidden"))
    assert.ok(!Model.validSessionName("a b"))
    assert.ok(!Model.validSessionName("a;rm -rf /"))
    assert.ok(!Model.validSessionName("x".repeat(65)))
  })

  test("pane ids are two runs around one colon", () => {
    assert.ok(Model.validPaneId("w1:p2"))
    assert.ok(Model.validPaneId("wC:p1"))
    assert.ok(!Model.validPaneId("w1"))
    assert.ok(!Model.validPaneId("w1:p2:p3"))
    assert.ok(!Model.validPaneId("w1:p2 x"))
  })

  test("hosts refuse anything a shell would read as more than a host", () => {
    assert.ok(Model.validHost("192.0.2.10"))
    assert.ok(Model.validHost("build-box"))
    assert.ok(Model.validHost("user@host"))
    assert.ok(!Model.validHost(""))
    assert.ok(!Model.validHost("a b"))
    assert.ok(!Model.validHost("host;id"))
    assert.ok(!Model.validHost("host$(id)"))
    assert.ok(!Model.validHost("-oProxyCommand=id"))
  })

  test("a herdr path is absolute or a bare command name", () => {
    assert.ok(Model.validHerdrPath(""))
    assert.ok(Model.validHerdrPath("herdr"))
    assert.ok(Model.validHerdrPath("/home/dev/.local/bin/herdr"))
    assert.ok(!Model.validHerdrPath("~/bin/herdr"))
    assert.ok(!Model.validHerdrPath("/bin/herdr; id"))
  })
})

describe("parseConfig", () => {
  test("no file is the first run, not an error", () => {
    const parsed = Model.parseConfig("")
    assert.deepEqual(parsed.machines, [])
    assert.equal(parsed.error, "")
  })

  test("unparseable JSON says so and keeps the list empty", () => {
    const parsed = Model.parseConfig("{oops")
    assert.deepEqual(parsed.machines, [])
    assert.match(parsed.error, /not valid JSON/)
  })

  test("a machines key that is not a list is refused", () => {
    assert.match(Model.parseConfig('{"machines":{}}').error, /not a list/)
  })

  test("entries missing an id or a host are dropped", () => {
    const parsed = Model.parseConfig(JSON.stringify({
      machines: [
        { id: "ok", host: "h1" },
        { host: "h2" },
        { id: "no host" },
        { id: "bad id!", host: "h3" },
        { id: "local", host: "h4" }
      ]
    }))
    assert.deepEqual(parsed.machines.map(m => m.id), ["ok"])
  })

  test("values out of range come back inside it", () => {
    const parsed = Model.parseConfig(JSON.stringify({
      machines: [{ id: "m", host: "h", port: 99999, connectTimeoutSec: 999, enabled: false }]
    }))
    assert.equal(parsed.machines[0].port, 0)
    assert.equal(parsed.machines[0].connectTimeoutSec, Model.MAX_TIMEOUT)
    assert.equal(parsed.machines[0].enabled, false)
  })

  test("the label falls back to the host", () => {
    const parsed = Model.parseConfig(JSON.stringify({ machines: [{ id: "m", host: "build-box" }] }))
    assert.equal(parsed.machines[0].label, "build-box")
  })

  test("more machines than the ceiling are cut off", () => {
    const many = []
    for (let i = 0; i < Model.MAX_MACHINES + 10; i++) many.push({ id: "m" + i, host: "h" + i })
    assert.equal(Model.parseConfig(JSON.stringify({ machines: many })).machines.length, Model.MAX_MACHINES)
  })

  test("serialize and parse round trip", () => {
    const machines = Model.parseConfig(JSON.stringify({
      machines: [{ id: "m", host: "h", port: 2222, user: "dev", connectTimeoutSec: 8 }]
    })).machines
    const again = Model.parseConfig(Model.serializeConfig(machines)).machines
    assert.deepEqual(again, machines)
  })
})

describe("validate", () => {
  const existing = [{
    id: "a", label: "A", host: "h1", port: 0, user: "", identityFile: "",
    herdrPath: "", connectTimeoutSec: 6, enabled: true
  }]

  test("a host is required", () => {
    assert.match(Model.validate({ host: "" }, [], ""), /host is needed/)
  })

  test("a host with shell characters is refused", () => {
    assert.match(Model.validate({ host: "h;id" }, [], ""), /characters an ssh target cannot have/)
  })

  test("a port out of range is refused", () => {
    assert.match(Model.validate({ host: "h", port: "70000" }, [], ""), /between 1 and 65535/)
    assert.match(Model.validate({ host: "h", port: "abc" }, [], ""), /between 1 and 65535/)
    assert.equal(Model.validate({ host: "h", port: "" }, [], ""), "")
  })

  test("a timeout out of range is refused", () => {
    assert.match(Model.validate({ host: "h", connectTimeoutSec: "1" }, [], ""), /timeout is between/)
    assert.equal(Model.validate({ host: "h", connectTimeoutSec: "10" }, [], ""), "")
  })

  test("the same target twice is refused, and editing it is not", () => {
    assert.match(Model.validate({ host: "h1" }, existing, ""), /already in the list/)
    assert.equal(Model.validate({ host: "h1" }, existing, "a"), "")
  })

  test("a different port on the same host is a different machine", () => {
    assert.equal(Model.validate({ host: "h1", port: "2222" }, existing, ""), "")
  })

  test("a bad herdr path is refused", () => {
    assert.match(Model.validate({ host: "h", herdrPath: "~/bin/herdr" }, [], ""),
      /absolute path or a plain command name/)
  })
})

describe("building machines", () => {
  test("an id reads like the label it came from", () => {
    const machine = Model.buildMachine({ label: "Build Box", host: "h" }, [])
    assert.equal(machine.id, "build-box")
  })

  test("a colliding id gets a counter, never the reserved local id", () => {
    const first = Model.buildMachine({ label: "box", host: "h1" }, [])
    const second = Model.buildMachine({ label: "box", host: "h2" }, [first])
    assert.equal(second.id, "box-2")
    assert.notEqual(Model.makeId("local", "h", []), "local")
  })

  test("a label of only punctuation still produces a usable id", () => {
    const machine = Model.buildMachine({ label: "!!!", host: "192.0.2.9" }, [])
    assert.ok(Model.validMachineId(machine.id))
  })

  test("edit keeps the id and replaces the fields", () => {
    const machines = [Model.buildMachine({ label: "box", host: "h1" }, [])]
    const next = Model.updateMachine(machines, machines[0].id, {
      label: "box", host: "h2", port: "2222", user: "dev", identityFile: "", herdrPath: "", connectTimeoutSec: "9"
    })
    assert.equal(next[0].id, machines[0].id)
    assert.equal(next[0].host, "h2")
    assert.equal(next[0].port, 2222)
    assert.equal(next[0].connectTimeoutSec, 9)
  })

  test("remove", () => {
    const machines = [Model.buildMachine({ label: "box", host: "h1" }, [])]
    assert.deepEqual(Model.withoutMachine(machines, machines[0].id), [])
  })

  test("the target is what ssh is handed, and the label says the port too", () => {
    const machine = Model.buildMachine({ label: "box", host: "h", port: "2222", user: "dev" }, [])
    assert.equal(Model.target(machine), "dev@h")
    assert.equal(Model.targetLabel(machine), "dev@h:2222")
  })
})

describe("parseSnapshot", () => {
  test("nothing yet is the empty state", () => {
    const state = Model.parseSnapshot("")
    assert.equal(state.ok, false)
    assert.deepEqual(state.machines, [])
    assert.equal(state.totals.agents, 0)
  })

  test("something that is not JSON says so rather than throwing", () => {
    assert.equal(Model.parseSnapshot("not json").error, Model.ERRORS["bad-json"])
  })

  test("machines, sessions and agents come through", () => {
    const state = Model.parseSnapshot(snapshotText())
    assert.equal(state.ok, true)
    assert.equal(state.machines.length, 2)
    assert.equal(state.machines[0].version, "0.8.2")
    assert.equal(state.machines[1].target, "dev@192.0.2.10")
    assert.equal(state.machines[0].sessions[0].agents.length, 3)
  })

  test("agents sort by what needs an answer first", () => {
    const state = Model.parseSnapshot(snapshotText())
    assert.deepEqual(state.machines[0].sessions[0].agents.map(a => a.status),
      ["blocked", "working", "idle"])
  })

  test("an agent without a title is not a row", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [{ id: "local", sessions: [{ name: "default", running: true,
        agents: [{ pane: "w1:p1", title: "" }, { pane: "w2:p1", title: "real" }] }] }]
    }))
    assert.equal(state.machines[0].sessions[0].agents.length, 1)
  })

  test("an unknown status is read as idle", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [{ id: "local", sessions: [{ name: "default", running: true,
        agents: [{ pane: "w1:p1", title: "t", status: "who-knows" }] }] }]
    }))
    assert.equal(state.machines[0].sessions[0].agents[0].status, "idle")
  })

  test("totals count every machine together", () => {
    const totals = Model.parseSnapshot(snapshotText()).totals
    assert.equal(totals.machines, 2)
    assert.equal(totals.servers, 2)
    assert.equal(totals.agents, 4)
    assert.equal(totals.blocked, 1)
    assert.equal(totals.done, 1)
    assert.equal(totals.working, 1)
  })

  test("an error code becomes the sentence that explains it", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [{ id: "m", remote: true, enabled: true, reachable: false, error: "herdr-missing" }]
    }))
    assert.equal(state.machines[0].error, Model.ERRORS["herdr-missing"])
  })

  test("the default session sorts above the rest", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [{ id: "local", sessions: [
        { name: "zed", running: true }, { name: "default", isDefault: true, running: true }] }]
    }))
    assert.deepEqual(state.machines[0].sessions.map(s => s.name), ["default", "zed"])
  })
})

describe("what the bar says", () => {
  test("the badge names the most urgent thing anywhere", () => {
    assert.equal(Model.badgeState({ blocked: 1, done: 2, working: 3 }), "blocked")
    assert.equal(Model.badgeState({ blocked: 0, done: 2, working: 3 }), "done")
    assert.equal(Model.badgeState({ blocked: 0, done: 0, working: 3 }), "working")
    assert.equal(Model.badgeState({ blocked: 0, done: 0, working: 0 }), "")
  })

  test("the count belongs to the state the badge is showing", () => {
    assert.equal(Model.badgeCount({ blocked: 2, done: 5, working: 9, servers: 3 }), 2)
    assert.equal(Model.badgeCount({ blocked: 0, done: 0, working: 0, servers: 3 }), 3)
  })

  test("the summary says what is running and what is waiting", () => {
    const state = Model.parseSnapshot(snapshotText())
    const text = Model.summary(state)
    assert.match(text, /2 servers/)
    assert.match(text, /on 2 machines/)
    assert.match(text, /1 waiting on you/)
  })

  test("an unreachable machine is named in the summary", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [
        { id: "local", reachable: true, sessions: [] },
        { id: "box", label: "box", remote: true, enabled: true, reachable: false, error: "unreachable", sessions: [] }]
    }))
    assert.deepEqual(Model.unreachable(state), ["box"])
    assert.match(Model.summary(state), /box is unreachable/)
  })

  test("a machine line says why it cannot be reached", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [{ id: "box", label: "box", remote: true, enabled: true,
        reachable: false, error: "auth-failed", sessions: [] }]
    }))
    assert.equal(Model.machineLine(state.machines[0]), Model.ERRORS["auth-failed"])
  })

  test("a stopped session says so instead of listing nothing", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [{ id: "local", sessions: [{ name: "old", running: false }] }]
    }))
    assert.equal(Model.sessionLine(state.machines[0].sessions[0]), "stopped")
  })

  test("an unknown error code is passed through rather than swallowed", () => {
    assert.equal(Model.errorText("something-new"), "something-new")
    assert.equal(Model.errorText(""), "")
  })
})

describe("rows", () => {
  test("one row per machine, session and agent, in drawing order", () => {
    const state = Model.parseSnapshot(snapshotText())
    const rows = Model.rows(state, {})
    assert.deepEqual(rows.map(r => r.kind),
      ["machine", "session", "agent", "agent", "agent", "machine", "session", "agent"])
    assert.equal(rows[0].machine, "local")
    assert.equal(rows[1].session, "default")
    assert.equal(rows[2].pane, "w2:p1")
  })

  test("a folded machine keeps its own row and loses the rest", () => {
    const state = Model.parseSnapshot(snapshotText())
    const rows = Model.rows(state, { local: true })
    assert.deepEqual(rows.map(r => r.kind), ["machine", "machine", "session", "agent"])
    assert.equal(rows[0].collapsed, true)
  })

  test("a session takes the state of the most urgent agent in it", () => {
    const state = Model.parseSnapshot(snapshotText())
    assert.equal(Model.sessionStatus(state.machines[0].sessions[0]), "blocked")
    assert.equal(Model.sessionStatus(state.machines[1].sessions[0]), "done")
    assert.equal(Model.sessionStatus({ running: false, agents: [] }), "stopped")
    assert.equal(Model.sessionStatus({ running: true, agents: [] }), "empty")
  })

  test("a session row knows whether a window is already showing it", () => {
    const state = Model.parseSnapshot(snapshotText())
    const rows = Model.rows(state, {})
    assert.equal(rows[1].showing, true)
    assert.equal(rows[6].showing, false)
  })

  test("the cursor starts on what is waiting on you", () => {
    const state = Model.parseSnapshot(snapshotText())
    const rows = Model.rows(state, {})
    assert.equal(rows[Model.bestRow(state)].pane, "w2:p1")
  })

  test("with nothing waiting it starts on the first session", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [{ id: "local", sessions: [{ name: "default", running: true,
        agents: [{ pane: "w1:p1", title: "busy", status: "working" }] }] }]
    }))
    assert.equal(Model.rows(state, {})[Model.bestRow(state)].kind, "session")
  })

  test("a row is only actionable when every name in it is one herdr would produce", () => {
    assert.ok(Model.actionable({ kind: "machine", machine: "local" }))
    assert.ok(Model.actionable({ kind: "session", machine: "local", session: "default" }))
    assert.ok(Model.actionable({ kind: "agent", machine: "local", session: "default", pane: "w1:p1" }))
    assert.ok(!Model.actionable({ kind: "agent", machine: "local", session: "default", pane: "w1" }))
    assert.ok(!Model.actionable({ kind: "session", machine: "local", session: "a b" }))
    assert.ok(!Model.actionable({ kind: "machine", machine: "bad id" }))
    assert.ok(!Model.actionable(null))
  })
})

describe("who just spoke", () => {
  test("only blocked and done count as wanting something", () => {
    const state = Model.parseSnapshot(snapshotText())
    const set = Model.wanting(state)
    assert.equal(Object.keys(set).length, 2)
  })

  test("the first reading primes, the next one names who changed", () => {
    const before = Model.wanting(Model.parseSnapshot(snapshotText()))
    const later = Model.parseSnapshot(JSON.stringify(JSON.parse(snapshotText({
      machines: JSON.parse(snapshotText()).machines
    }))))
    later.machines[0].sessions[0].agents.push(
      { pane: "w9:p1", title: "new voice", status: "blocked", workspace: "x", seq: 20 })
    assert.equal(Model.spokeLast(before, later), "local\u0000default\u0000w9:p1")
  })

  test("nothing new means nothing blinks", () => {
    const state = Model.parseSnapshot(snapshotText())
    assert.equal(Model.spokeLast(Model.wanting(state), state), "")
  })

  test("two new voices at once go to whichever spoke last", () => {
    const state = Model.parseSnapshot(snapshotText())
    state.machines[0].sessions[0].agents.push(
      { pane: "w8:p1", title: "first", status: "blocked", workspace: "x", seq: 30 },
      { pane: "w9:p1", title: "second", status: "done", workspace: "x", seq: 31 })
    assert.equal(Model.spokeLast({}, state), "local\u0000default\u0000w9:p1")
  })
})

describe("hostile and hand-written input", () => {
  test("names off Object.prototype are not statuses or error codes", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, error: "constructor", machines: [{ id: "local", reachable: true, error: "__proto__",
        sessions: [{ name: "default", running: true,
          agents: [{ pane: "w1:p1", title: "t", status: "constructor" }] }] }]
    }))
    assert.equal(state.error, "constructor")
    assert.equal(state.machines[0].error, "__proto__")
    assert.equal(state.machines[0].sessions[0].agents[0].status, "idle")
    assert.equal(state.machines[0].counts.idle, 1)
    for (const value of Object.values(state.machines[0].counts)) assert.ok(Number.isFinite(value))
    assert.equal(typeof Model.summary(state), "string")
  })

  test("a status in capitals is still that status", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [{ id: "local", reachable: true, sessions: [{ name: "default", running: true,
        agents: [{ pane: "w1:p1", title: "t", status: "BLOCKED" }] }] }]
    }))
    assert.equal(state.totals.blocked, 1)
  })

  test("a snapshot that is a list, or holds no machines list, is not drawn", () => {
    assert.equal(Model.parseSnapshot("[1,2]").error, Model.ERRORS["bad-json"])
    assert.deepEqual(Model.parseSnapshot('{"ok":true,"machines":"no"}').machines, [])
  })

  test("a machine without an id is dropped, and so is a second with the same one", () => {
    const state = Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [{ label: "nameless" }, { id: "a" }, { id: "a", label: "again" }, null]
    }))
    assert.deepEqual(state.machines.map(m => m.id), ["a"])
    assert.equal(state.machines[0].label, "a")
  })

  test("a config that is a list is refused", () => {
    const parsed = Model.parseConfig('[{"id":"a","host":"h"}]')
    assert.notEqual(parsed.error, "")
  })

  test("an id written twice keeps its first row, and removing it leaves the rest", () => {
    const parsed = Model.parseConfig(JSON.stringify({ machines: [
      { id: "box", host: "h1" }, { id: "box", host: "h2" }, { id: "other", host: "h3" }] }))
    assert.deepEqual(parsed.machines.map(m => m.host), ["h1", "h3"])
    assert.deepEqual(Model.withoutMachine(parsed.machines, "box").map(m => m.id), ["other"])
  })

  test("numbers are whole numbers written as such", () => {
    assert.equal(Model.intOr("22", 0), 22)
    assert.equal(Model.intOr(" 08 ", 0), 8)
    assert.equal(Model.intOr(1e21, 0), 0)
    assert.equal(Model.intOr("1e3", 0), 0)
    assert.equal(Model.intOr("22abc", 0), 0)
    assert.equal(Model.intOr(22.5, 7), 7)
    assert.equal(Model.normalizeMachine({ id: "a", host: "h", port: 1e21 }).port, 0)
  })

  test("a field cut at the limit never ends on half a character", () => {
    const text = Model.clip("a" + "😀".repeat(300))
    const last = text.charCodeAt(text.length - 1)
    assert.ok(!(last >= 0xd800 && last <= 0xdbff))
    assert.ok(text.length <= Model.MAX_FIELD)
  })

  test("invisible formatting and C1 controls are stripped", () => {
    assert.equal(Model.clip("a‮b​c\u0085d⁦e"), "abcde")
  })
})

describe("the form agrees with the helper", () => {
  const fields = (over) => Object.assign({ label: "", host: "box", port: "", user: "",
    identityFile: "", herdrPath: "", connectTimeoutSec: "" }, over)

  test("an identity file with a space in it is refused", () => {
    assert.match(Model.validate(fields({ identityFile: "/home/u/my key" }), [], ""), /identity/)
    assert.equal(Model.validate(fields({ identityFile: "~/.ssh/id_ed25519" }), [], ""), "")
  })

  test("an identity file that starts like an option is refused", () => {
    assert.equal(Model.validIdentity("-oProxyCommand=x"), false)
  })

  test("a herdr path that starts like an option is refused", () => {
    assert.equal(Model.validHerdrPath("--version"), false)
    assert.equal(Model.validHerdrPath("herdr"), true)
    assert.equal(Model.validHerdrPath(".local-herdr"), true)
  })

  test("a user in the host and in its own field is refused", () => {
    assert.notEqual(Model.validate(fields({ host: "a@box", user: "b" }), [], ""), "")
    assert.equal(Model.validate(fields({ host: "a@box" }), [], ""), "")
  })

  test("the same target written two ways is the same machine", () => {
    const machines = [Model.buildMachine(fields({ host: "a@box" }), [])]
    assert.match(Model.validate(fields({ host: "box", user: "a" }), machines, ""), /already/)
  })

  test("the same host in other letters is the same machine", () => {
    const machines = [Model.buildMachine(fields({ host: "Box" }), [])]
    assert.match(Model.validate(fields({ host: "box" }), machines, ""), /already/)
  })

  test("the ceiling applies to an add with no editing id at all", () => {
    const machines = []
    for (let i = 0; i < Model.MAX_MACHINES; i++) machines.push(Model.buildMachine(fields({ host: "h" + i }), machines))
    assert.notEqual(Model.validate(fields({ host: "new" }), machines, undefined), "")
    assert.equal(Model.validate(fields({ host: "h3" }), machines, machines[3].id), "")
  })

  test("every error code the helper prints has a sentence", () => {
    const codes = ["bad-host", "bad-user", "bad-port", "bad-path", "bad-identity",
      "missing-jq", "missing-ps", "missing-timeout", "no-tmpdir", "no-bash", "too-large"]
    for (const code of codes) assert.notEqual(Model.errorText(code), code, code)
  })

  test("a probe answer is about the fields it was asked with", () => {
    const asked = fields({ host: "box", port: "22" })
    assert.equal(Model.probeKey(asked), Model.probeKey(fields({ host: " box ", port: "22" })))
    assert.notEqual(Model.probeKey(asked), Model.probeKey(fields({ host: "other", port: "22" })))
  })
})

describe("the cursor and the blink", () => {
  function herd() {
    return Model.parseSnapshot(JSON.stringify({
      ok: true, machines: [
        { id: "local", reachable: true, sessions: [
          { name: "a", running: true, agents: [{ pane: "w1:p1", title: "one", status: "idle" }] },
          { name: "b", running: true, agents: [{ pane: "w1:p1", title: "two", status: "idle" }] }] },
        { id: "dev", remote: true, reachable: true, sessions: [
          { name: "x", running: true, agents: [{ pane: "w1:p1", title: "asks", status: "blocked" }] }] }]
    }))
  }

  test("the best row is counted over the rows as folded", () => {
    const state = herd()
    const folded = { local: true }
    const rows = Model.rows(state, folded)
    const index = Model.bestRow(state, folded)
    assert.equal(rows[index].label, "asks")
  })

  test("with nothing at all the best row is the first", () => {
    assert.equal(Model.bestRow(Model.emptyState()), 0)
  })

  test("an agent that goes from done to blocked has spoken again", () => {
    const state = herd()
    const key = "dev\u0000x\u0000w1:p1"
    assert.equal(Model.spokeLast({ [key]: "done" }, state), key)
    assert.equal(Model.spokeLast({ [key]: "blocked" }, state), "")
  })

  test("no previous reading means nothing blinks", () => {
    assert.equal(Model.spokeLast(null, herd()), "")
  })

  test("a machine that dropped out keeps what it was waiting on", () => {
    const before = Model.wanting(herd())
    const down = herd()
    down.machines[1].reachable = false
    down.machines[1].sessions = []
    const carried = Model.carryWanting(before, down)
    assert.equal(carried["dev\u0000x\u0000w1:p1"], "blocked")
    assert.equal(Model.spokeLast(carried, herd()), "")
  })

  test("a machine that was removed takes what it was waiting on with it", () => {
    const before = Model.wanting(herd())
    const removed = herd()
    removed.machines.pop()
    assert.deepEqual(Model.carryWanting(before, removed), {})
  })

  test("an answered agent on a machine that did answer is let go", () => {
    const before = Model.wanting(herd())
    const answered = herd()
    answered.machines[1].sessions[0].agents[0].status = "working"
    assert.deepEqual(Model.carryWanting(before, answered), {})
  })

  test("a machine without herdr is told apart, for the copy-the-install-command button", () => {
    const state = Model.parseSnapshot(JSON.stringify({ ok: true, machines: [
      { id: "a", remote: true, enabled: true, reachable: false, error: "herdr-missing" },
      { id: "b", remote: true, enabled: true, reachable: false, error: "auth-failed" }] }))
    const rows = Model.rows(state, {})
    assert.deepEqual(rows.map(r => r.errorCode), ["herdr-missing", "auth-failed"])
  })

  test("the install command to copy is herdr's own installer, for the user to run", () => {
    assert.equal(Model.INSTALL_COMMAND, "curl -fsSL https://herdr.dev/install.sh | sh")
  })
})

describe("herdr's colours", () => {
  const tokyo = `mode = "dark"
background = "#1a1b26"
foreground = "#a9b1d6"
muted = "#414868"
red = "#f7768e"
yellow = "#e0af68"
green = "#9ece6a"
cyan = "#449dab"
blue = "#7aa2f7"
magenta = "#ad8ee6"
bright_red = "#ff7a93"
bright_yellow = "#ff9e64"
bright_green = "#b9f27c"
bright_cyan = "#0db9d7"
bright_blue = "#7da6ff"
bright_magenta = "#bb9af7"
bright_foreground = "#c0caf5"
`
  const white = `mode = "light"
background = "#ffffff"
foreground = "#000000"
`

  test("no herdr config is herdr's default theme, catppuccin", () => {
    const palette = Model.herdrPalette("", tokyo)
    assert.equal(palette.theme, "catppuccin")
    assert.equal(palette.done, "#94e2d5")
    assert.equal(palette.indicators, "dots")
  })

  test("each state takes the token herdr gives it", () => {
    const palette = Model.herdrPalette('[theme]\nname = "nord"\n', tokyo)
    const nord = Model.HERDR_THEMES.nord
    assert.equal(palette.working, nord.yellow)
    assert.equal(palette.blocked, nord.red)
    assert.equal(palette.done, nord.teal)
    assert.equal(palette.idle, nord.green)
    assert.equal(palette.unknown, nord.overlay0)
  })

  test("the terminal theme is the terminal's palette, which Omarchy's theme sets", () => {
    const palette = Model.herdrPalette('[theme]\nname = "terminal"\n[theme.custom]\npanel_bg = "black"\n', tokyo)
    assert.equal(palette.working, "#e0af68")
    assert.equal(palette.blocked, "#ff7a93")
    assert.equal(palette.done, "#449dab")
    assert.equal(palette.idle, "#9ece6a")
    assert.equal(palette.unknown, "#a9b1d6")
  })

  test("theme names are read the way herdr reads them", () => {
    assert.equal(Model.herdrPalette('[theme]\nname = "Tokyo Night"\n', "").theme, "tokyo-night")
    assert.equal(Model.herdrPalette('[theme]\nname = "latte"\n', "").theme, "catppuccin-latte")
    assert.equal(Model.herdrPalette('[theme]\nname = "nonsense"\n', "").theme, "catppuccin")
  })

  test("custom colours override the theme, in every spelling herdr accepts", () => {
    const palette = Model.herdrPalette(
      '[theme]\nname = "nord"\n[theme.custom]\nteal = "#123456"\ngreen = "rgb(1, 2, 3)"\nred = "#abc"\nyellow = "lightyellow"\n',
      tokyo)
    assert.equal(palette.done, "#123456")
    assert.equal(palette.idle, "#010203")
    assert.equal(palette.blocked, "#aabbcc")
    assert.equal(palette.working, "#ff9e64")
  })

  test("auto_switch follows Omarchy's light or dark theme, with its own overrides", () => {
    const config = '[theme]\nname = "gruvbox"\nauto_switch = true\n[theme.custom.light]\nteal = "#000001"\n'
    assert.equal(Model.herdrPalette(config, tokyo).theme, "gruvbox")
    const light = Model.herdrPalette(config, white)
    assert.equal(light.theme, "gruvbox-light")
    assert.equal(light.done, "#000001")
  })

  test("symbols are used when herdr is set to them", () => {
    assert.equal(Model.herdrPalette('[ui]\nstatus_indicators = "symbols"\n', "").indicators, "symbols")
    assert.equal(Model.stateMark("done", "symbols"), "✓")
    assert.equal(Model.stateMark("done", "dots"), "●")
    assert.equal(Model.stateMark("idle", "dots"), "○")
  })

  test("a theme that writes color0..color15 is read that way", () => {
    const ansi = Model.ansiPalette('color3 = "#111111"\nyellow = "#222222"\n')
    assert.equal(ansi[3], "#111111")
  })

  test("a colour that would vanish on the background is moved until it shows", () => {
    const pale = "#f9e2af"
    const moved = Model.readable(pale, "#ffffff")
    assert.ok(Model.contrast(moved, "#ffffff") >= 3)
    assert.equal(Model.readable("#e0af68", "#1a1b26"), "#e0af68")
  })

  test("the badge text reads on whatever colour the badge is", () => {
    for (const fill of ["#f9e2af", "#1e66f5", "#9ece6a", "#d20f39", "#ffffff", "#000000"]) {
      const text = Model.textOn(fill, "#1a1b26", "#a9b1d6")
      assert.ok(Model.contrast(fill, text) >= 3, fill + " on " + text)
    }
  })

  test("Qt's #aarrggbb colours are understood", () => {
    assert.equal(Model.hexOf("#801a1b26"), "#1a1b26")
  })

  test("every Omarchy theme with every herdr theme gives readable dots", () => {
    const fs = require("fs")
    const dir = "/usr/share/omarchy/themes"
    if (!fs.existsSync(dir)) return
    for (const omarchy of fs.readdirSync(dir)) {
      const file = dir + "/" + omarchy + "/colors.toml"
      if (!fs.existsSync(file)) continue
      const colors = fs.readFileSync(file, "utf8")
      const bg = Model.parseTomlFlat(colors).background
      for (const herdr of Object.keys(Model.HERDR_THEMES)) {
        const palette = Model.herdrPalette('[theme]\nname = "' + herdr + '"\n', colors)
        for (const state of ["working", "blocked", "done", "idle"]) {
          const shown = Model.readable(palette[state], bg)
          assert.ok(Model.contrast(shown, bg) >= 3, `${herdr} ${state} on ${omarchy}`)
        }
      }
    }
  })
})
