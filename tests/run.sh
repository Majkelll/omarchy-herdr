#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
status=0

printf '\n=== Model.js ===\n'
node --test "$ROOT/tests/model.test.js" || status=1

printf '\n=== bin/herdr-ctl ===\n'
"$ROOT/tests/ctl.test.sh" || status=1

printf '\n=== QML smoke test ===\n'
"$ROOT/tests/qml.smoke.sh" || status=1

printf '\n=== shellcheck ===\n'
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$ROOT/bin/herdr-ctl" && printf 'ok   no warnings\n'
else
  printf 'skipped (shellcheck is not installed)\n'
fi

exit "$status"
