#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CTL="$ROOT/bin/herdr-ctl"
STUBS="$ROOT/tests/stubs"

WORK=$(mktemp -d -p "${TMPDIR:-/tmp}" herdr-ctl-test.XXXXXX)
trap 'rm -rf -- "$WORK"' EXIT

export PATH="$STUBS:$PATH"
export HERDR_WIDGET_CACHE="$WORK/cache"
export HERDR_WIDGET_HERDR=herdr
export STUB_LOG="$WORK/calls.log"

pass=0
fail=0

check() {
  local name=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     expected: %q\n     actual:   %q\n' "$name" "$expected" "$actual"
  fi
}

check_match() {
  local name=$1 pattern=$2 actual=$3
  if [[ $actual =~ $pattern ]]; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n     expected to match: %q\n     actual:            %q\n' "$name" "$pattern" "$actual"
  fi
}

check_status() {
  local name=$1 expected=$2
  shift 2
  "$@" >/dev/null 2>&1
  check "$name" "$expected" "$?"
}

config() {
  printf '%s' "$1" >"$WORK/machines.json"
  export HERDR_WIDGET_CONFIG="$WORK/machines.json"
}

ONE_MACHINE='{"version":1,"machines":[{"id":"lab","label":"lab","host":"192.0.2.10","port":2222,"user":"dev","identityFile":"","herdrPath":"","connectTimeoutSec":4,"enabled":true}]}'

snapshot() {
  "$CTL" snapshot 2>/dev/null
}

check "an unknown subcommand names itself" \
  "unknown-command" "$("$CTL" bogus 2>&1 >/dev/null)"
check_status "an unknown subcommand exits non-zero" 1 "$CTL" bogus
check "no subcommand at all is an unknown subcommand" \
  "unknown-command" "$("$CTL" 2>&1 >/dev/null)"

config '{"version":1,"machines":[]}'
out=$(snapshot)

check "the local machine is always there" \
  "local" "$(jq -r '.machines[0].id' <<<"$out")"
check "the local machine is not a remote one" \
  "false" "$(jq -r '.machines[0].remote' <<<"$out")"
check "its version comes off the binary" \
  "9.9.9" "$(jq -r '.machines[0].version' <<<"$out")"
check "a running session and a stopped one both show" \
  "default old" "$(jq -r '[.machines[0].sessions[].name] | join(" ")' <<<"$out")"
check "the stopped session is marked stopped" \
  "false" "$(jq -r '.machines[0].sessions[] | select(.name == "old") | .running' <<<"$out")"
check "agents come back with their panes and titles" \
  "waiting here quiet one" \
  "$(jq -r '[.machines[0].sessions[0].agents[].title] | join(" ")' <<<"$out")"
check "an agent's workspace label is joined on from the snapshot" \
  "manaw" "$(jq -r '.machines[0].sessions[0].agents[0].workspace' <<<"$out")"
check "the session's projects are its workspace labels" \
  "ChessLab manaw" "$(jq -r '.machines[0].sessions[0].projects | join(" ")' <<<"$out")"
check "totals count what is waiting" \
  "1" "$(jq -r '.totals.blocked' <<<"$out")"
check "the answer says it is one" \
  "true" "$(jq -r '.ok' <<<"$out")"

check "the window showing a local session is found through its terminal" \
  "0xaaa" "$(jq -r '.machines[0].sessions[] | select(.name == "default") | .window' <<<"$out")"
check "and so is the workspace that window is on" \
  "4" "$(jq -r '.machines[0].sessions[] | select(.name == "default") | .workspace' <<<"$out")"
check "a stopped session has no window" \
  "" "$(jq -r '.machines[0].sessions[] | select(.name == "old") | .window' <<<"$out")"

out_down=$(STUB_HERDR_MODE=down snapshot)
check "a local herdr with no server says so rather than vanishing" \
  "no-server" "$(jq -r '.machines[0].error' <<<"$out_down")"
check "and is not drawn as reachable" \
  "false" "$(jq -r '.machines[0].reachable' <<<"$out_down")"

config "$ONE_MACHINE"
out=$(snapshot)

check "a configured machine is listed after the local one" \
  "local lab" "$(jq -r '[.machines[].id] | join(" ")' <<<"$out")"
check "it is a remote one" \
  "true" "$(jq -r '.machines[1].remote' <<<"$out")"
check "its target is what ssh is handed" \
  "dev@192.0.2.10" "$(jq -r '.machines[1].target' <<<"$out")"
check "its version comes off its own binary" \
  "9.9.9" "$(jq -r '.machines[1].version' <<<"$out")"
check "its sessions and agents come back" \
  "far away work" "$(jq -r '.machines[1].sessions[0].agents[0].title' <<<"$out")"
