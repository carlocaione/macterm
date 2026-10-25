#!/usr/bin/env bash
# List each line of code that names Macterm's identity (bundle ID, app name,
# config folder, zmx folder), and compare the list with the lines that we
# reviewed (fork/identity-allowlist.txt).
#
#   fork/identity.sh                      print the lines, as <file><TAB><text>
#   fork/identity.sh --check              fail on a line that is not in the allowlist
#                                         (a checkout of off/base or off/main)
#   fork/identity.sh --check-added <ref>  the same, for the lines added since <ref>
#                                         only (a checkout of a feature branch)
#
# A line counts once for each file, with its indentation removed, so that a
# line that only moves does not fail the check. Comments do not count.
set -euo pipefail

PATTERNS=(-e 'com\.thdxg\.macterm' -e '\.config/macterm([^a-z]|$)' -e 'Macterm\.app'
  -e '"Macterm( Debug)?"' -e '/zmx(-\\\(uid\))?"')
PATHS=(Macterm CLI scripts project.yml mise.toml ':!scripts/record-demos' ':!*.md' ':!*.xcstrings')

# <file><TAB><text> in, the same out without indentation and without comments.
normalize() {
  awk -F'\t' '{
    text = substr($0, length($1) + 2)
    sub(/^[[:space:]]+/, "", text)
    if (text ~ /^(\/\/|#|\*|<!--)/) next
    print $1 "\t" text
  }'
}

lines() {
  { git grep -nE "${PATTERNS[@]}" -- "${PATHS[@]}" || true; } |
    awk '{ i = index($0, ":"); rest = substr($0, i + 1); j = index(rest, ":"); print substr($0, 1, i - 1) "\t" substr(rest, j + 1) }' |
    normalize | LC_ALL=C sort -u
}

added_lines() {
  git diff -U0 --no-color "$1" HEAD -- "${PATHS[@]}" |
    awk '/^\+\+\+ / { file = (substr($0, 1, 6) == "+++ b/") ? substr($0, 7) : ""; next }
         /^\+/ && file != "" { print file "\t" substr($0, 2) }' |
    { grep -E "${PATTERNS[@]}" || true; } | normalize | LC_ALL=C sort -u
}

# check <what> <lines>
check() {
  local allowlist="fork/identity-allowlist.txt" new
  # A feature branch has no fork/ folder of its own: use the list beside this script.
  [[ -f $allowlist ]] || allowlist="$(dirname "${BASH_SOURCE[0]}")/identity-allowlist.txt"
  new="$(LC_ALL=C comm -13 <(grep -v '^#' "$allowlist" | grep -v '^$' | LC_ALL=C sort -u) <(printf '%s\n' "$2" | grep -v '^$' || true))"
  if [[ -n $new ]]; then
    echo "identity: $1 name Macterm's identity, and the allowlist does not have them:"
    printf '%s\n' "$new" | sed 's/^/  /'
    echo "See fork/AGENTS.md (Identity) and the fix prompt for what to do."
    exit 1
  fi
  echo "identity: no new lines"
}

case "${1:-}" in
  "") lines ;;
  --check) check "these lines" "$(lines)" ;;
  --check-added)
    [[ -n ${2:-} ]] || { echo "usage: fork/identity.sh --check-added <ref>" >&2; exit 2; }
    check "these lines that the branch adds" "$(added_lines "$2")"
    ;;
  *)
    echo "usage: fork/identity.sh [--check | --check-added <ref>]" >&2
    exit 2
    ;;
esac
