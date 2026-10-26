---
upstream: none
e2e: scripts/e2e/test_sessions.py
---
# Sessions: tabs without a project

## What the user sees

A session is a tab that belongs to no project and is not pinned. The sessions have a sidebar section of their own, with the header "Sessions", below the pinned tabs and above the projects. The section shows only while a session exists.

- ⌘T (New Tab) in a window that shows no project opens a session there. Before, it did nothing.
- New Session (File menu, command palette, the menu of an empty sidebar area; no default keybind) opens a session from any window.
- A new session starts in the home folder, and then follows `tab-inherit-working-directory`.
- A session is an ordinary tab. Closing it (Close Tab, ⌘W on its last pane, a shell that exits) ends its processes. When the last session closes, the window shows no project again ("No project selected", which now lists ⌘T as "New session").
- Quitting keeps the sessions, as it keeps project tabs. The next start reattaches them.
- Tabs move in and out: drag, Move to Sessions (a project tab's menu), Unpin to Sessions (the menu of a pinned row that runs), Pin Tab and Move to Project (a session's menu). Unpin goes back to the sessions for a tab that was pinned from them. A move shows the moved tab.
- A tab of a remote project cannot move into the sessions. Macterm says so in a toast.
- The CLI: `--project sessions` addresses the section. `macterm tab new` with no active project opens a session. "Sessions" is a reserved project name, as "Pinned" is.

## Why the fork has it

The user wants terminals that are not tied to a project: work that has no folder and no project, without a pin that keeps it for ever.

## What must stay true

- **The sessions are a sentinel workspace**, `workspaces[SessionTabs.projectID]` (`Macterm/Model/SessionTabs.swift`, fixed UUID `5E551045-0000-4000-8000-4D6163536573`). It is NOT a `ProjectStore` row, so every loop over projects skips it. `SessionTabs.project` is its synthetic `Project` (home folder) for the call sites that route by a `Project`.
- **A session is an ordinary tab, not a record.** The pinned workspace's special cases are written as `!= PinnedTabs.projectID`, so they treat the sessions as a project: per-window tab selection, mirrors, reorder, close. Do not add the sessions to those checks.
- **The workspace starts empty**: `ensureSessionWorkspace`, also the branch in `AppState.ensureWorkspace`. A project's `Workspace(projectID:projectPath:)` makes a default tab; the sessions must not get one.
- **New Tab with no project opens a session** (`AppCommand.newTab` in `AppCommandActions.swift`), and `.newSession` always does, and so does the CLI's `tab new` with no project. All call `AppState.createSession`. It selects the workspace in the key window FIRST and then creates the tab, so that `workspaceActiveTabDidChange` records the new tab in the key window and not in a background window that shows another session. Selecting an empty workspace makes no save, so the windows do not leave it before the tab is there.
- **The windows leave an empty sessions workspace**: `AppState.leaveEmptySessions` is the first call of `saveWorkspaces`. Every path that removes the last session ends there (close, a shell that exits, move, merge, pin).
- **Restore**: `restoreSelection` adds `SessionTabs.projectID` to the valid workspace IDs, and selects the sessions at launch when they were active and a session exists.
- **zmx names**: the panes of a new session use the slug `ZmxSessionName.sessionTabSlug` (`session`). A tab that moves in keeps the session names of its panes: `Pane.rebind` changes only the routing identity. It is set in the low-level `createTab(projectID:projectPath:sessionSlug:…)`, not in the `createTab(projectID:projects:workingDirectory:…)` that projects-without-folders changes, so that the two features do not conflict.
- **Unpin** goes through `AppState.unpinDestination`: the origin project, or the sessions if the tab was pinned from them, else the first project, else the sessions for a local tab. A remote tab with no project gets nil, and upstream's toast "Cannot unpin".
- **A move lands on the moved tab** (`AppState.landOnTab` in `moveTab`, `separatePane` and `unpinUnloadedRecord`; `createSession` selects its tab after the switch). `alignKeyWindowTab` prefers the tab that the key window remembers for a workspace, so a window that showed the destination before showed its old tab. This fixes the same for moves between projects.
- **A remote pane never enters the sessions** (`AppState.canMoveIntoSessions`): `moveTab`, `separatePane`, `mergeTab` and `unpinUnloadedRecord` refuse with the toast `SessionTabs.remoteTabRefusal`, and the sidebar does not offer Move to Sessions or Unpin to Sessions for one. The reason: a remote pane takes its zmx path from its project (`stampRemoteZmxPath`), a relaunch does not keep it, and selecting the sessions would stamp nil over it.
- **App Intents**: `MactermProjectQuery` offers the sessions (under `SessionTabs.sectionTitle`) only while one exists, but `entities(for:)` resolves the id at any time. New Tab there calls `ensureSessionWorkspace`; Focus Project throws `notFound` while it is empty.
- **Reserved name**: `ReservedProjectName` (in `SessionTabs.swift`) is the one test of every naming path. It covers "Pinned" and "Sessions". `ProjectStore.create` suffixes a folder name ("sessions 2"); `ProjectStore.rename`, the sidebar rename, the remote sheet, the New Project intent and the CLI refuse a typed one.
- **CLI** (`ControlHandler.swift`): `resolveProject` reads `sessions` (any case) and the UUID before any project. `resolveWorkspace` creates the empty workspace on request. `tab new` with no active project and no selector opens a session and shows it unless `--no-focus`. `project select sessions` needs a session. `project rename`, `project remove` and the layout verbs (`rejectWorkspaceWithoutLayout`) refuse it. `status` names the sessions as the active project.
- The GUI title is `SessionTabs.sectionTitle` (localized). `SessionTabs.displayName` ("Sessions") is the CLI selector and the reserved name, and stays English.
- Translations: every new string has `ko` and `zh-Hans` (세션 / 会话, as `TRANSLATING.md` says).
- Tests: `MactermTests/App/SessionTabsTests.swift`, `MactermTests/Control/ControlHandlerSessionTests.swift`, the changed cases in `DockMenuTests` and `MactermIntentsTests` (New Tab now applies with no project, so they use Close Tab as the command that does not apply), and `scripts/e2e/test_sessions.py`.