check "a finished agent over there is counted here" \
  "1" "$(jq -r '.totals.done' <<<"$out")"
check "a window already attached to it is found by the ssh target on its command line" \
  "0xbbb" "$(jq -r '.machines[1].sessions[0].window' <<<"$out")"
check "somebody else's ssh to an unknown machine is not one of these rows" \
  "2" "$(jq -r '.machines | length' <<<"$out")"
check "the port is passed to ssh exactly as configured" \
  "yes" "$(grep -q -- '-p 2222' "$STUB_LOG" && echo yes || echo no)"

check "nothing in a refresh can stop a server or delete a session" \
  "" "$(grep -E 'session (stop|delete)|server stop|kill' "$STUB_LOG" || true)"

for mode_case in "auth auth-failed" "hostkey host-key" "refused unreachable" "timeout timeout"; do
  set -- $mode_case
  out_err=$(STUB_SSH_MODE="$1" snapshot)
  check "ssh failing with $1 reads as $2" \
    "$2" "$(jq -r '.machines[1].error' <<<"$out_err")"
  check "a machine that failed with $1 is not reachable" \
    "false" "$(jq -r '.machines[1].reachable' <<<"$out_err")"
done

out_err=$(STUB_SSH_MODE=noherdr snapshot)
check "a machine without herdr says exactly that" \
  "herdr-missing" "$(jq -r '.machines[1].error' <<<"$out_err")"

out_err=$(STUB_SSH_MODE=badjson snapshot)
check "a machine answering with something that is not herdr JSON is refused" \
  "bad-json" "$(jq -r '.machines[1].error' <<<"$out_err")"

check "one machine failing leaves the local one intact" \
  "true" "$(jq -r '.machines[0].reachable' <<<"$out_err")"

config 'this is not json'
out_bad=$(snapshot)
check "an unreadable config is said out loud" \
  "config-unreadable" "$(jq -r '.error' <<<"$out_bad")"
check "and the local machine is still drawn" \
  "local" "$(jq -r '.machines[0].id' <<<"$out_bad")"

config '{"version":1,"machines":[{"id":"bad id","host":"h"},{"id":"ok","host":"h;id"},{"id":"local","host":"h"},{"id":"fine","host":"h2","enabled":true}]}'
out_rows=$(snapshot)
check "rows that are not a machine at all are dropped" \
  "local ok fine" "$(jq -r '[.machines[].id] | join(" ")' <<<"$out_rows")"
check "a machine with a host ssh cannot be handed is drawn with the reason" \
  "bad-host false" "$(jq -r '.machines[1] | "\(.error) \(.reachable)"' <<<"$out_rows")"

config '{"version":1,"machines":[{"id":"off","host":"h2","enabled":false}]}'
: >"$STUB_LOG"
out_off=$(snapshot)
check "a disabled machine is listed" \
  "off" "$(jq -r '.machines[1].id' <<<"$out_off")"
check "a disabled machine is not dialled" \
  "" "$(grep '^ssh ' "$STUB_LOG" || true)"

config "$ONE_MACHINE"
export HERDR_WIDGET_DRY_RUN=1

out_open=$("$CTL" open local default 2>&1)
check_match "clicking a local session raises the window it is already in" \
  'dispatch: workspace=4 window=0xaaa' "$out_open"
check_match "and says it did something" 'ok' "$out_open"

out_open=$("$CTL" open local default w2:p1 2>&1)
check_match "clicking a local agent focuses its pane first" \
  'focus: herdr agent focus w2:p1' "$out_open"
check_match "and then raises the window" 'dispatch: workspace=4 window=0xaaa' "$out_open"

out_open=$("$CTL" open local old 2>&1)
check_match "a session with no window gets one opened on it" \
  'launch: app-id=org.omarchy.herdr cmd=herdr --session old' "$out_open"

out_open=$("$CTL" open lab default w1:p1 2>&1)
check_match "clicking a remote agent focuses its pane on that machine" \
  'focus: ssh dev@192.0.2.10 -- /opt/herdr/bin/herdr agent focus w1:p1' "$out_open"
check_match "and raises the window already attached to it rather than opening another" \
  'dispatch: workspace=7 window=0xbbb' "$out_open"

config '{"version":1,"machines":[{"id":"nowindow","host":"h9","user":"dev","connectTimeoutSec":4}]}'
out_open=$("$CTL" open nowindow default 2>&1)
check_match "a remote session with no window opens a terminal onto that machine" \
  'launch: app-id=org.omarchy.herdr cmd=ssh -t' "$out_open"
check_match "and runs that machine's own herdr, at the path it was found at" \
  'dev@h9 /opt/herdr/bin/herdr' "$out_open"

