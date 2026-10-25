# Task: make a MactermOff branch pass its checks again

You work in a git worktree of MactermOff, a fork of Macterm (a macOS terminal app in Swift). A script moved the branch below onto a new upstream `main`. Then a step of the gate failed. The step and the end of its log are below.

## Rules

- Find the cause. Usually upstream renamed, moved or changed something that the branch uses, or a test of the branch expects the old upstream behavior.
- Change the branch so that it does what its description says, on top of the new upstream code. Make the smallest change. Do not change upstream code that the branch does not already change.
- Never delete, skip or weaken a test to make it pass. If upstream removed the behavior that a test checks, say so in your answer, and stop.
- A format failure: run `mise exec -- ./scripts/format.sh` (it fixes the files in place).
- A strings failure: run `mise exec -- ./scripts/strings.sh` (it updates the catalog), then add the `ko` and `zh-Hans` translations of each new entry.
- An identity failure on `off/base`: upstream added a line that names Macterm's identity. Change it for MactermOff as `fork/AGENTS.md` (Identity) says, or, if the line is not shared state, add it to `fork/identity-allowlist.txt`.
- An identity failure on a feature branch: the feature adds a line that names Macterm's identity, for example a path in `~/.config/macterm`. A feature must work in upstream Macterm and in MactermOff, so never write a MactermOff name or path in it. Remove the hard-coded name instead: take the path from the app (a CLI answer, `ProjectFileStore.defaultConfigDirectory()`) or from the output of the command that made the file.
- To check your work, run the gate command below with the failing step. It can take several minutes.
- Do not run git commands that change the repository (`commit`, `add`, `rebase`, `merge`, `reset`, `checkout`, `switch`, `restore`, `stash`, `branch`, `tag`, `push`). Leave your changes in the working tree. The script commits them.
- On a feature branch, add a dated entry to the "Adaptations" section of its description (`fork/features/<name>.md`) for each change that you make, also a change to a test only: what changed and why. Change other statements of the description that your change makes false.

## Your answer

The first line is the subject of the commit for your change: what it does and why, in the style of upstream's commits, at most 72 characters. Then an empty line. Then a short Markdown summary: the cause, the change, and what a reviewer must check.
