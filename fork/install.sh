#!/usr/bin/env bash
# Build MactermOff from this checkout (normally off/main) and install it as
# /Applications/MactermOff.app. It never touches /Applications/Macterm.app.
#
# Usage: fork/install.sh [--identity <code-signing identity>]
#   --identity  A code-signing identity in your keychain (its name or SHA-1).
#               With it, macOS keeps the privacy grants (Full Disk Access,
#               Local Network and others) from one install to the next.
#               Without it, the app is signed ad hoc, and macOS asks again
#               after each install. OFF_CODESIGN_IDENTITY sets the default.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
identity="${OFF_CODESIGN_IDENTITY:-}"
while (($#)); do
  case "$1" in
    --identity) identity="$2"; shift 2 ;;
    -h | --help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "install: unknown argument: $1" >&2; exit 2 ;;
  esac
done

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ $branch == off/main ]] || echo "install: note: this checkout is on $branch, not off/main" >&2
[[ -z $(git status --porcelain --untracked-files=no) ]] || echo "install: note: the checkout has changes that are not committed" >&2
if ps -axo command | grep -qF "/Applications/MactermOff.app/Contents/MacOS/MactermOff"; then
  echo "install: MactermOff runs. Quit it first (its zmx sessions stay)." >&2
  exit 1
fi

# shellcheck source=scripts/_lib.sh
source scripts/_lib.sh
# A label only: Sparkle is off in a fork build (no SPARKLE_ED_PUBLIC_KEY).
VERSION="$(macterm_tip_version)"
unset SPARKLE_ED_PUBLIC_KEY
MACTERM_CODESIGN_IDENTITY="$identity" VERSION="$VERSION" mise exec -- ./scripts/build.sh
./scripts/install.sh
echo "Installed /Applications/MactermOff.app $VERSION ($(git rev-parse --short HEAD))"
