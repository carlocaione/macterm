#!/usr/bin/env bash
# List each line of code that names Macterm's identity (bundle ID, app name,
# config folder, zmx folder), and compare the list with the lines that we
# reviewed (fork/identity-allowlist.txt). Run it at the root of a checkout of
# off/base or off/main.
#
#   fork/identity.sh           print the lines, as <file><TAB><text>
#   fork/identity.sh --check   fail when a line is not in the allowlist
#
# A line counts once for each file, with its indentation removed, so that a
# line that only moves does not fail the check. Comments do not count.
set -euo pipefail

allowlist="fork/identity-allowlist.txt"

lines() {
  git grep -nE \
    -e 'com\.thdxg\.macterm' \
    -e '\.config/macterm([^a-z]|$)' \
    -e 'Macterm\.app' \
    -e '"Macterm( Debug)?"' \
    -e '/zmx(-\\\(uid\))?"' \
    -- Macterm CLI scripts project.yml mise.toml \
    ':!scripts/record-demos' ':!*.md' ':!*.xcstrings' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|#|\*|<!--)' \
    | sed -E 's/^([^:]+):[0-9]+:[[:space:]]*/\1\t/' \
    | LC_ALL=C sort -u
}

case "${1:-}" in
  "")
    lines
    ;;
  --check)
    if [[ ! -f "$allowlist" ]]; then
      echo "identity: $allowlist is not in this checkout" >&2
      exit 2
    fi
    new="$(LC_ALL=C comm -13 <(grep -v '^#' "$allowlist" | grep -v '^$' | LC_ALL=C sort -u) <(lines))"
    if [[ -n "$new" ]]; then
      echo "identity: these lines name Macterm's identity, and $allowlist does not have them:"
      printf '%s\n' "$new" | sed 's/^/  /'
      echo "Change each one for MactermOff (see fork/AGENTS.md, Identity), or add it to $allowlist."
      exit 1
    fi
    echo "identity: no new lines"
    ;;
  *)
    echo "usage: fork/identity.sh [--check]" >&2
    exit 2
    ;;
esac
