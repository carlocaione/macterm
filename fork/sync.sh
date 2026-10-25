#!/usr/bin/env bash
# MactermOff sync: keep the fork's branches on top of upstream Macterm.
# fork/AGENTS.md ("The sync") explains the steps. Run `fork/sync.sh help`.
#
# All code is in functions, and the last line calls main: bash reads a script
# while it runs it, and `promote` can change this file on disk.

usage() {
  cat <<'EOF'
Usage: fork/sync.sh <command> [options]

Commands:
  sync      Rebase off/base and each feature onto upstream main, run the gates,
            and build off/next/main. The result is in off/next/* and in a report.
  promote   Move off/* to the ready off/next/* branches, with a backup tag of each
            old tip, delete retired features, and push off/* to the fork.
  abandon   Delete off/next/*. Your branches stay as they are.
  status    Show the off/* branches and the last report.

Options of sync:
  --agent claude|codex          Resolves conflicts and fixes failures (default: claude).
  --reviewer claude|codex|none  Checks each changed branch for drift (default: codex).
  --gates full|quick|none       full: the gate on each branch, then on off/next/main.
                                quick: the gate on off/next/main only. (default: full)
  --no-e2e                      Do not run the e2e tests of the features.
  --attempts <n>                Fix attempts for each branch (default: 2).
  --review-all                  Review each branch, also when upstream did not touch it.
  --no-fetch                    Do not fetch upstream first.

Options of promote:
  --no-push                     Move the local branches only.
  --force                       Promote also when off/next/base or off/next/main failed.

Environment:
  OFF_UPSTREAM     The upstream ref (default: origin/main).
  OFF_SYNC_DIR     The sync worktree (default: macterm-off-sync.noindex next to the repository).
  OFF_PUSH_URL     Where promote pushes (default: git@github.com:carlocaione/macterm.git).
  OFF_CLAUDE_MODEL, OFF_CODEX_MODEL   The model of each agent (default: its own).
EOF
}

say() { printf '%s\n' "$*" >&2; }
die() {
  say "sync: $*"
  exit 1
}

init() {
  FORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  GIT_COMMON="$(git -C "$FORK_DIR" rev-parse --path-format=absolute --git-common-dir)"
  STATE_DIR="$GIT_COMMON/off-sync"
  SYNC_DIR="${OFF_SYNC_DIR:-$(dirname "$(dirname "$GIT_COMMON")")/macterm-off-sync.noindex}"
  UPSTREAM="${OFF_UPSTREAM:-origin/main}"
  PUSH_URL="${OFF_PUSH_URL:-git@github.com:carlocaione/macterm.git}"
  # mise refuses a mise.toml that it does not trust. This trusts the sync
  # worktree for this process and its children only.
  export MISE_TRUSTED_CONFIG_PATHS="$SYNC_DIR${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}"
  mkdir -p "$STATE_DIR/reports" "$STATE_DIR/runs"
}

# R: git on the repository (the refs are shared). W: git in the sync worktree.
R() { git -C "$FORK_DIR" "$@"; }
W() { git -C "$SYNC_DIR" "$@"; }

short() { R rev-parse --short "$1"; }
src_branch() { if [[ $1 == base ]]; then echo off/base; else echo "off/feat/$1"; fi; }
next_branch() {
  case "$1" in
    base) echo off/next/base ;;
    main) echo off/next/main ;;
    *) echo "off/next/feat/$1" ;;
  esac
}

# One value for each branch and key, in the run folder.
put() { printf '%s\n' "$3" >"$RUN_DIR/$1.$2"; }
get() { cat "$RUN_DIR/$1.$2" 2>/dev/null || true; }
# Append Markdown to the report section of a branch.
sec() { cat >>"$RUN_DIR/$1.section.md"; }

features() {
  R show off/base:fork/manifest | sed -e 's/#.*//' -e 's/[[:space:]]//g' | grep -v '^$' || true
}

# The value of <key> in the front matter of <file> at <ref>.
front_matter() {
  { R show "$1:$2" 2>/dev/null || true; } | awk -v key="$3" '
    NR == 1 { inside = ($0 == "---"); next }
    inside && $0 == "---" { inside = 0 }
    inside && !found && index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/[[:space:]]+#.*$/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      print v
      found = 1
    }'
}

# The upstream commit (since <old base>) with the same patch as <commit>.
upstream_twin() {
  local pid
  pid="$(R show "$1" | R patch-id --stable | cut -d' ' -f1)"
  R log -p "$2..$UPSTREAM_SHA" | R patch-id --stable | awk -v p="$pid" '$1 == p && !found { print $2; found = 1 }'
}

worktree_of() {
  R worktree list --porcelain | awk -v ref="refs/heads/$1" '
    /^worktree / { path = substr($0, 10) }
    $0 == "branch " ref && !found { print path; found = 1 }'
}

# ─── Agents ─────────────────────────────────────────────────────────────────

