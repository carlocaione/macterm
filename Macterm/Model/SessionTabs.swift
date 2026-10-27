import Foundation

/// The sessions sentinel: a workspace for tabs that belong to no project and
/// are not pinned. New Tab opens a tab here when the window shows no project,
/// and New Session opens one from anywhere.
///
/// Like `PinnedTabs`, the workspace is keyed by a fixed UUID that is NOT a
/// `ProjectStore` row, so everything that iterates real projects (Settings →
/// Projects, the palette's project source, CLI `project list`, layout save
/// and apply) never sees it. Unlike a pinned tab, a session has no
/// declaration: it is an ordinary tab. Closing it ends its shells, the
/// workspace snapshot carries it across a relaunch, and the windows leave the
/// workspace when its last tab goes (`AppState.leaveEmptySessions`). Every
/// path that the pinned workspace special-cases with `!= PinnedTabs.projectID`
/// therefore treats sessions as a project: one tab selection for each window,
/// mirrors, reorder and close.
enum SessionTabs {
    /// Fixed across launches and machines — the workspace snapshot and the
    /// panes' routing identity both key on it. Spelled as raw bytes for the
    /// linter, like `PinnedTabs.projectID`; this is
    /// `5E551045-0000-4000-8000-4D6163536573`.
    static let projectID = UUID(uuid: (
        0x5E, 0x55, 0x10, 0x45, 0x00, 0x00, 0x40, 0x00,
        0x80, 0x00, 0x4D, 0x61, 0x63, 0x53, 0x65, 0x73
    ))

    /// The name that the CLI reads as this workspace (`--project sessions`),
    /// which no project may carry. It stays as it is in every language, as
    /// `PinnedTabs.displayName` does. What the GUI shows is `sectionTitle`.
    static let displayName = "Sessions"

    /// The section's name in the GUI, in the app's language: the sidebar
    /// header, the window title, the quit prompt.
    static var sectionTitle: String {
        String(localized: "Sessions", comment: "The sidebar section of the tabs without a project")
    }

    /// Whether `name` is this workspace's, with the rules of
    /// `PinnedTabs.reservesName`: case-insensitive, blind to surrounding
    /// whitespace. Every naming path applies it through `ReservedProjectName`.
    static func reservesName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == displayName.lowercased()
    }

    /// Why a typed name was refused, as the app says it. The CLI words its
    /// `bad_request` the same (`ControlHandler.reservedNameError(for:)`).
    static let reservedNameMessage = String(
        localized: "“\(displayName)” is a reserved name for the tabs without a project. Select another name."
    )

    /// Why a remote tab did not move into the sessions (`AppState.canMoveIntoSessions`).
    static let remoteTabRefusal = String(localized: "A remote tab cannot move into the sessions")

    /// Where a new session starts when nothing gives it a directory: the
    /// user's home. `$HOME`-env-first, so the benchmark harness's throwaway
    /// home isolates it.
    static var fallbackRoot: String { ProjectPath.currentHome }

    /// Synthetic `Project` value for the call sites that render or route by a
    /// `Project` (MainWindow, the sidebar's rows, `selectProject`, the CLI's
    /// project resolution). Never inserted into `ProjectStore`.
    static var project: Project {
        Project(id: projectID, name: displayName, path: fallbackRoot)
    }
}

/// The names of the workspaces that are not projects, which no project may
/// carry: `ControlHandler.resolveProject` reads each one as its workspace
/// before it looks at any project. The one test that every naming path
/// applies — a typed name is refused where it was typed, and a name that
/// nobody chose is suffixed (`ProjectStore.create`).
enum ReservedProjectName {
    static func isReserved(_ name: String) -> Bool {
        PinnedTabs.reservesName(name) || SessionTabs.reservesName(name)
    }

    /// Why `name` was refused. Only meaningful when `isReserved(name)`.
    static func message(for name: String) -> String {
        SessionTabs.reservesName(name) ? SessionTabs.reservedNameMessage : PinnedTabs.reservedNameMessage
    }
}
