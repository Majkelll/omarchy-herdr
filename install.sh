#!/usr/bin/env bash
set -euo pipefail

for tool in jq rsync; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'install.sh needs %s\n' "$tool" >&2; exit 1; }
done

SRC=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ID=$(jq -r '.id // empty' "$SRC/manifest.json")
[[ $ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { printf 'manifest.json has no usable id\n' >&2; exit 1; }

DEST="$HOME/.config/omarchy/plugins"
if [[ ${1:-} == --to ]]; then
  DEST=${2:?--to needs a directory}
fi
TARGET="$DEST/$ID"

if [[ -L $TARGET ]]; then
  rm -- "$TARGET"
fi

mkdir -p -- "$TARGET"
rsync -a --delete --delete-excluded \
  --exclude '.git' --exclude 'node_modules' --exclude '*.swp' --exclude 'tests' \
  -- "$SRC/" "$TARGET/"

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  if ! omarchy-plugin-validate "$TARGET"; then
    printf 'installed, but omarchy-plugin-validate did not accept it (see above)\n' >&2
    exit 1
  fi
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

printf 'installed %s to %s\n' "$ID" "$TARGET"
printf 'add it to the bar with: omarchy bar add %s --section right\n' "$ID"
