<!-- page:
slug: sessions
title: Sessions
nav: Sessions
group: Projects & sessions
description: Tabs that belong to no project. New Tab opens one when the window shows no project.
-->

# Sessions

A session is a tab that belongs to no project and is not pinned. Use it for work that has no project: a quick ssh connection, a calculation, a man page. The sessions have their own section in the sidebar, below the [pinned tabs](/docs/pinned-tabs) and above the projects. The section shows only while a session exists.

## Opening a session

| Action | How |
| --- | --- |
| **New Tab with no project** | When the window shows no project, <kbd>⌘T</kbd> opens a session. |
| **New Session** | Select **File → New Session**, use the command palette, or right-click an empty area of the sidebar. This opens a session from any window. It has no keybind by default. Add one in Settings → Keymaps. |
| **New Tab in a session** | When a session is active, <kbd>⌘T</kbd> opens one more session. |

A new session starts in your home folder. With `tab-inherit-working-directory = true`, it starts in the folder of the active session.

## A session is an ordinary tab

- Splits, zoom and the other pane commands work as they do in a project.
- When Macterm quits, it keeps the sessions, as it keeps the tabs of a project. The next time that Macterm starts, it connects each session to its shell again.
- Closing a session ends its processes: **Close Tab**, <kbd>⌘W</kbd> on its last pane, or a shell that exits. When the last session closes, the window shows no project.
- The commands that need a project are not available: rename, unload and remove a project, the layouts, and Files.

## Moving tabs

| Move | How |
| --- | --- |
| A project tab into the sessions | Right-click the tab and select **Move to Sessions**. Or drag the tab into the sessions section. |
| A session into a project | Right-click the session and select **Move to Project**. Or drag the session into a project section. |
| A session into the pinned tabs | Right-click the session and select **Pin Tab**. Or drag the session above every project. |
| A pinned tab into the sessions | Right-click a pinned row that runs and select **Unpin to Sessions**. Or drag the row into the sessions section. |

A move keeps the shells. When you unpin a tab that you pinned from the sessions, it goes back into the sessions. When no project exists, **Unpin Tab** moves a pinned tab that runs into the sessions. On a pinned row that does not run, **Unpin Tab** removes the row, as it always does.

A tab of a remote project cannot move into the sessions, because its panes need the settings of their project. The tab stays where it is, and Macterm tells you.

## CLI

In the [CLI](/docs/cli), `--project sessions` selects the sessions:

```sh
macterm tab new --project sessions
macterm tab list --project sessions
```

When no project is active, `macterm tab new` also opens a session. The name `sessions` always means the sessions. Macterm refuses the name Sessions for a new project and for a rename, where you type it. A folder with the name Sessions gets the project name `Sessions 2`. A project that had the name before keeps it. Select that project by its UUID or by its index (`project:N`), or rename it.