config "$ONE_MACHINE"
check "opening a machine that is not in the list is refused" \
  "bad-machine" "$("$CTL" open nosuch default 2>&1 >/dev/null)"
check "a session name herdr would not produce is refused" \
  "bad-session" "$("$CTL" open local 'a b' 2>&1 >/dev/null)"
check "a pane id herdr would not produce is refused" \
  "bad-pane" "$("$CTL" open local default 'w1;id' 2>&1 >/dev/null)"
check_status "a refused click exits non-zero" 1 "$CTL" open local default 'w1;id'

: >"$STUB_LOG"
"$CTL" open local default w2:p1 >/dev/null 2>&1
check "a click never stops anything either" \
  "" "$(grep -E 'session (stop|delete)|server stop|kill' "$STUB_LOG" || true)"

unset HERDR_WIDGET_DRY_RUN
out_probe=$("$CTL" probe 192.0.2.10 2222 dev "" 4 2>/dev/null)
check "a probe says it got there" \
  "true" "$(jq -r '.reachable' <<<"$out_probe")"
check "a probe brings back where herdr is" \
  "/opt/herdr/bin/herdr" "$(jq -r '.herdrPath' <<<"$out_probe")"
check "a probe brings back the version" \
  "9.9.9" "$(jq -r '.version' <<<"$out_probe")"
check "a probe says whether a server is already running there" \
  "true" "$(jq -r '.server' <<<"$out_probe")"

out_probe=$(STUB_SSH_MODE=noherdr "$CTL" probe h "" "" "" 4 2>/dev/null)
check "a probe that finds no herdr says so while still being reachable" \
  "true herdr-missing" "$(jq -r '"\(.reachable) \(.error)"' <<<"$out_probe")"

out_probe=$(STUB_SSH_MODE=auth "$CTL" probe h "" "" "" 4 2>/dev/null)
check "a probe refused by ssh points at the fix" \
  "false auth-failed" "$(jq -r '"\(.reachable) \(.error)"' <<<"$out_probe")"

check "a probe of a host that is not a host is refused" \
  "bad-host" "$("$CTL" probe 'h;id' "" "" "" 4 2>&1 >/dev/null)"
check "a probe with a port that is not a port is refused" \
  "bad-port" "$("$CTL" probe h 99999 "" "" 4 2>&1 >/dev/null)"

export HERDR_WIDGET_DRY_RUN=1
out_install=$("$CTL" install h "" "" "" 4 2>&1)
check_match "installing runs herdr's own installer in a window you can watch" \
  'launch: app-id=org.omarchy.herdr.install' "$out_install"
check_match "and it is the installer from herdr.dev" \
  'https://herdr.dev/install.sh' "$out_install"
check "installing a host that is not a host is refused" \
  "bad-host" "$("$CTL" install 'h;id' "" "" "" 4 2>&1 >/dev/null)"

config '[{"id":"a","host":"h"}]'
check "a config that is a list rather than an object is unreadable" \
  "config-unreadable" "$(snapshot | jq -r '.error')"

config '{"machines":[{"id":"ERRORS-lab","host":"h"}]}'
check "a machine whose id starts with ERROR is a machine, not an unreadable file" \
  " ERRORS-lab" "$(STUB_SSH_MODE=refused snapshot | jq -r '"\(.error) \(.machines[1].id)"')"

config '{"machines":{"id":"a"}}'
check "a machines key that is not a list is unreadable" \
  "config-unreadable" "$(snapshot | jq -r '.error')"

config '{"machines":[{"id":7,"host":"h1"},{"id":"two","host":"h2","port":"22"},{"id":"two","host":"h3"}]}'
out_mixed=$(STUB_SSH_MODE=refused snapshot)
check "a number where a string goes is read as the string, and the other rows stay" \
  "local 7 two" "$(jq -r '[.machines[].id] | join(" ")' <<<"$out_mixed")"
check "an id written twice keeps its first row" \
  "h2" "$(jq -r '.machines[2].target' <<<"$out_mixed")"

config '{"machines":[{"id":"oct","host":"h","port":"08","connectTimeoutSec":1000}]}'
: >"$STUB_LOG"
snapshot >/dev/null
check "a port written with a leading zero is read in base ten" \
  "yes" "$(grep -q -- '-p 8 ' "$STUB_LOG" && echo yes || echo no)"
check "a timeout out of range is clamped rather than the row dropped" \
  "yes" "$(grep -q -- 'ConnectTimeout=60' "$STUB_LOG" && echo yes || echo no)"

config '{"machines":[{"id":"spaced","host":"h","identityFile":"/home/u/my key"}]}'
: >"$STUB_LOG"
out_id=$(snapshot)
check "an identity file ssh would split is drawn with the reason" \
  "bad-identity" "$(jq -r '.machines[1].error' <<<"$out_id")"
