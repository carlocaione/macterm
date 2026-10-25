# MactermOff: the fork

MactermOff is a personal fork of [Macterm](https://github.com/thdxg/macterm). It is Macterm plus a set of features that upstream does not have, or does not have yet. It installs next to `Macterm.app`, and the two apps do not share state.

This file is for people and agents that work on the fork. Upstream's `AGENTS.md` still applies to the code. On an `off/*` branch, where the two files disagree, this file wins.

## Branches

| Branch | Content | Base |
|---|---|---|
| `off/base` | The fork identity and this `fork/` folder. | upstream `main` |
| `off/feat/<name>` | One feature: its code, tests and translations, and `fork/features/<name>.md`. | upstream `main`, **not** `off/base` |
| `off/main` | The app that you build and install: `off/base`, then a merge of each feature in the order of `fork/manifest`. | built again at each sync |
| `off/next/*` | The result of a sync, before you review it. | — |
| `feat/*`, `fix/*` | Upstream pull requests. They follow upstream's rules (squash, merge `main`, never rebase). | upstream `main` |

Rules:

- **`off/base` and each `off/feat/*` are rebased onto upstream `main`.** This is the opposite of upstream's rule for its PR branches. Never merge `main` into an `off/*` branch.
- **Never commit on `off/main`.** Each sync builds it again from `off/base` and the features, so a commit there is lost. Make the change on `off/base` or on the feature branch.
- **A feature branch is based on upstream `main`, not on `off/base`.** It must build and pass the tests without the fork identity. Then it can become an upstream PR with no change.
- **A feature keeps its code commits as upstream would take them. Its description is a separate commit.** When upstream merges the same patch, the rebase drops the code commit, and the sync retires the feature.
- A fix that an agent makes during a sync is a new commit on the feature branch. To fold it into the feature commit, squash the branch by hand. Then the next sync uses the squashed branch.
- Never add a `Co-Authored-By` trailer or any AI sign-off to a commit.
- Write fork text in the style of upstream (ASD-STE100, see upstream's `AGENTS.md`).

## Identity

| | Macterm | MactermOff |
|---|---|---|
| App | `/Applications/Macterm.app` | `/Applications/MactermOff.app` |
| Bundle ID | `com.thdxg.macterm` | `com.carlocaione.mactermoff` |
| Preferences, keychain items, privacy grants | follow the bundle ID | follow the bundle ID |
| App Support folder, control socket | `Macterm/` | `MactermOff/` |
| Config folder | `~/.config/macterm` | `~/.config/mactermoff` |
| zmx socket folder | `$TMPDIR/zmx-<uid>` | `$TMPDIR/zmx-off-<uid>` |
| Updates | Sparkle | none (see below) |

- **The zmx folder is the most important difference.** Macterm's orphan sweep kills every `macterm-*` session with no client that it did not create. In a shared folder, Macterm would kill the sessions of a MactermOff that is not running, and the reverse. `ZmxSocketBudget.socketDir` gives the fork its own folder. An explicit `ZMX_DIR` still wins, so do not set `ZMX_DIR` for both apps. The exception is a `ZMX_DIR` that names a Macterm folder: Macterm sets `ZMX_DIR` in each pane, and `open` gives an app the environment of the shell that runs it. The reverse is not covered: Macterm that `open` starts from a MactermOff pane uses the fork's folder. Start Macterm from the Dock, Finder or Spotlight.
- **The config folder is separate because both apps rewrite `pinned.yaml` and `widgets.yaml`.** To share the files that you edit by hand, link them: `ln -s ~/.config/macterm/projects ~/.config/mactermoff/projects` (the same for `extensions` and `config.ghostty`).
- **Sparkle is off.** A local build has the placeholder public key, and `Updater` then does not start. Never give a fork build `SPARKLE_ED_PUBLIC_KEY`: Sparkle would then replace MactermOff with upstream's release.
- **The Debug build keeps upstream's identity** ("Macterm Debug", `com.thdxg.macterm.debug`), so upstream's scripts and tests run with no change. It uses the fork's zmx and config folders, but its preferences and App Support folder are the same as upstream's Debug build. Do not use a Debug build as your daily app.
- `fork/identity.sh` lists each line of code that names Macterm's identity. `fork/identity-allowlist.txt` has the lines that we reviewed. The gate fails on a new line. When upstream adds one: change it for the fork, or add it to the list.
- Known gaps: the agent skills and `macterm tutor` still say `~/.config/macterm` and `/Applications/Macterm.app`. The app icon is the same as Macterm's. The Dock and the app switcher show the name "MactermOff".

## The sync

`fork/sync.sh sync` moves the fork to the newest upstream `main`. Nothing that you use changes until you run `promote`.

1. Fetch upstream. Save the fork's remote branch tips, for the lease of `promote`.
2. Rebase `off/base`, then each feature, onto upstream `main`, as `off/next/base` and `off/next/feat/<name>`. All of this happens in the sync worktree (`../macterm-off-sync.noindex`), not in your checkout. Spotlight does not index a folder whose name ends in `.noindex`, so the "Macterm Debug" app that the gate builds there does not show in Spotlight. The unit tests and the e2e tests still write upstream's Debug preferences (`com.thdxg.macterm.debug`) and `~/Library/Application Support/Macterm Debug`.
3. When a rebase stops on a conflict, an agent resolves it. It keeps upstream's change and applies the intent of the fork commit on top. The script stages the files and continues. Git's `rerere` replays a resolution that it saw before. After the rebase, the agent updates the feature's description, because the description is a later commit and is not there during the rebase.
4. A feature whose code is all upstream now (only its `fork/` file is left) is **retired**: it is not in the integration, and `promote` deletes its branch.
5. Each branch must pass the gate (`fork/gate.sh`): setup, identity (`off/base` only), format, lint, unit tests, strings. When a step fails, an agent fixes the branch, and the gate runs again (`--attempts`). A branch that still fails is left out, and the sync continues with the others.
6. A second agent (the reviewer) reads each feature that upstream touched, or that an agent changed. It answers KEEP, ADAPT or RETIRE, with evidence. It finds what the gate cannot find: upstream now does the same thing, or a convention changed.
7. `off/next/main` is built from `off/next/base` and a merge of each feature. It must pass the gate and the e2e tests of each feature (`e2e:` in the feature's description). The e2e tests start hermetic app windows and take the keyboard focus for some minutes.
8. The report goes to `.git/off-sync/reports/` (`latest.md`). It has the upstream commits, what each agent changed and why, `git range-diff` for each branch, the gate results and the review verdicts.

Then:

- `fork/sync.sh promote` pushes the ready `off/next/*` branches to the fork as `off/*`, with a lease: if the fork changed after the sync read it, the push fails and nothing moves. Then it makes a backup tag of each old tip (`off-backup/<time>/...`) and moves the local `off/*` branches.
- `fork/sync.sh abandon` deletes `off/next/*`. Your branches stay as they were.
- `fork/sync.sh status` shows the branches and the last report.

The agents: `--agent claude|codex` resolves and fixes (default `claude`). `--reviewer claude|codex|none` reviews (default `codex`). The agents never run git commands that change the repository, and never push. The script does all git operations. Each agent's answer is in the report.

## Feature descriptions

Each feature branch adds `fork/features/<name>.md`. It is the brief that the agents get at each sync, so write it for a reader who does not know the feature.

```markdown
---
upstream: thdxg/macterm#123    # the upstream PR, or "none"
e2e: scripts/e2e/test_x.py::test_y scripts/e2e/test_z.py
---
# Title

## What the user sees
## Why the fork has it
## What must stay true      (the invariants; the tests that pin them)
## Where it lives           (files, types, functions; upstream rules that it depends on)
## How to verify            (unit tests, e2e tests, manual steps)
## When to retire it        (the upstream change that makes it unnecessary)
## Adaptations              (one dated entry for each change that a sync made)
```

## Adding a feature

1. Make a branch from upstream `main`: `git switch -c off/feat/<name> origin/main`.
2. Commit the feature as upstream would take it. Follow upstream's `AGENTS.md`, with tests and translations.
3. Commit `fork/features/<name>.md` as a separate commit.
4. On `off/base`, add the name to `fork/manifest`. The order is the merge order.
5. Run `fork/sync.sh sync`, read the report, and run `fork/sync.sh promote`.

To offer the feature upstream, make a `feat/<name>` branch from `origin/main` with the code commits only, and open the PR from it. Add the PR to `upstream:`.