# run_agent <resolve|fix|review> <claude|codex> <prompt file> <answer file>
run_agent() {
  local role=$1 agent=$2 prompt=$3 answer=$4
  local log="${answer%.md}.log"
  say "   $agent: $role ($(basename "$answer"))"
  case "$agent" in
    claude)
      local allow=(Read Glob Grep "Bash(git status:*)" "Bash(git diff:*)" "Bash(git log:*)"
        "Bash(git show:*)" "Bash(git range-diff:*)" "Bash(git grep:*)" "Bash(git blame:*)" "Bash(ls:*)")
      local deny=("Bash(git commit:*)" "Bash(git add:*)" "Bash(git rebase:*)" "Bash(git merge:*)"
        "Bash(git reset:*)" "Bash(git checkout:*)" "Bash(git switch:*)" "Bash(git restore:*)"
        "Bash(git stash:*)" "Bash(git branch:*)" "Bash(git tag:*)" "Bash(git push:*)"
        "Bash(git clean:*)" "Bash(git cherry-pick:*)" "Bash(rm:*)")
      if [[ $role == review ]]; then
        deny+=(Edit Write NotebookEdit)
      else
        allow+=(Edit Write "Bash(mise exec -- ./scripts/format.sh:*)" "Bash(mise exec -- ./scripts/strings.sh:*)"
          "Bash($FORK_DIR/gate.sh:*)")
      fi
      # disableAllHooks: the user's own hooks (an output style, a notifier) do
      # not belong in a scripted run.
      (cd "$SYNC_DIR" && claude -p --permission-mode dontAsk --strict-mcp-config \
        --settings '{"disableAllHooks": true}' \
        ${OFF_CLAUDE_MODEL:+--model "$OFF_CLAUDE_MODEL"} \
        --allowedTools "${allow[@]}" --disallowedTools "${deny[@]}" \
        <"$prompt" >"$answer" 2>"$log") || say "   claude exited with an error (see $log)"
      ;;
    codex)
      # workspace-write cannot write the repository's .git folder, which is
      # outside the worktree, so codex cannot change refs either.
      local sandbox=workspace-write
      [[ $role == review ]] && sandbox=read-only
      codex exec -C "$SYNC_DIR" -s "$sandbox" --color never \
        ${OFF_CODEX_MODEL:+-m "$OFF_CODEX_MODEL"} \
        -o "$answer" - <"$prompt" >"$log" 2>&1 || say "   codex exited with an error (see $log)"
      ;;
  esac
  [[ -s $answer ]] || echo "(The agent gave no answer. See $log.)" >"$answer"
}

context_header() {
  local label=$1
  echo
  echo "## Context"
  echo
  echo "- Worktree (your working directory): \`$SYNC_DIR\`"
  echo "- Branch: \`$(next_branch "$label")\`, the next version of \`$(src_branch "$label")\`"
  echo "- New upstream main: $(R log -1 --format='`%h` %s' "$UPSTREAM_SHA")"
  if [[ -n $(get "$label" old-base) ]]; then
    echo "- Old upstream base of the branch: $(R log -1 --format='`%h` %s' "$(get "$label" old-base)")"
  fi
}

descriptions() {
  local feature=$1
  echo
  echo "## Fork rules (fork/AGENTS.md)"
  echo
  R show off/base:fork/AGENTS.md
  if [[ -n $feature && $feature != base && $feature != main ]]; then
    echo
    echo "## Feature description (fork/features/$feature.md)"
    echo
    R show "$(src_branch "$feature"):fork/features/$feature.md" 2>/dev/null || echo "(The branch has no description.)"
  fi
}

# ─── Rebase and merge ───────────────────────────────────────────────────────

in_progress() {
  if [[ $1 == rebase ]]; then
    [[ -d $(W rev-parse --path-format=absolute --git-path rebase-merge) ||
      -d $(W rev-parse --path-format=absolute --git-path rebase-apply) ]]
  else
    W rev-parse -q --verify MERGE_HEAD >/dev/null
  fi
}

