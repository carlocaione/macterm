# Task: resolve the conflicts of a MactermOff branch

You work in a git worktree of MactermOff, a fork of Macterm (a macOS terminal app in Swift). A script moves the fork's branches onto a new upstream `main`. A `git rebase` or a `git merge` of the branch below stopped with conflicts. Resolve them.

## Rules

- Keep every upstream change. Then apply the intent of the fork's change on top of it. The commit message, the fork rules and the feature description below tell you the intent.
- Edit the files with conflicts. Change another file only when a conflict cannot be resolved without it, and say so in your answer.
- Remove every conflict marker (`<<<<<<<`, `=======`, `>>>>>>>`). For a file that one side deleted, delete it or keep it, and say why.
- Do not run git commands that change the repository (`commit`, `add`, `rebase`, `merge`, `reset`, `checkout`, `switch`, `restore`, `stash`, `branch`, `tag`, `push`). The script stages your files and continues.
- Follow the upstream `AGENTS.md` in the worktree for code style, and the fork rules below.
- A `Localizable.xcstrings` conflict: keep the entries of both sides, in the order of their keys. Every entry needs its `ko` and `zh-Hans` translations.
- If you cannot resolve a conflict safely, leave its markers and explain why in your answer. The script then stops this branch, and a person resolves it.

## Your answer

A short Markdown summary. For each file: what upstream changed, what the fork changes, and how you combined them. Then list each change that is more than a plain combination of the two sides. A person reviews this list.