check "and that machine is never dialled" \
  "" "$(grep '^ssh ' "$STUB_LOG" || true)"
check "opening it is refused with the same reason" \
  "bad-identity" "$("$CTL" open spaced default 2>&1 >/dev/null)"

config '{"version":1,"machines":[]}'
out_weird=$(STUB_HERDR_MODE=weird snapshot)
check "a snapshot of the wrong shape keeps its session listed" \
  "default old" "$(jq -r '[.machines[0].sessions[].name] | join(" ")' <<<"$out_weird")"
check "and costs it only its agents" \
  "0" "$(jq -r '.machines[0].sessions[0].agents | length' <<<"$out_weird")"

out_pretty=$(STUB_HERDR_MODE=pretty snapshot)
check "a pretty-printed local herdr reads the same as a compact one" \
  "waiting here quiet one" "$(jq -r '[.machines[0].sessions[0].agents[].title] | join(" ")' <<<"$out_pretty")"

config "$ONE_MACHINE"
out_exec=$(STUB_SSH_MODE=exec snapshot)
check "the remote scripts themselves find herdr and read every session" \
  "waiting here quiet one" "$(jq -r '[.machines[1].sessions[0].agents[].title] | join(" ")' <<<"$out_exec")"
check "and report its version" \
  "9.9.9" "$(jq -r '.machines[1].version' <<<"$out_exec")"
out_exec=$(STUB_SSH_MODE=exec STUB_HERDR_MODE=pretty snapshot)
check "a remote herdr that pretty-prints is read all the same" \
  "waiting here quiet one" "$(jq -r '[.machines[1].sessions[0].agents[].title] | join(" ")' <<<"$out_exec")"

config '{"version":1,"machines":[{"id":"moved","host":"h","herdrPath":"/gone/herdr"}]}'
out_moved=$(STUB_SSH_MODE=exec snapshot)
check "a saved herdr path that no longer answers is looked for again" \
  "true 9.9.9" "$(jq -r '.machines[1] | "\(.reachable) \(.version)"' <<<"$out_moved")"

config "$ONE_MACHINE"
check "a host without bash says so" \
  "no-bash" "$(STUB_SSH_MODE=nobash snapshot | jq -r '.machines[1].error')"

config '{"version":1,"machines":[{"id":"slow","host":"h","connectTimeoutSec":2}]}'
started=$SECONDS
out_hang=$(STUB_SSH_MODE=hang snapshot)
check "a host that never answers reads as timeout" \
  "timeout" "$(jq -r '.machines[1].error' <<<"$out_hang")"
check "and costs at most three of its connect timeouts" \
  "yes" "$( (( SECONDS - started <= 9 )) && echo yes || echo no)"

config '{"version":1,"machines":[]}'
check "a program with herdr only in its arguments is not a herdr window" \
  "" "$(STUB_PS_MODE=noisy snapshot | jq -r '.machines[0].sessions[] | select(.name == "default") | .window')"

: >"$STUB_LOG"
HERDR_WIDGET_DRY_RUN= STUB_HYPR_MODE=named "$CTL" open local default >/dev/null 2>&1
check "a workspace with a space and a quote in its name is still switched to" \
  "yes" "$(grep -qF "workspace = 'it\\'s work'" "$STUB_LOG" && echo yes || echo no)"

check "a probe with an identity that is not a path is refused" \
  "bad-identity" "$("$CTL" probe h "" "" $'x\n-oProxyCommand=id' 4 2>&1 >/dev/null)"
check "so is an install" \
  "bad-identity" "$("$CTL" install h "" "" $'x\n-oProxyCommand=id' 4 2>&1 >/dev/null)"
check "a herdr path that starts like an option is refused" \
  "bad-path" "$("$CTL" probe h "" "" "" 4 --version 2>&1 >/dev/null)"

out_probe=$(STUB_SSH_MODE=exec "$CTL" probe h "" "" "" 4 /nope/herdr 2>/dev/null)
check "a probe of a path that is not there says herdr is missing, not some other herdr" \
  "true herdr-missing " "$(jq -r '"\(.reachable) \(.error) \(.herdrPath)"' <<<"$out_probe")"

mkdir -p "$WORK/nojq"
for tool in /usr/bin/*; do
  [[ ${tool##*/} == jq ]] || ln -s "$tool" "$WORK/nojq/" 2>/dev/null
done
check "a snapshot without jq still answers in JSON the panel can draw" \
  '{"ok":false,"error":"missing-jq","machines":[]}' "$(PATH="$WORK/nojq" "$CTL" snapshot 2>/dev/null)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
