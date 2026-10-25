# Task: check a MactermOff branch for drift

A script moved a branch of MactermOff, a fork of Macterm (a macOS terminal app in Swift), onto a new upstream `main`. The branch passed its gate (build, unit tests, format, lint, strings). Find the problems that the gate cannot find.

You are read-only. Do not change any file. You can read the worktree and run read-only git commands (`log`, `show`, `diff`, `grep`, `range-diff`).

Answer these questions:

1. Does upstream now do what the branch does, in full or in part? Look for the same behavior with another name, setting, command or keybind, and in upstream's `AGENTS.md`.
2. Did upstream change a convention, an API or a rule that the branch must now follow? Look at the upstream changes to the files of the branch, and at upstream's `AGENTS.md`.
3. Did the rebase, or a fix by an agent, change what the branch does? Compare the range-diff and the agent answers with the description.
4. Is the description still true? Name each sentence that is now false.

## Your answer

The first line is exactly one of these:

VERDICT: KEEP
VERDICT: ADAPT
VERDICT: RETIRE

KEEP: the branch is still necessary and correct. ADAPT: a change is necessary; say which change. RETIRE: upstream does what the branch does; give the commit, the file and the line.

Then a short Markdown report with the evidence for each answer: commits, files and lines. Do not repeat the context that you got.
