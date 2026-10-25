#!/usr/bin/env bash
set -euo pipefail

# Source app comes from `mise run build`, which exports a Release-signed .app
# under build/export/MactermOff.app.
SRC="./build/export/MactermOff.app"
if [[ ! -d "$SRC" ]]; then
  echo "ERROR: $SRC is not there. Run 'mise run build' first." >&2
  exit 1
fi

rm -rf /Applications/MactermOff.app
ditto "$SRC" /Applications/MactermOff.app

codesign --verify --deep --strict --verbose=2 /Applications/MactermOff.app
