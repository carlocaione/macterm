#!/usr/bin/env bash
# The checks that a MactermOff branch must pass. Run it at the root of a
# checkout. It prints one line for each step and writes the output of each
# step to <logs>/<step>.log. It stops at the first step that fails (exit 1).
#
# Usage: fork/gate.sh [--steps <a,b,...>] [--e2e <pytest selector>]... [--logs <dir>]
#   Steps: setup identity format lint unit strings e2e
#   Default: setup,format,lint,unit,strings. "identity" is for a checkout
#   with the fork identity (off/base, off/main). "e2e" runs the --e2e tests.
#
# The e2e step starts hermetic app windows. They take the keyboard focus.
set -euo pipefail

FORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
steps="setup,format,lint,unit,strings"
logs="build/fork-gate"
e2e=()

while (($#)); do
  case "$1" in
    --steps) steps="$2"; shift 2 ;;
    --e2e) e2e+=("$2"); shift 2 ;;
    --logs) logs="$2"; shift 2 ;;
    -h | --help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "gate: unknown argument: $1" >&2; exit 2 ;;
  esac
done

DERIVED_DATA="$PWD/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/Macterm Debug.app"
VENV="$PWD/build/e2e-venv"

# Each step is one command or an explicit && chain: `set -e` does not apply
# inside a function that runs as the condition of an `if`.
step_setup() { ./scripts/setup.sh; }
step_identity() { "$FORK_DIR/identity.sh" --check; }
step_format() { mise exec -- ./scripts/format.sh --check; }
step_lint() { mise exec -- ./scripts/lint.sh; }
step_unit() { mise exec -- ./scripts/test.sh; }
step_strings() { mise exec -- ./scripts/strings.sh --check --no-build; }
step_e2e() {
  if ((${#e2e[@]} == 0)); then
    echo "no e2e tests to run"
    return 0
  fi
  mise exec -- xcodegen generate --spec project.yml >/dev/null &&
    xcodebuild -project Macterm.xcodeproj -scheme Macterm -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" ONLY_ACTIVE_ARCH=YES build |
    (mise exec -- xcbeautify --quiet 2>/dev/null || cat) &&
    { [[ -x "$VENV/bin/pytest" ]] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install --quiet pytest==8.4.1; }; } &&
    "$VENV/bin/pytest" -v "${e2e[@]}" --app "$APP"
}

mkdir -p "$logs"
IFS=',' read -r -a list <<<"$steps"
for step in "${list[@]}"; do
  if ! declare -F "step_$step" >/dev/null; then
    echo "gate: unknown step: $step" >&2
    exit 2
  fi
done
for step in "${list[@]}"; do
  start=$SECONDS
  if "step_$step" >"$logs/$step.log" 2>&1; then
    printf 'PASS %-8s %4ss\n' "$step" "$((SECONDS - start))"
  else
    printf 'FAIL %-8s %4ss  %s\n' "$step" "$((SECONDS - start))" "$logs/$step.log"
    exit 1
  fi
done