# resolve_conflicts <label> <rebase|merge> <log> [feature]
# Returns 1 when a conflict stays. The caller aborts the operation.
resolve_conflicts() {
  local label=$1 kind=$2 log=$3 feature=${4:-$1}
  local round=0 files f tag=$1
  [[ $kind == merge ]] && tag="$label-$feature"
  while in_progress "$kind"; do
    round=$((round + 1))
    ((round <= 30)) || return 1
    files="$(W diff --name-only --diff-filter=U)"
    if [[ -z $files ]]; then
      # rerere resolved the conflicts, or the commit is empty now.
      if [[ $kind == merge ]]; then
        W commit -q --no-edit >>"$log" 2>&1 || return 1
      elif ! GIT_EDITOR=true W rebase --continue >>"$log" 2>&1; then
        if [[ -z $(W diff --name-only --diff-filter=U) ]] && W diff --cached --quiet; then
          W rebase --skip >>"$log" 2>&1 || return 1
        fi
      fi
      continue
    fi

    local prompt="$RUN_DIR/$tag.resolve-$round.prompt.md"
    local answer="$RUN_DIR/$tag.resolve-$round.md"
    local paths=()
    while IFS= read -r f; do paths+=("$f"); done <<<"$files"
    {
      cat "$FORK_DIR/prompts/resolve.md"
      context_header "$label"
      if [[ $kind == rebase ]]; then
        echo "- Operation: \`git rebase\` onto the new upstream main. It stopped at this commit of the fork:"
        echo
        echo '```'
        W log -1 --format='%h %s%n%n%b' REBASE_HEAD
        echo '```'
      else
        echo "- Operation: \`git merge\` of \`$(next_branch "$feature")\` into \`off/next/main\`."
        echo "  The conflict is between this feature and the fork identity or an earlier feature."
      fi
      echo
      echo "Files with conflicts:"
      echo
      printf -- '- `%s`\n' "${paths[@]}"
      if [[ -n $(get "$label" old-base) ]]; then
        echo
        echo "## Upstream commits since the old base that change these files"
        echo
        R log --format='- `%h` %s' "$(get "$label" old-base)..$UPSTREAM_SHA" -- "${paths[@]}"
      fi
      descriptions "$feature"
    } >"$prompt"
    run_agent resolve "$AGENT" "$prompt" "$answer"

    for f in "${paths[@]}"; do
      if [[ -f $SYNC_DIR/$f ]] && grep -qE '^(<<<<<<<|>>>>>>>)( |$)' "$SYNC_DIR/$f"; then
        say "   a conflict stays in $f"
        return 1
      fi
    done
    for f in "${paths[@]}"; do W add -A -- "$f"; done
    printf '%s\n' "${paths[@]}" >>"$RUN_DIR/$tag.conflicts"
    {
      echo "**Conflicts resolved by $AGENT** (round $round): $(printf '`%s` ' "${paths[@]}")"
      echo
      sed 's/^/> /' "$answer"
      echo
    } | sec "$label"
    if [[ $kind == merge ]]; then
      W commit -q --no-edit >>"$log" 2>&1 || return 1
    else
      GIT_EDITOR=true W rebase --continue >>"$log" 2>&1 || true
    fi
  done
  return 0
}

# ─── Gate and fixes ─────────────────────────────────────────────────────────

# The lines of a gate log that name the failure, then the end of the log.
log_excerpt() {
  echo "Lines that name a failure:"
  echo '```'
  grep -nE 'error:|recorded an issue|Expectation failed|failed after|FAILED|✖|❌|Error:|not in sync|identity:' "$1" | head -n 80 || true
  echo '```'
  echo
  echo "The end of the log:"
  echo '```'
  tail -n 60 "$1"
  echo '```'
}

# gate_with_fixes <label> <steps> [e2e selector]...
gate_with_fixes() {
  local label=$1 steps=$2
  shift 2
  local e2e_args=() s
  for s in "$@"; do e2e_args+=(--e2e "$s"); done
  local attempt=0 out failed step_log
  while :; do
    out="$RUN_DIR/$label.gate-$attempt.txt"
    if ((attempt == 0)); then say "   gate: $steps"; else say "   gate again, after fix $attempt"; fi
    if (cd "$SYNC_DIR" && "$FORK_DIR/gate.sh" --steps "$steps" --logs "$RUN_DIR/gate/$label-$attempt" \
      ${e2e_args[@]+"${e2e_args[@]}"}) >"$out" 2>&1; then
      sed 's/^/     /' "$out" >&2
      { echo "**Gate** (after $attempt fixes):"; echo; echo '```'; cat "$out"; echo '```'; echo; } | sec "$label"
      return 0
    fi
    sed 's/^/     /' "$out" >&2
    { echo "**Gate** (after $attempt fixes):"; echo; echo '```'; cat "$out"; echo '```'; echo; } | sec "$label"
    failed="$(awk '$1 == "FAIL" { print $2 }' "$out")"
    step_log="$(awk '$1 == "FAIL" { print $4 }' "$out")"
    put "$label" failed-step "${failed:-gate}"
    # No fixes on off/next/main: a fix there would be lost at the next sync.
    [[ $label != main && -n $failed && $attempt -lt $ATTEMPTS ]] || return 1
    attempt=$((attempt + 1))
    fix_branch "$label" "$failed" "$step_log" "$attempt" "$steps" || return 1
  done
}

fix_branch() {
  local label=$1 step=$2 step_log=$3 attempt=$4 steps=$5
  local prompt="$RUN_DIR/$label.fix-$attempt.prompt.md" answer="$RUN_DIR/$label.fix-$attempt.md"
  {
    cat "$FORK_DIR/prompts/fix.md"
    context_header "$label"
    echo
    echo "## The failing step: $step"
    echo
    echo "The gate command, to run at the root of the worktree:"
    echo
    echo "    $FORK_DIR/gate.sh --steps $steps"
    echo
    log_excerpt "$step_log"
    descriptions "$label"
  } >"$prompt"
  run_agent fix "$AGENT" "$prompt" "$answer"
  if [[ -z $(W status --porcelain) ]]; then
    say "   $AGENT changed nothing"
    return 1
  fi
  local subject
  subject="$(head -n 1 "$answer" | sed -E 's/^#+[[:space:]]*//; s/^[`*"]+//; s/[`*"]+$//' | cut -c1-72)"
  [[ -n $subject && $subject != "(The agent"* ]] || subject="Adapt $label to upstream $(short "$UPSTREAM_SHA")"
  W add -A
  W commit -q -m "$subject" \
    -m "fork/sync.sh: the $step step of the gate failed after the move onto upstream $(short "$UPSTREAM_SHA")."
  W rev-parse HEAD >>"$RUN_DIR/$label.fix-commits"
  {
    echo "**Fix $attempt by $AGENT** (\`$(W rev-parse --short HEAD)\` $subject):"
    echo
    sed 's/^/> /' "$answer"
    echo
  } | sec "$label"
}

