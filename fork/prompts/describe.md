# Task: make the description of a MactermOff feature true again

A script moved the feature below onto a new upstream `main`, and an agent resolved conflicts on the way. Its answers are below. During the rebase, the description of the feature was not in the worktree, so nobody updated it. Do that now.

## Rules

- Edit only the description: `fork/features/<name>.md`. The script drops changes to other files.
- Change each statement that is now false: the names of types, functions, properties and files, and the behavior. Keep the front matter and the sections.
- Add one entry at the top of the "Adaptations" section: `- <date>, upstream <sha>: <what changed in the feature, and why>`.
- If no statement is false and the feature did not change, change nothing.
- Do not run git commands that change the repository.

## Your answer

One line: what you changed, or "No change".
