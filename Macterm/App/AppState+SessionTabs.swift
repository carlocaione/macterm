import Foundation
import os

private let logger = Logger(subsystem: appBundleID, category: "SessionTabs")

/// Sessions: tabs that belong to no project and are not pinned, in a special
/// workspace keyed by the fixed `SessionTabs.projectID` sentinel —
/// deliberately NOT a `ProjectStore` row.
///
/// The rules, in one place:
/// - New Tab in a window that shows no project opens a session there
///   (`AppCommand.newTab`); New Session opens one from anywhere. Both end in
///   `createSession`.
/// - Everywhere else the workspace behaves as a project's: one tab
///   selection for each window, mirrors, reorder, close (which ends the
///   shells), the snapshot and the reattach at launch. The pinned
///   workspace's special cases (`!= PinnedTabs.projectID`) leave it alone.
/// - It starts empty (`ensureSessionWorkspace`), and the windows leave it
///   when its last tab goes (`AppState.leaveEmptySessions`, called from every
///   `saveWorkspaces`). The sidebar draws its section only while a session
///   exists.
/// - Moves are the ordinary `moveTab` in both directions, and Pin and Unpin
///   work as for a project: a tab pinned from the sessions unpins back to
///   them (`unpinDestination`). A move lands on the moved tab (`landOnTab`).
/// - A remote pane never enters the sessions (`canMoveIntoSessions`): a
///   move, a separated pane, a merge or an unpin with one refuses.
extension AppState {
    // MARK: - Queries

    var sessionWorkspace: Workspace? { workspaces[SessionTabs.projectID] }

    /// Whether the sessions section has a tab to show.
    var hasSessions: Bool { !(sessionWorkspace?.tabs.isEmpty ?? true) }

    func ensureSessionWorkspace() {
        if workspaces[SessionTabs.projectID] == nil {
            // Empty on purpose — `Workspace(projectID:projectPath:)` would
            // spawn an initial tab that nobody asked for.
            workspaces[SessionTabs.projectID] = Workspace(
                projectID: SessionTabs.projectID, tabs: [], activeTabID: nil
            )
        }
    }

    // MARK: - Creation

    /// Open a new session and show it in the key window. Its directory
    /// follows `tab-inherit-working-directory` from the focused session, as
    /// New Tab does in a project, and is the home folder for the first one.
    /// `command` is typed into its shell when the shell starts (the CLI's
    /// `--run`).
    @discardableResult
    func createSession(projects: [Project], command: String? = nil) -> UUID? {
        ensureSessionWorkspace()
        // The key window enters the sessions before the tab exists. A new
        // active tab is recorded in a window that shows the workspace
        // (`workspaceActiveTabDidChange`): it must be the key window, not a
        // background window that shows another session. The selection makes
        // no save, so an empty workspace is not left again before the tab is
        // there.
        selectProject(SessionTabs.project)
        guard let tabID = createTab(projectID: SessionTabs.projectID, projects: projects, command: command) else {
            return nil
        }
        logger.info("createSession: \(tabID, privacy: .public)")
        // The new tab is the one on screen, also when the key window
        // remembered an older session (`landOnTab`).
        landOnTab(tabID, in: SessionTabs.projectID)
        return tabID
    }

    // MARK: - Pin / Unpin

    /// Where Unpin moves a pinned tab: back to the place it was pinned from —
    /// a project or the sessions — and else the first project. With no
    /// project at all, a local tab goes to the sessions, which need none. A
    /// remote tab has no place then (`canMoveIntoSessions`): nil.
    func unpinDestination(for record: PinnedTabRecord, isRemote: Bool, projects: [Project]) -> Project? {
        // A tab pinned from the sessions can have a remote pane merged into
        // it since; then it goes to a project like any remote tab.
        if record.originProjectID == SessionTabs.projectID, !isRemote { return SessionTabs.project }
        if let project = projects.first(where: { $0.id == record.originProjectID }) ?? projects.first {
            return project
        }
        return isRemote ? nil : SessionTabs.project
    }

    // MARK: - Remote panes

    /// Whether these panes may move into the sessions. A remote pane may not:
    /// it takes its zmx path from its project at each selection
    /// (`stampRemoteZmxPath`), a relaunch does not keep that path, and the
    /// sessions have no host to give it. Its tab stays where it is.
    func canMoveIntoSessions(_ panes: [Pane]) -> Bool {
        !panes.contains(where: \.isRemote)
    }

    /// Say why a move into the sessions did nothing: a drop that does
    /// nothing in silence looks broken.
    func refuseRemoteMoveIntoSessions() {
        logger.info("a remote tab stays out of the sessions")
        presentToast(SessionTabs.remoteTabRefusal)
    }
}