# ─── Review ─────────────────────────────────────────────────────────────────

review_branch() {
  local label=$1 dst old_base old_tip f
  [[ $REVIEWER != none ]] || {
    put "$label" review "off"
    return 0
  }
  dst="$(next_branch "$label")"
  old_base="$(get "$label" old-base)"
  old_tip="$(get "$label" old-tip)"
  local files=() touched=()
  while IFS= read -r f; do [[ -n $f ]] && files+=("$f"); done < <(R diff --name-only "$UPSTREAM_SHA" "$dst" -- . ':(exclude)fork')
  if ((${#files[@]})); then
    while IFS= read -r f; do [[ -n $f ]] && touched+=("$f"); done < <(R diff --name-only "$old_base" "$UPSTREAM_SHA" -- "${files[@]}")
  fi
  if ((${#touched[@]} == 0)) && [[ ! -s $RUN_DIR/$label.conflicts && ! -s $RUN_DIR/$label.fix-commits ]] && ((REVIEW_ALL == 0)); then
    put "$label" review "not needed"
    return 0
  fi
  local prompt="$RUN_DIR/$label.review.prompt.md" answer="$RUN_DIR/$label.review.md"
  {
    cat "$FORK_DIR/prompts/review.md"
    context_header "$label"
    echo
    echo "## Files that the branch changes"
    echo
    if ((${#files[@]})); then printf -- '- `%s`\n' "${files[@]}"; else echo "(none)"; fi
    if ((${#touched[@]})); then
      echo
      echo "## Upstream commits since the old base that change these files"
      echo
      R log --format='- `%h` %s' "$old_base..$UPSTREAM_SHA" -- "${touched[@]}"
      echo
      echo "## Upstream diff of these files (at most 1500 lines)"
      echo
      echo '```diff'
      R diff "$old_base" "$UPSTREAM_SHA" -- "${touched[@]}" | head -n 1500 || true
      echo '```'
    fi
    echo
    echo "## Changes to upstream's AGENTS.md since the old base (at most 300 lines)"
    echo
    echo '```diff'
    R diff "$old_base" "$UPSTREAM_SHA" -- AGENTS.md | head -n 300 || true
    echo '```'
    echo
    echo "## Range-diff of the branch (old commits, then new commits)"
    echo
    echo '```'
    R range-diff "$old_base..$old_tip" "$UPSTREAM_SHA..$dst"
    echo '```'
    local a
    for a in "$RUN_DIR/$label".resolve-[0-9]*.md "$RUN_DIR/$label".fix-[0-9]*.md; do
      [[ -f $a && $a != *.prompt.md ]] || continue
      echo
      echo "## Answer of an agent in this sync: $(basename "$a")"
      echo
      cat "$a"
    done
    descriptions "$label"
  } >"$prompt"
  run_agent review "$REVIEWER" "$prompt" "$answer"
  local verdict
  verdict="$(grep -m1 -oE 'VERDICT: (KEEP|ADAPT|RETIRE)' "$answer" | cut -d' ' -f2 || true)"
  put "$label" review "${verdict:-unclear}"
  {
    echo "**Review by $REVIEWER: ${verdict:-unclear}**"
    echo
    sed 's/^/> /' "$answer"
    echo
  } | sec "$label"
}

# ─── Description ────────────────────────────────────────────────────────────

# After a rebase with resolved conflicts, the agent brings the feature's
# description up to date. During the rebase the description was not there:
# it is a later commit of the branch.
update_description() {
  local label=$1 doc="fork/features/$1.md" a line f
  [[ -f $SYNC_DIR/$doc ]] || return 0
  local prompt="$RUN_DIR/$label.describe.prompt.md" answer="$RUN_DIR/$label.describe.md"
  {
    sed -e "s|<name>|$label|g" -e "s|<date>|$(date +%Y-%m-%d)|g" -e "s|<sha>|$(short "$UPSTREAM_SHA")|g" \
      "$FORK_DIR/prompts/describe.md"
    context_header "$label"
    for a in "$RUN_DIR/$label".resolve-[0-9]*.md; do
      [[ -f $a && $a != *.prompt.md ]] || continue
      echo
      echo "## Answer of the agent that resolved the conflicts ($(basename "$a"))"
      echo
      cat "$a"
    done
    echo
    echo "## The feature on top of the new upstream (at most 1500 lines)"
    echo
    echo '```diff'
    W diff "$UPSTREAM_SHA" HEAD -- . ':(exclude)fork' | head -n 1500 || true
    echo '```'
  } >"$prompt"
  run_agent fix "$AGENT" "$prompt" "$answer"
  # Keep only the description. Other files are not for this step.
  while IFS= read -r line; do
    f="${line:3}"
    [[ -n $f && $f != "$doc" ]] || continue
    if [[ ${line:0:2} == "??" ]]; then rm -rf "${SYNC_DIR:?}/$f"; else W restore --source=HEAD --staged --worktree -- "$f"; fi
    say "   dropped a change outside the description: $f"
  done < <(W status --porcelain)
  [[ -n $(W status --porcelain -- "$doc") ]] || return 0
  W add -- "$doc"
  W commit -q -m "Update the $label description for upstream $(short "$UPSTREAM_SHA")" \
    -m "fork/sync.sh: the rebase onto upstream $(short "$UPSTREAM_SHA") resolved conflicts in this feature."
  W rev-parse HEAD >>"$RUN_DIR/$label.fix-commits"
  {
    echo "**Description updated by $AGENT** (\`$(W rev-parse --short HEAD)\`): $(head -n 1 "$answer")"
    echo
  } | sec "$label"
}

# ─── One branch ─────────────────────────────────────────────────────────────

sync_one() {
  local label=$1 src dst old_tip old_base log
  src="$(src_branch "$label")"
  dst="$(next_branch "$label")"
  say ""
  say "== $label ($src)"
  echo "## \`$src\`" | sec "$label"
  echo | sec "$label"
  if ! R rev-parse -q --verify "refs/heads/$src" >/dev/null; then
    put "$label" status missing
    put "$label" rebase "no branch $src"
    return 0
  fi
  old_tip="$(R rev-parse "$src")"
  old_base="$(R merge-base "$src" "$UPSTREAM_SHA")"
  put "$label" old-tip "$old_tip"
  put "$label" old-base "$old_base"
  W checkout -q -B "$dst" "$old_tip"

  log="$RUN_DIR/$label.rebase.log"
  if W -c rerere.enabled=true -c rerere.autoUpdate=true rebase --empty=drop "$UPSTREAM_SHA" >"$log" 2>&1; then
    if [[ $old_base == "$UPSTREAM_SHA" ]]; then put "$label" rebase "up to date"; else put "$label" rebase clean; fi
  elif resolve_conflicts "$label" rebase "$log"; then
    put "$label" rebase "resolved by $AGENT ($(sort -u "$RUN_DIR/$label.conflicts" | wc -l | tr -d ' ') files)"
  else
    W rebase --abort >/dev/null 2>&1 || true
    put "$label" rebase "conflict not resolved"
    put "$label" status failed
    say "   the rebase stopped on a conflict that stays; $src is not moved"
    return 0
  fi
  say "   rebase: $(get "$label" rebase)"

  # Commits that upstream has now, with the same patch.
  local mark sha subject twin dropped=0
  while read -r mark sha subject; do
    [[ $mark == - ]] || continue
    dropped=$((dropped + 1))
    twin="$(upstream_twin "$sha" "$old_base")" || twin=""
    put "$label" twin "$(R log -1 --format='%h %s' "${twin:-$sha}")"
    echo "- Upstream has \`$(short "$sha")\` $subject, as $(R log -1 --format='`%h` %s' "${twin:-$sha}")." | sec "$label"
  done < <(R cherry -v "$UPSTREAM_SHA" "$old_tip" "$old_base")
  ((dropped == 0)) || put "$label" rebase "$(get "$label" rebase), $dropped dropped"

  if [[ $label != base && -z $(W diff --name-only "$UPSTREAM_SHA" HEAD -- . ':(exclude)fork') ]]; then
    put "$label" status retired
    put "$label" gate "-"
    put "$label" review "-"
    { echo; echo "No code of the feature is left on top of upstream: the feature is retired."; echo; } | sec "$label"
    say "   retired: upstream has all of its code"
    return 0
  fi

  if [[ $label != base && -s $RUN_DIR/$label.conflicts ]]; then
    update_description "$label"
  fi

  if [[ $GATES == full ]]; then
    local steps="setup,format,lint,unit,strings"
    [[ $label == base ]] && steps="setup,identity,format,lint,unit,strings"
    if gate_with_fixes "$label" "$steps"; then
      if [[ -s $RUN_DIR/$label.fix-commits ]]; then
        put "$label" gate "pass after $(wc -l <"$RUN_DIR/$label.fix-commits" | tr -d ' ') fix"
      else
        put "$label" gate pass
      fi
    else
      put "$label" gate "fail: $(get "$label" failed-step)"
      put "$label" status failed
    fi
  else
    put "$label" gate "-"
  fi

  if [[ $(get "$label" status) != failed ]]; then
    review_branch "$label"
    put "$label" status ready
  else
    put "$label" review "-"
  fi
  {
    echo
    echo "**Range-diff** (\`$(short "$old_base")..$(short "$old_tip")\` → \`$(short "$UPSTREAM_SHA")..$dst\`):"
    echo
    echo '```'
    R range-diff "$old_base..$old_tip" "$UPSTREAM_SHA..$dst" || true
    echo '```'
    echo
  } | sec "$label"
}

retire_features() {
  local retired=() f
  for f in ${FEATURES[@]+"${FEATURES[@]}"}; do
    [[ $(get "$f" status) == retired ]] && retired+=("$f")
  done
  ((${#retired[@]})) || return 0
  [[ $(get base status) == ready ]] || return 0
  W checkout -q off/next/base
  local manifest="$SYNC_DIR/fork/manifest"
  for f in "${retired[@]}"; do
    awk -v name="$f" '{ line = $0; sub(/#.*/, "", line); gsub(/[[:space:]]/, "", line) } line != name' \
      "$manifest" >"$manifest.new"
    mv "$manifest.new" "$manifest"
    echo "# retired $(date +%Y-%m-%d): $f (upstream $(get "$f" twin))" >>"$manifest"
  done
  W add fork/manifest
  W commit -q -m "Retire ${retired[*]} from the fork, because upstream has it now" \
    -m "$(for f in "${retired[@]}"; do echo "$f: upstream $(get "$f" twin)"; done)"
  say ""
  say "== off/next/base: retired ${retired[*]} in fork/manifest"
}

build_integration() {
  say ""
  say "== off/next/main"
  echo "## \`off/main\`" | sec main
  echo | sec main
  if [[ $(get base status) != ready ]]; then
    put main status failed
    put main rebase "not built: off/base is not ready"
    put main gate "-"
    put main review "-"
    return 0
  fi
  W checkout -q -B off/next/main off/next/base
  local merged=() e2e=() sels=() f sel log="$RUN_DIR/main.merge.log"
  for f in ${FEATURES[@]+"${FEATURES[@]}"}; do
    [[ $(get "$f" status) == ready ]] || continue
    if W -c rerere.enabled=true -c rerere.autoUpdate=true merge --no-ff --no-edit -m "Merge off/feat/$f" \
      "off/next/feat/$f" >>"$log" 2>&1 || resolve_conflicts main merge "$log" "$f"; then
      merged+=("$f")
      read -r -a sels <<<"$(front_matter "off/next/feat/$f" "fork/features/$f.md" e2e || true)"
      for sel in ${sels[@]+"${sels[@]}"}; do e2e+=("$sel"); done
    else
      W merge --abort >/dev/null 2>&1 || true
      put "$f" status excluded
      echo "- \`$f\` is not in the integration: its merge has a conflict that stays." | sec main
      say "   $f: the merge has a conflict that stays; it is left out"
    fi
  done
  put main rebase "merged: ${merged[*]:-none}"
  say "   merged: ${merged[*]:-none}"
  put main review "-"
  if [[ $GATES == none ]]; then
    put main gate "-"
    put main status ready
    return 0
  fi
  local steps="setup,identity,format,lint,unit,strings" note=""
  if ((E2E)) && ((${#e2e[@]})); then
    steps="$steps,e2e"
    note=" (with ${#e2e[@]} e2e)"
    say "   the e2e step opens hermetic app windows that take the keyboard focus"
  fi
  if gate_with_fixes main "$steps" ${e2e[@]+"${e2e[@]}"}; then
    put main gate "pass$note"
    put main status ready
  else
    put main gate "fail: $(get main failed-step)"
    put main status failed
  fi
}

write_report() {
  local label first_base
  first_base="$(get base old-base)"
  {
    echo "# MactermOff sync $RUN_ID"
    echo
    echo "- Upstream: \`$UPSTREAM\` at $(R log -1 --format='`%h` %s' "$UPSTREAM_SHA")"
    echo "- Agent: $AGENT. Reviewer: $REVIEWER. Gates: $GATES$( ((E2E)) || echo ', no e2e')."
    echo
    echo "| Branch | Rebase | Gate | Review | Result |"
    echo "|---|---|---|---|---|"
    for label in base ${FEATURES[@]+"${FEATURES[@]}"} main; do
      echo "| \`$(next_branch "$label")\` | $(get "$label" rebase) | $(get "$label" gate) | $(get "$label" review) | **$(get "$label" status)** |"
    done
    if [[ -n $first_base && $first_base != "$UPSTREAM_SHA" ]]; then
      echo
      echo "## New upstream commits"
      echo
      R log --format='- `%h` %s' "$first_base..$UPSTREAM_SHA"
    fi
    echo
    for label in base ${FEATURES[@]+"${FEATURES[@]}"} main; do
      [[ -f $RUN_DIR/$label.section.md ]] && cat "$RUN_DIR/$label.section.md"
    done
    echo "## Next"
    echo
    echo "- Read the agent answers and the range-diffs above. Test the app: \`git -C $SYNC_DIR switch off/next/main\`, then build there."
    echo "- \`fork/sync.sh promote\` moves the ready branches to \`off/*\` and pushes them. \`fork/sync.sh abandon\` drops this sync."
    echo "- The files of this run (prompts, agent logs, gate logs): \`$RUN_DIR\`"
  } >"$REPORT"
}

# ─── Commands ───────────────────────────────────────────────────────────────

cmd_sync() {
  AGENT=claude REVIEWER=codex GATES=full ATTEMPTS=2 FETCH=1 E2E=1 REVIEW_ALL=0
  while (($#)); do
    case "$1" in
      --agent) AGENT=$2; shift 2 ;;
      --reviewer) REVIEWER=$2; shift 2 ;;
      --gates) GATES=$2; shift 2 ;;
      --attempts) ATTEMPTS=$2; shift 2 ;;
      --no-e2e) E2E=0; shift ;;
      --review-all) REVIEW_ALL=1; shift ;;
      --no-fetch) FETCH=0; shift ;;
      *) die "unknown option of sync: $1" ;;
    esac
  done
  [[ $AGENT == claude || $AGENT == codex ]] || die "--agent is claude or codex"
  [[ $REVIEWER == claude || $REVIEWER == codex || $REVIEWER == none ]] || die "--reviewer is claude, codex or none"
  [[ $GATES == full || $GATES == quick || $GATES == none ]] || die "--gates is full, quick or none"
  command -v "$AGENT" >/dev/null || die "$AGENT is not installed"
  [[ $REVIEWER == none ]] || command -v "$REVIEWER" >/dev/null || die "$REVIEWER is not installed"
  [[ ! -f $STATE_DIR/pending ]] || die "the sync $(cat "$STATE_DIR/pending") waits: run 'fork/sync.sh promote' or 'fork/sync.sh abandon'"
  [[ -z $(R for-each-ref refs/heads/off/next) ]] || die "off/next/* branches exist: run 'fork/sync.sh abandon'"
  R rev-parse -q --verify refs/heads/off/base >/dev/null || die "off/base does not exist"
  mkdir "$STATE_DIR/lock" 2>/dev/null || die "another sync runs (or remove $STATE_DIR/lock)"
  trap 'rmdir "$STATE_DIR/lock" 2>/dev/null' EXIT

  if ((FETCH)); then
    say "Fetching ${UPSTREAM%%/*}"
    R fetch --quiet "${UPSTREAM%%/*}"
  fi
  UPSTREAM_SHA="$(R rev-parse --verify "$UPSTREAM^{commit}")"
  RUN_ID="$(date +%Y%m%d-%H%M%S)"
  RUN_DIR="$STATE_DIR/runs/$RUN_ID"
  REPORT="$STATE_DIR/reports/$RUN_ID.md"
  mkdir -p "$RUN_DIR"
  FEATURES=()
  local f
  while IFS= read -r f; do
    [[ $f != base && $f != main ]] || die "a feature cannot have the name $f"
    FEATURES+=("$f")
  done < <(features)
  printf '%s\n' ${FEATURES[@]+"${FEATURES[@]}"} >"$RUN_DIR/features"
  echo "$UPSTREAM_SHA" >"$RUN_DIR/upstream"
  # The fork's branch tips now: promote pushes with these as the lease.
  if ! git ls-remote "$PUSH_URL" 'refs/heads/off/*' >"$RUN_DIR/remote-tips" 2>"$RUN_DIR/remote-tips.err"; then
    rm -f "$RUN_DIR/remote-tips"
    say "warning: cannot read $PUSH_URL; promote will not push"
  fi

  say "Upstream: $(R log -1 --format='%h %s' "$UPSTREAM_SHA")"
  say "Features: ${FEATURES[*]:-none}"
  if [[ ! -e $SYNC_DIR/.git ]]; then
    say "Creating the sync worktree $SYNC_DIR"
    R worktree add --quiet --detach "$SYNC_DIR" "$UPSTREAM_SHA"
  fi
  # A sync that stopped can leave an operation or changes behind.
  W rebase --abort >/dev/null 2>&1 || true
  W merge --abort >/dev/null 2>&1 || true
  W reset -q --hard
  W clean -fdq
  W checkout -q --detach "$UPSTREAM_SHA"

  sync_one base
  for f in ${FEATURES[@]+"${FEATURES[@]}"}; do sync_one "$f"; done
  retire_features
  build_integration
  W checkout -q --detach

  write_report
  ln -sfn "$REPORT" "$STATE_DIR/reports/latest.md"
  echo "$RUN_ID" >"$STATE_DIR/pending"
  echo
  sed -n '/^| Branch/,/^$/p' "$REPORT"
  echo "Report: $REPORT"
  echo "Next: read it, then run 'fork/sync.sh promote' or 'fork/sync.sh abandon'."
}

cmd_promote() {
  local push=1 force=0
  while (($#)); do
    case "$1" in
      --no-push) push=0; shift ;;
      --force) force=1; shift ;;
      *) die "unknown option of promote: $1" ;;
    esac
  done
  [[ -f $STATE_DIR/pending ]] || die "no sync waits for promote"
  RUN_ID="$(cat "$STATE_DIR/pending")"
  RUN_DIR="$STATE_DIR/runs/$RUN_ID"
  if ((force == 0)); then
    [[ $(get base status) == ready ]] || die "off/next/base is $(get base status). Fix it, or use --force"
    [[ $(get main status) == ready ]] || die "off/next/main is $(get main status). Fix it, or use --force"
  fi
  local f label b nb wt status stamp
  local labels=(base) moves=() deletes=()
  while IFS= read -r f; do [[ -n $f ]] && labels+=("$f"); done <"$RUN_DIR/features"
  labels+=(main)

  # 1. Plan, and check each worktree, before anything moves.
  W checkout -q --detach 2>/dev/null || true
  for label in "${labels[@]}"; do
    nb="$(next_branch "$label")"
    if [[ $label == main ]]; then b=off/main; else b="$(src_branch "$label")"; fi
    status="$(get "$label" status)"
    wt="$(worktree_of "$b")"
    if [[ $status == retired ]]; then
      R rev-parse -q --verify "refs/heads/$b" >/dev/null || continue
      [[ -z $wt ]] || die "$wt has $b checked out. Switch it to another branch, then run promote again"
      deletes+=("$b")
    elif { [[ $status == ready ]] || ((force)); } && R rev-parse -q --verify "refs/heads/$nb" >/dev/null; then
      if R rev-parse -q --verify "refs/heads/$b" >/dev/null && [[ $(R rev-parse "$b") == "$(R rev-parse "$nb")" ]]; then
        say "unchanged: $b"
        continue
      fi
      if [[ -n $wt && -n $(git -C "$wt" status --porcelain --untracked-files=no) ]]; then
        die "$wt has changes on $b. Commit or stash them, then run promote again"
      fi
      moves+=("$b")
    else
      say "kept: $b ($status)"
    fi
  done

  # 2. Push first. When the fork refuses, nothing moves here.
  if ((push)) && ((${#moves[@]} + ${#deletes[@]})); then
    [[ -f $RUN_DIR/remote-tips ]] || die "the sync could not read the fork, so there is no lease. Use --no-push, and push by hand"
    local args=() refspecs=() sha
    for b in ${moves[@]+"${moves[@]}"}; do
      sha="$(awk -v ref="refs/heads/$b" '$2 == ref { print $1 }' "$RUN_DIR/remote-tips")"
      args+=("--force-with-lease=refs/heads/$b:$sha")
      refspecs+=("refs/heads/off/next/${b#off/}:refs/heads/$b")
    done
    for b in ${deletes[@]+"${deletes[@]}"}; do
      sha="$(awk -v ref="refs/heads/$b" '$2 == ref { print $1 }' "$RUN_DIR/remote-tips")"
      [[ -n $sha ]] || continue
      args+=("--force-with-lease=refs/heads/$b:$sha")
      refspecs+=(":refs/heads/$b")
    done
    if ((${#refspecs[@]})); then
      say "Pushing to $PUSH_URL"
      R push --atomic "$PUSH_URL" "${args[@]}" "${refspecs[@]}" ||
        die "the fork refused the push, and nothing moved here. The fork changed after the sync read it: look at it, then run 'fork/sync.sh abandon' and sync again"
    fi
  fi

  # 3. Move the local branches, with a backup tag of each old tip.
  stamp="$(date +%Y%m%d-%H%M%S)"
  for b in ${moves[@]+"${moves[@]}"}; do
    nb="off/next/${b#off/}"
    R rev-parse -q --verify "refs/heads/$b" >/dev/null && R tag "off-backup/$stamp/${b#off/}" "$b"
    wt="$(worktree_of "$b")"
    if [[ -n $wt ]]; then
      git -C "$wt" checkout -q -B "$b" "$nb"
    else
      R branch -q -f "$b" "$nb"
    fi
    say "moved: $b -> $(R log -1 --format='%h %s' "$b")"
  done
  for b in ${deletes[@]+"${deletes[@]}"}; do
    R tag "off-backup/$stamp/${b#off/}" "$b"
    R branch -q -D "$b"
    say "retired: deleted $b (backup: off-backup/$stamp/${b#off/})"
  done
  for label in "${labels[@]}"; do
    R branch -q -D "$(next_branch "$label")" 2>/dev/null || true
  done
  rm -f "$STATE_DIR/pending"
}

cmd_abandon() {
  W checkout -q --detach 2>/dev/null || true
  local b
  while IFS= read -r b; do
    [[ -n $b ]] && R branch -q -D "$b" && say "deleted $b"
  done < <(R for-each-ref --format='%(refname:short)' refs/heads/off/next)
  rm -f "$STATE_DIR/pending"
}

cmd_status() {
  local up b counts
  up="$(R rev-parse --verify "$UPSTREAM^{commit}")"
  echo "Upstream $UPSTREAM: $(R log -1 --format='%h %s (%cr)' "$up")"
  while IFS= read -r b; do
    counts="$(R rev-list --left-right --count "$up...$b")"
    printf '  %-34s %3s ahead, %3s behind\n' "$b" "${counts##*[[:space:]]}" "${counts%%[[:space:]]*}"
  done < <(R for-each-ref --format='%(refname:short)' refs/heads/off)
  if [[ -f $STATE_DIR/pending ]]; then
    echo "The sync $(cat "$STATE_DIR/pending") waits for promote or abandon."
  fi
  [[ -e $STATE_DIR/reports/latest.md ]] && echo "Last report: $(readlink "$STATE_DIR/reports/latest.md")"
  return 0
}

main() {
  set -euo pipefail
  init
  local command=${1:-help}
  shift || true
  case "$command" in
    sync) cmd_sync "$@" ;;
    promote) cmd_promote "$@" ;;
    abandon) cmd_abandon "$@" ;;
    status) cmd_status "$@" ;;
    help | -h | --help) usage ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
