#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SHELL_DIR=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'skipped (quickshell is not installed)\n'
  exit 0
fi
if [[ ! -d $SHELL_DIR/Ui ]]; then
  printf 'skipped (the Omarchy shell components are not at %s)\n' "$SHELL_DIR"
  exit 0
fi

WORK=$(mktemp -d -p "${TMPDIR:-/tmp}" herdr-qml-smoke.XXXXXX)
trap 'rm -rf -- "$WORK"' EXIT

cp -r -- "$SHELL_DIR"/* "$WORK/" 2>/dev/null
rm -f -- "$WORK/shell.qml"
mkdir -p -- "$WORK/probe"
cp -r -- "$ROOT/BarWidget.qml" "$ROOT/Panel.qml" "$ROOT/Model.js" "$ROOT/bin" "$WORK/probe/"

cat >"$WORK/probe.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "probe" as Herdr
import "probe/Model.js" as Model

QtObject {
  id: probeRoot

  property var widget: Herdr.BarWidget {
    moduleName: "io.github.majkelll.herdr"
    bar: null
    settings: ({})
  }

  property int step: 0
  property string machineId: ""

  function say(text) { console.warn("probe: " + text) }
  function rowIndex(panel, kind, machine) {
    for (var i = 0; i < panel.rows.length; i++)
      if (panel.rows[i].kind === kind && (machine === "" || panel.rows[i].machine === machine)) return i
    return -1
  }

  property var stepper: Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: {
      var w = probeRoot.widget
      var p = w.panelItem
      probeRoot.step++
      switch (probeRoot.step) {
      case 1:
        var rows = p.rows
        probeRoot.say("machines=" + w.state.machines.length + " rows=" + rows.length)
        probeRoot.say("summary=" + Model.summary(w.state))
        probeRoot.say("badge=" + w.badgeState + "/" + w.badgeCount)
        probeRoot.say("tooltip=" + w.tooltip())
        probeRoot.say("rejects a bad host=" + (w.addMachine({ host: "bad;id" }) !== ""))
        probeRoot.say("rejects an empty host=" + (w.addMachine({ host: "" }) !== ""))
        var session = probeRoot.rowIndex(p, "session", "")
        if (session >= 0) { p.takeCursor(session); p.activateCursor() }
        break
      case 2:
        probeRoot.say("actionError=" + JSON.stringify(w.actionError))
        p.startAdd()
        p.draftHost = "herdr-test.invalid"
        p.draftLabel = "Test box"
        p.draftPort = "2222"
        p.submitForm()
        probeRoot.say("add formError=" + JSON.stringify(p.formError) + " formOpen=" + p.formOpen)
        probeRoot.machineId = w.machines.length > 0 ? w.machines[0].id : ""
        probeRoot.say("added id=" + probeRoot.machineId)
        break
      case 3:
        p.startAdd()
        p.draftHost = "herdr-test.invalid"
        p.draftPort = "2222"
        p.submitForm()
        probeRoot.say("duplicate refused=" + (p.formError !== ""))
        p.draftHost = "other.invalid"
        probeRoot.say("editing clears the error=" + (p.formError === ""))
        p.draftIdentity = "/home/u/my key"
        p.submitForm()
        probeRoot.say("spaced identity refused=" + (p.formError !== ""))
        p.draftIdentity = ""
        p.draftPort = "abc"
        p.testForm()
        probeRoot.say("test of a bad port answered=" + (p.probeLine() !== "" && !w.probing))
        p.cancelForm()
        probeRoot.say("cancel closes the form=" + !p.formOpen)
        break
      case 4:
        p.startEdit(probeRoot.machineId)
        probeRoot.say("edit prefills=" + (p.draftHost === "herdr-test.invalid" && p.draftPort === "2222"))
        p.draftLabel = "Renamed box"
        p.submitForm()
        probeRoot.say("edit saved=" + (w.machines.length === 1 && w.machines[0].label === "Renamed box"
          && w.machines[0].id === probeRoot.machineId))
        w.refresh()
        break
      case 6:
        var machineRow = probeRoot.rowIndex(p, "machine", probeRoot.machineId)
        probeRoot.say("machine row drawn=" + (machineRow >= 0))
        if (machineRow >= 0) {
          probeRoot.say("unreachable machine says why=" + (p.rows[machineRow].line !== ""))
          probeRoot.say("no install button for a name that does not resolve="
            + (p.rows[machineRow].errorCode !== "herdr-missing"))
          p.takeCursor(machineRow)
          p.deleteCursor()
          probeRoot.say("first delete only arms=" + (p.removeArmed === probeRoot.machineId && w.machines.length === 1))
          p.deleteCursor()
          probeRoot.say("second delete removes=" + (w.machines.length === 0))
        }
        break
      case 7:
        var before = p.rows.length
        p.toggleCollapsed("local")
        probeRoot.say("folding hides the sessions=" + (p.rows.length < before || before <= 1))
        probeRoot.say("cursor stays on a row=" + (p.selectedIndex >= 0 && p.selectedIndex < p.rows.length))
        p.toggleCollapsed("local")
        probeRoot.say("unfolding brings them back=" + (p.rows.length === before))
        p.moveCursor(1); p.moveCursor(1); p.moveCursor(-1)
        probeRoot.say("arrows keep the cursor in the list=" + (p.selectedIndex >= 0 && p.selectedIndex < p.rows.length))
        break
      case 8:
        probeRoot.say("built")
        Qt.quit()
        break
      }
    }
  }
}
QML

printf '{"version":1,"machines":[]}\n' >"$WORK/machines.json"
out=$(HERDR_WIDGET_DRY_RUN=1 HERDR_WIDGET_CONFIG="$WORK/machines.json" HERDR_WIDGET_CACHE="$WORK/cache" \
  timeout 90 quickshell -p "$WORK/probe.qml" 2>&1)
status=$?
out=$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g')

pass=0
fail=0
check() {
  if [[ $2 == yes ]]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf 'FAIL %s\n' "$1"
  fi
}

check "quickshell loaded the config" \
  "$([[ $out == *"Configuration Loaded"* ]] && echo yes || echo no)"
check "the widget and its panel were built" \
  "$([[ $out == *"probe: built"* ]] && echo yes || echo no)"
check "no QML error while building or running it" \
  "$(grep -E 'WARN|ERROR|TypeError|ReferenceError|is not a function|Binding loop|non-existent' <<<"$out" \
      | grep -vE 'qml: probe: |qt\.qpa\.|Failed to register with host portal' | grep -q . && echo no || echo yes)"
check "a machine is added through the form" \
  "$(grep -qF 'probe: add formError="" formOpen=false' <<<"$out" && echo yes || echo no)"
check "the same machine twice is refused" \
  "$(grep -qF 'probe: duplicate refused=true' <<<"$out" && echo yes || echo no)"
check "editing a field clears the sentence under the form" \
  "$(grep -qF 'probe: editing clears the error=true' <<<"$out" && echo yes || echo no)"
check "an identity file with a space is refused" \
  "$(grep -qF 'probe: spaced identity refused=true' <<<"$out" && echo yes || echo no)"
check "Test with a bad port answers without asking ssh" \
  "$(grep -qF 'probe: test of a bad port answered=true' <<<"$out" && echo yes || echo no)"
check "cancel closes the form" \
  "$(grep -qF 'probe: cancel closes the form=true' <<<"$out" && echo yes || echo no)"
check "edit opens with the machine's own values" \
  "$(grep -qF 'probe: edit prefills=true' <<<"$out" && echo yes || echo no)"
check "an edit is saved under the same id" \
  "$(grep -qF 'probe: edit saved=true' <<<"$out" && echo yes || echo no)"
check "the new machine is drawn after a refresh" \
  "$(grep -qF 'probe: machine row drawn=true' <<<"$out" && echo yes || echo no)"
check "a machine that cannot be reached says why" \
  "$(grep -qF 'probe: unreachable machine says why=true' <<<"$out" && echo yes || echo no)"
check "the install button is only for a missing herdr" \
  "$(grep -qF 'probe: no install button for a name that does not resolve=true' <<<"$out" && echo yes || echo no)"
check "the first delete only arms the button" \
  "$(grep -qF 'probe: first delete only arms=true' <<<"$out" && echo yes || echo no)"
check "the second delete removes the machine" \
  "$(grep -qF 'probe: second delete removes=true' <<<"$out" && echo yes || echo no)"
check "folding a machine hides its sessions" \
  "$(grep -qF 'probe: folding hides the sessions=true' <<<"$out" && echo yes || echo no)"
check "the cursor stays on a row when the list shrinks" \
  "$(grep -qF 'probe: cursor stays on a row=true' <<<"$out" && echo yes || echo no)"
check "unfolding brings them back" \
  "$(grep -qF 'probe: unfolding brings them back=true' <<<"$out" && echo yes || echo no)"
check "the arrows keep the cursor inside the list" \
  "$(grep -qF 'probe: arrows keep the cursor in the list=true' <<<"$out" && echo yes || echo no)"
check "machines.json holds no test machine afterwards" \
  "$(jq -e '.machines == []' "$WORK/machines.json" >/dev/null 2>&1 && echo yes || echo no)"
check "the panel produced rows from the herd" \
  "$(grep -qE 'rows=[1-9]' <<<"$out" && echo yes || echo no)"
check "a click on a session reported no error" \
  "$(grep -q 'probe: actionError=""' <<<"$out" && echo yes || echo no)"
check "a machine with an impossible host is refused before it is written" \
  "$(grep -q 'probe: rejects a bad host=true' <<<"$out" && echo yes || echo no)"
check "so is one with no host at all" \
  "$(grep -q 'probe: rejects an empty host=true' <<<"$out" && echo yes || echo no)"
check "quickshell exited cleanly" \
  "$([[ $status -eq 0 ]] && echo yes || echo no)"

if (( fail > 0 )) || [[ -n ${HERDR_SMOKE_VERBOSE:-} ]]; then
  printf '\n--- quickshell output ---\n%s\n' "$out" | head -60
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
