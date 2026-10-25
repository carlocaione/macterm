---
upstream: thdxg/macterm#654
e2e: scripts/e2e/test_projects.py::test_projects_without_folders_keep_tabs_layouts_and_sessions_after_restart
---
# Projects without a folder

## What the user sees

A project can exist without a folder. It is a named group of tabs, for work that is not one directory. The user creates one from the sidebar, Settings → Projects, the File menu, the command palette, or `macterm project create --name N [--select]`. Its first terminal starts in the home folder. New tabs and splits then follow the usual directory inheritance (`tab-inherit-working-directory`, `split-inherit-working-directory`). The project shows "No folder" where a project shows its path. Actions that need a folder are not available for it: Files (the palette screen), Copy Path, and the Worktrees menu (it stays empty). A relative path in an extension action resolves in the folder where its listing ran.

## Why the fork has it

The user groups terminal sessions by task, and many tasks have no single folder.

## What must stay true

- `Project.path` is optional. A project with `path == nil` has no folder. `Project.pathLabel` shows "No folder".
- **Storage stays readable by older builds.** `ProjectStore` writes projects with a folder to `projects.json` and projects without one to `projects_folderless.json` in the same folder (`ProjectStore.folderlessFileURL(beside:)`). An older build decodes `projects.json` and never sees a row without a path. A row without a path in `projects.json` moves on the next save. A project in both files loads once. A corrupt `projects_folderless.json` fails the load and keeps both files.
- **A failed project list keeps the workspace.** `restoreSelection(projects:projectListLoadFailed:)` with `WorkspaceStore.preserveForUnreadProjects()` keeps the snapshot and every session of projects that did not load. It never reaps them.
- **Layouts match by identity.** A layout file of a project without a folder has an `id:` (the project UUID) and no `path:` (`ProjectFileIdentity.id`; a file with a path is `.path`). The `id` is written before `tabs:`. An `id` that is not a UUID does not break a file with a path. `LayoutFileError.noFolderlessProjectFile` and `.noIdentity` name the errors. Folderless layouts match by ID across renames and do not overwrite each other.
- **Import keeps identity.** `ProjectStore.importFolderless(name:id:)` keeps the ID, refuses a collision and the pinned sentinel ID (`canImportFolderless`), and suffixes the reserved name `Pinned`.
- **Sessions are named after the project** (`Project.sessionSlug`), because there is no folder name.
- A project without a folder cannot take the current directory as its path, and never scans the home folder for Files.
- Tests: `ProjectStoreTests`, `ProjectFileStoreTests`, `ProjectFileTests`, `AppStateTests`, `ControlHandlerTests`, `LayoutReconcilerTests`, `CustomPaletteScopeTests`, `FilesPaletteScopeTests`, and the e2e test in the front matter (tabs, layouts and sessions survive a restart).
- `assets/project.schema.json` allows `id` without `path`. Keep it in step with `ProjectFile`.
- Known gap until upstream merges #654: the `$schema` line of a saved layout points to upstream's schema on `main`, which requires `path:`. An editor that validates against it flags a layout without a folder. The app reads the file correctly.
- Translations: every new string has `ko` and `zh-Hans`.

## Where it lives

`Macterm/Model/Project.swift`, `ProjectPath.swift`, `Workspace.swift`, `PinnedTabs.swift`; `Macterm/Persistence/ProjectStore.swift`, `ProjectFile.swift`, `ProjectFileStore.swift`, `LayoutFile.swift`, `LayoutBuilder.swift`, `LayoutReconciler.swift`, `WorkspacePersistence.swift`; `Macterm/Control/ControlHandler.swift`, `ControlProtocol.swift`; `Macterm/Views/NewFolderlessProjectSheet.swift`, `Sidebar.swift`, `MainWindow.swift`; `Macterm/Settings/ProjectsSettings.swift`; `Macterm/Palette/ProjectSource.swift`, `Scopes/CustomPaletteScope.swift`, `Scopes/FilesPaletteScope.swift`; `Macterm/Intents/Entities.swift`; `Macterm/Localizable.xcstrings`; `assets/project.schema.json`; `website/docs/pages/50-declarative-layouts.md`, `80-cli.md`. It depends on upstream's persistence rules ("A directory is not an identity", layout matching by `path:`) and on the `Pinned` name rule.

In MactermOff, the two project files are in the `MactermOff` App Support folder, and layouts are in `~/.config/mactermoff/projects/`.

## How to verify

- Unit tests: the suites above.
- e2e: the test in the front matter.
- By hand: create a project without a folder (File menu or `macterm project create --name Notes --select`). Open tabs and a split, quit, start again: the tabs and sessions come back. Save its layout, rename the project, apply the layout: it still matches.

## When to retire it

When upstream merges #654, or when upstream lets a project exist without a folder in another way. If upstream adds it with another storage format, the fork must migrate `projects_folderless.json` and `id:` layouts before it drops this feature.

## Adaptations

- 2026-10-25, upstream cc7faea: the e2e test finds the saved layouts with a glob over `.config/*/projects/` in its throwaway home, not in `.config/macterm/projects`, so that it passes in Macterm and in MactermOff, whose config folder is `~/.config/mactermoff` (`505c8cb`, by the sync's fix agent). The app did not change. A codex review found the `$schema` gap above; it was there before the sync.
- 2026-10-25, by hand: the comment of that test now has the text of PR #654 (`aeddbeb`), which got the same change. The fork and the PR have the same code again, so that the sync can retire the feature when upstream merges the PR.