## Where it lives

- Model: `Macterm/Model/SessionTabs.swift` (`SessionTabs`, `ReservedProjectName`).
- State: `Macterm/App/AppState+SessionTabs.swift` (`sessionWorkspace`, `hasSessions`, `ensureSessionWorkspace`, `createSession`, `unpinDestination`); `AppState.swift` (`leaveEmptySessions`, restore, `ensureWorkspace`, `configuredProjectDirectory`, the slug in `createTab`, `selectGlobalTab`, `stepProject`, the unload and remove guards); `AppState+PinnedTabs.swift` (both unpin paths).
- Commands: `AppCommand.newSession`, `HotkeyAction.newSession` (`new_session`, default `none`), `MactermKeybind.newSession`; `AppCommandActions.swift`; the File menu in `MactermApp.swift`; `DockMenu.preparation`.
- UI: `Sidebar.swift` (`sessionsSection`, `tabOwner`, the menu items), `MainWindow.swift` (the synthetic project, the title, the "New session" hint), `WindowState.expandActiveProject`.
- CLI: `ControlHandler.swift`. App Intents: `IntentHost.swift`, `Entities.swift`, `ProjectIntents.swift`.
- Palette `run:` actions in a session: `CustomPaletteScope.swift` (no project name or folder in the environment).
- Docs: `website/docs/pages/56-sessions.md`, and the CLI, pinned tabs and Shortcuts pages; the Sessions section of `AGENTS.md`.
- It depends on upstream's pinned-tab design (`PinnedTabs`, the sentinel workspace) and on `saveWorkspaces` being the end of every structural change.

## How to verify

- Unit tests: `SessionTabsTests`, `ControlHandlerSessionTests`, `DockMenuTests`, `MactermIntentsTests` (the sessions intents), `PinnedTabsTests`.
- e2e: `scripts/e2e/test_sessions.py` (a session runs a shell in the home folder under the `session` slug; `tab new` in a window with no project opens a session).
- By hand: remove or unload the project that a window shows, press ⌘T: a "Sessions" section appears with one tab. ⌘T again: a second session. Right-click a project tab → Move to Sessions. Pin a session, then Unpin Tab: it goes back to Sessions. Close every session: the window shows "No project selected". Quit and start again with sessions open: they come back with their shells.

## When to retire it

When upstream has tabs that belong to no project and opens one from New Tab with no project. If upstream takes this patch as a PR, the sync drops the code commit.

## Adaptations
