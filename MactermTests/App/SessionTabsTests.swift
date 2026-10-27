import Foundation
@testable import Macterm
import Testing

/// Sessions: tabs without a project. New Tab with no project and New Session
/// open one, the windows leave the workspace when its last tab goes, the
/// snapshot carries it across a relaunch, and tabs move in and out of it the
/// same way they move between projects and the pinned workspace.
@MainActor
struct SessionTabsTests {
    // MARK: - Setup helpers

    private struct Fixture {
        let state: AppState
        let store: ProjectStore
        let storeURL: URL
        let projectsDir: URL

        var ctx: AppCommandContext { AppCommandContext(appState: state, projectStore: store) }
    }

    /// AppState with temp-file stores and a no-op zmx (a test must never fork
    /// the real zmx or reap the developer's live sessions), and no surfaces
    /// warmed (that would spawn real shells).
    private func makeFixture() -> Fixture {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macterm-tests-\(UUID().uuidString).json")
        let projectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macterm-tests-projects-\(UUID().uuidString)", isDirectory: true)
        let state = AppState(
            workspaceStore: WorkspaceStore(fileURL: storeURL),
            projectFiles: ProjectFileStore(directoryURL: projectsDir)
        )
        state.zmx = .noop
        state.incubatePane = { _ in }
        let store = ProjectStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("macterm-tests-sessions-\(UUID().uuidString).json"))
        return Fixture(state: state, store: store, storeURL: storeURL, projectsDir: projectsDir)
    }

    /// A key window that shows no project, as after the last project closed.
    private func keyWindow(_ state: AppState) -> WindowState {
        let window = WindowState()
        state.registerWindow(window)
        state.noteKeyWindow(window)
        return window
    }

    private func seedProject(_ fx: Fixture, name: String = "proj", path: String = "/tmp") -> Project {
        let project = Project(name: name, path: path, sortOrder: fx.store.projects.count)
        fx.store.add(project)
        fx.state.selectProject(project)
        return project
    }

    /// A remote project, selected. Its panes are remote; the no-op zmx keeps
    /// every ssh and zmx call away from a real host.
    private func seedRemoteProject(_ fx: Fixture) -> Project {
        let project = Project(name: "box", path: "me@host:/srv/app", sortOrder: fx.store.projects.count)
        fx.store.add(project)
        fx.state.selectProject(project)
        return project
    }

    private func run(_ command: AppCommand, _ fx: Fixture) throws {
        let action = try #require(command.action(in: fx.ctx))
        action()
    }

    private var sessionsID: UUID { SessionTabs.projectID }

    // MARK: - Opening a session

    @Test
    func new_tab_in_a_window_that_shows_no_project_opens_a_session_there() throws {
        let fx = makeFixture()
        let window = keyWindow(fx.state)
        #expect(window.activeProjectID == nil)

        try run(.newTab, fx)

        let sessions = try #require(fx.state.sessionWorkspace)
        let tab = try #require(sessions.tabs.first)
        let pane = try #require(tab.splitRoot.allPanes().first)
        #expect(sessions.tabs.count == 1)
        #expect(window.activeProjectID == sessionsID)
        #expect(fx.state.activeProjectID == sessionsID)
        #expect(fx.state.viewTab(for: sessionsID, in: window)?.tab.id == tab.id)
        // A session starts in the home folder, and its zmx session groups
        // under one slug, not under the name of that folder.
        #expect(pane.projectPath == SessionTabs.fallbackRoot)
        #expect(pane.sessionName.hasPrefix(ZmxSessionName.prefix + ZmxSessionName.sessionTabSlug + "-"))
    }

    @Test
    func new_tab_in_the_sessions_opens_another_session() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        try run(.newTab, fx)

        try run(.newTab, fx)

        #expect(fx.state.sessionWorkspace?.tabs.count == 2)
        #expect(fx.state.activeProjectID == sessionsID)
    }

    @Test
    func new_session_opens_one_beside_a_project_and_shows_it() throws {
        let fx = makeFixture()
        let window = keyWindow(fx.state)
        let project = seedProject(fx)
        let projectTabs = try #require(fx.state.workspaces[project.id]?.tabs.map(\.id))

        try run(.newSession, fx)

        #expect(fx.state.sessionWorkspace?.tabs.count == 1)
        #expect(window.activeProjectID == sessionsID)
        // The project keeps its tabs, and New Tab there still makes one there.
        #expect(fx.state.workspaces[project.id]?.tabs.map(\.id) == projectTabs)
        fx.state.selectProject(project)
        try run(.newTab, fx)
        #expect(fx.state.workspaces[project.id]?.tabs.count == projectTabs.count + 1)
        #expect(fx.state.sessionWorkspace?.tabs.count == 1)
    }

    @Test
    func the_sessions_workspace_starts_empty() {
        let fx = makeFixture()

        // A project gets a default tab on its first selection; the sessions
        // open on request only.
        fx.state.ensureSessionWorkspace()

        #expect(fx.state.sessionWorkspace?.tabs.isEmpty == true)
        #expect(!fx.state.hasSessions)
    }

    // MARK: - Landing on the new tab

    /// The window remembers the session that it showed last. A new one must
    /// still be the one that it shows.
    @Test
    func new_session_shows_the_new_session_in_a_window_that_showed_an_older_one() throws {
        let fx = makeFixture()
        let window = keyWindow(fx.state)
        let project = seedProject(fx)
        try run(.newSession, fx)
        let older = try #require(fx.state.sessionWorkspace?.activeTab)
        fx.state.selectProject(project)

        try run(.newSession, fx)

        let newer = try #require(fx.state.sessionWorkspace?.tabs.last)
        #expect(newer.id != older.id)
        #expect(fx.state.viewTab(for: sessionsID, in: window)?.tab.id == newer.id)
    }

    /// Each window keeps its own selection (#345): a session opened in the
    /// key window does not move a background window that shows another one.
    @Test
    func new_session_does_not_move_another_window_that_shows_the_sessions() throws {
        let fx = makeFixture()
        let background = WindowState()
        fx.state.registerWindow(background)
        let key = keyWindow(fx.state)
        let project = seedProject(fx)
        try run(.newSession, fx)
        let shown = try #require(fx.state.sessionWorkspace?.activeTab)
        fx.state.selectProject(SessionTabs.project, in: background)
        fx.state.selectProject(project)
        #expect(fx.state.selectedTab(for: sessionsID, in: background)?.id == shown.id)

        try run(.newSession, fx)

        let newer = try #require(fx.state.sessionWorkspace?.tabs.last)
        #expect(fx.state.selectedTab(for: sessionsID, in: key)?.id == newer.id)
        #expect(fx.state.selectedTab(for: sessionsID, in: background)?.id == shown.id)
    }

    @Test
    func a_tab_moved_into_the_sessions_is_the_one_that_the_window_shows() throws {
        let fx = makeFixture()
        let window = keyWindow(fx.state)
        let project = seedProject(fx)
        try run(.newSession, fx)
        fx.state.selectProject(project)
        let tab = try #require(fx.state.workspaces[project.id]?.activeTab)

        fx.state.moveTab(tab.id, from: project.id, to: sessionsID, destPath: SessionTabs.fallbackRoot)

        #expect(fx.state.viewTab(for: sessionsID, in: window)?.tab.id == tab.id)
    }

    @Test
    func a_pane_separated_into_the_sessions_is_the_one_that_the_window_shows() throws {
        let fx = makeFixture()
        let window = keyWindow(fx.state)
        let project = seedProject(fx)
        try run(.newSession, fx)
        fx.state.selectProject(project)
        let tab = try #require(fx.state.workspaces[project.id]?.activeTab)
        let first = try #require(tab.splitRoot.allPanes().first)
        _ = fx.state.splitPane(first.id, direction: .horizontal, projectID: project.id)
        let second = try #require(tab.splitRoot.allPanes().last)

        fx.state.separatePane(second.id, toProject: sessionsID, destPath: SessionTabs.fallbackRoot, at: nil)

        #expect(fx.state.viewTab(for: sessionsID, in: window)?.tab.splitRoot.allPanes().first === second)
    }

    // MARK: - Leaving an empty sessions workspace

    @Test
    func closing_the_last_session_leaves_the_window_on_no_project() throws {
        let fx = makeFixture()
        let window = keyWindow(fx.state)
        try run(.newTab, fx)
        let tab = try #require(fx.state.sessionWorkspace?.tabs.first)

        fx.state.closeTab(tab.id, projectID: sessionsID)

        #expect(!fx.state.hasSessions)
        #expect(window.activeProjectID == nil)
        #expect(fx.state.activeProjectID == nil)
        // New Tab still applies there, and opens the next session.
        try run(.newTab, fx)
        #expect(fx.state.sessionWorkspace?.tabs.count == 1)
        #expect(window.activeProjectID == sessionsID)
    }

    @Test
    func a_shell_that_exits_in_the_last_session_leaves_the_window_on_no_project() throws {
        let fx = makeFixture()
        let window = keyWindow(fx.state)
        try run(.newTab, fx)
        let pane = try #require(fx.state.sessionWorkspace?.tabs.first?.splitRoot.allPanes().first)

        // ⌃D: the shell ends, and libghostty reports the exit of the pane.
        fx.state.paneProcessExited(pane.id, projectID: sessionsID)

        #expect(!fx.state.hasSessions)
        #expect(window.activeProjectID == nil)
    }

    @Test
    func closing_one_of_two_sessions_stays_in_the_sessions() throws {
        let fx = makeFixture()
        let window = keyWindow(fx.state)
        try run(.newTab, fx)
        try run(.newTab, fx)
        let first = try #require(fx.state.sessionWorkspace?.tabs.first)

        fx.state.closeTab(first.id, projectID: sessionsID)

        #expect(fx.state.sessionWorkspace?.tabs.count == 1)
        #expect(window.activeProjectID == sessionsID)
    }

    @Test
    func a_background_window_leaves_the_sessions_with_the_key_window() throws {
        let fx = makeFixture()
        let background = WindowState()
        fx.state.registerWindow(background)
        let key = keyWindow(fx.state)
        try run(.newTab, fx)
        fx.state.selectProject(SessionTabs.project, in: background)
        let tab = try #require(fx.state.sessionWorkspace?.tabs.first)

        fx.state.closeTab(tab.id, projectID: sessionsID)

        #expect(key.activeProjectID == nil)
        #expect(background.activeProjectID == nil)
    }

    // MARK: - Relaunch

    @Test
    func sessions_survive_a_relaunch_with_their_zmx_sessions() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        try run(.newTab, fx)
        try run(.newTab, fx)
        let names = (fx.state.sessionWorkspace?.tabs ?? []).flatMap { $0.splitRoot.allPanes() }.map(\.sessionName)
        fx.state.saveWorkspaces()

        let state2 = AppState(
            workspaceStore: WorkspaceStore(fileURL: fx.storeURL),
            projectFiles: ProjectFileStore(directoryURL: fx.projectsDir)
        )
        state2.zmx = .noop
        state2.incubatePane = { _ in }
        // No project at all: the sessions need none to restore.
        state2.restoreSelection(projects: [])

        let restored = (state2.sessionWorkspace?.tabs ?? []).flatMap { $0.splitRoot.allPanes() }.map(\.sessionName)
        #expect(restored == names)
        #expect(names.count == 2)
    }

    // MARK: - Moves, pin and unpin

    @Test
    func a_tab_moves_into_the_sessions_and_back_with_its_panes() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let project = seedProject(fx)
        let tab = try #require(fx.state.workspaces[project.id]?.activeTab)
        let pane = try #require(tab.splitRoot.allPanes().first)

        fx.state.moveTab(tab.id, from: project.id, to: sessionsID, destPath: SessionTabs.fallbackRoot)

        #expect(fx.state.sessionWorkspace?.tabs.map(\.id) == [tab.id])
        #expect(fx.state.sessionWorkspace?.tabs.first?.splitRoot.allPanes().first === pane)
        #expect(pane.projectID == sessionsID)
        #expect(fx.state.activeProjectID == sessionsID)

        // The folder of `seedProject`. (`Project.path` is optional where
        // projects can have no folder, so the test names it.)
        fx.state.moveTab(tab.id, from: sessionsID, to: project.id, destPath: "/tmp")

        #expect(fx.state.workspaces[project.id]?.tabs.contains { $0.id == tab.id } == true)
        #expect(pane.projectID == project.id)
        #expect(!fx.state.hasSessions)
        #expect(fx.state.activeProjectID == project.id)
    }

    @Test
    func a_pane_separated_into_the_sessions_becomes_a_session() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let project = seedProject(fx)
        let tab = try #require(fx.state.workspaces[project.id]?.activeTab)
        let first = try #require(tab.splitRoot.allPanes().first)
        _ = fx.state.splitPane(first.id, direction: .horizontal, projectID: project.id)
        let second = try #require(tab.splitRoot.allPanes().last)

        fx.state.separatePane(second.id, toProject: sessionsID, destPath: SessionTabs.fallbackRoot, at: nil)

        #expect(fx.state.sessionWorkspace?.tabs.first?.splitRoot.allPanes().first === second)
        #expect(tab.splitRoot.allPanes().map(\.id) == [first.id])
    }

    @Test
    func a_tab_pinned_from_the_sessions_unpins_back_to_them() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let project = seedProject(fx)
        try run(.newSession, fx)
        let tab = try #require(fx.state.sessionWorkspace?.tabs.first)

        fx.state.pinTab(tab.id, fromProject: sessionsID)

        #expect(fx.state.pinnedRecords.first?.originProjectID == sessionsID)
        #expect(!fx.state.hasSessions)

        fx.state.unpinTab(tab.id, projects: [project])

        #expect(fx.state.sessionWorkspace?.tabs.map(\.id) == [tab.id])
        #expect(fx.state.pinnedRecords.isEmpty)
        #expect(fx.state.activeProjectID == sessionsID)
    }

    @Test
    func unpinning_with_no_project_moves_the_tab_into_the_sessions() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let project = seedProject(fx)
        let tab = try #require(fx.state.workspaces[project.id]?.activeTab)
        fx.state.pinTab(tab.id, fromProject: project.id)

        // The origin project is gone: there is no project to go back to, and
        // the tab still needs a place that keeps its shells.
        fx.state.unpinTab(tab.id, projects: [])

        #expect(fx.state.sessionWorkspace?.tabs.map(\.id) == [tab.id])
        #expect(fx.state.pinnedRecords.isEmpty)
    }

    // MARK: - Remote tabs stay in their project

    /// A remote pane takes its zmx path from its project, and a relaunch does
    /// not keep it: in the sessions it would lose it. Every way in refuses.
    @Test
    func a_remote_tab_does_not_move_into_the_sessions() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let project = seedRemoteProject(fx)
        let tab = try #require(fx.state.workspaces[project.id]?.activeTab)
        #expect(tab.splitRoot.allPanes().first?.isRemote == true)

        fx.state.moveTab(tab.id, from: project.id, to: sessionsID, destPath: SessionTabs.fallbackRoot)

        #expect(fx.state.workspaces[project.id]?.tabs.map(\.id) == [tab.id])
        #expect(!fx.state.hasSessions)
        #expect(fx.state.activeProjectID == project.id)
        #expect(fx.state.activeToast?.title == SessionTabs.remoteTabRefusal)
    }

    @Test
    func a_remote_pane_does_not_separate_into_the_sessions() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let project = seedRemoteProject(fx)
        let tab = try #require(fx.state.workspaces[project.id]?.activeTab)
        let first = try #require(tab.splitRoot.allPanes().first)
        _ = fx.state.splitPane(first.id, direction: .horizontal, projectID: project.id)
        let second = try #require(tab.splitRoot.allPanes().last)

        fx.state.separatePane(second.id, toProject: sessionsID, destPath: SessionTabs.fallbackRoot, at: nil)

        #expect(tab.splitRoot.allPanes().count == 2)
        #expect(!fx.state.hasSessions)
    }

    @Test
    func a_remote_tab_does_not_merge_into_a_session() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let project = seedRemoteProject(fx)
        let remoteTab = try #require(fx.state.workspaces[project.id]?.activeTab)
        try run(.newSession, fx)
        let session = try #require(fx.state.sessionWorkspace?.activeTab)

        fx.state.mergeTab(remoteTab.id, from: project.id, at: .rootEdge(.right), inProject: sessionsID)

        #expect(session.splitRoot.allPanes().count == 1)
        #expect(fx.state.workspaces[project.id]?.tabs.map(\.id) == [remoteTab.id])
    }

    @Test
    func a_remote_tab_with_no_project_to_go_back_to_stays_pinned() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let project = seedRemoteProject(fx)
        let tab = try #require(fx.state.workspaces[project.id]?.activeTab)
        fx.state.pinTab(tab.id, fromProject: project.id)

        fx.state.unpinTab(tab.id, projects: [])

        #expect(fx.state.pinnedRecords.map(\.id) == [tab.id])
        #expect(!fx.state.hasSessions)
    }

    /// A pinned tab from the sessions that a remote tab was merged into: its
    /// unpin (also the one that an edit of `pinned.yaml` makes at launch)
    /// goes to a project, or nowhere.
    @Test
    func a_remote_tab_pinned_from_the_sessions_does_not_unpin_into_them() {
        let fx = makeFixture()
        let record = PinnedTabRecord(
            id: UUID(),
            declaration: LayoutTab(name: nil, layout: .pane(LayoutPane(cwd: "me@host:/srv/app"))),
            originProjectID: sessionsID
        )
        let project = Project(name: "proj", path: "/tmp", sortOrder: 0)

        #expect(fx.state.unpinDestination(for: record, isRemote: true, projects: [])?.id == nil)
        #expect(fx.state.unpinDestination(for: record, isRemote: true, projects: [project])?.id == project.id)
        #expect(fx.state.unpinDestination(for: record, isRemote: false, projects: [project])?.id == sessionsID)
    }

    @Test
    func an_unloaded_remote_pinned_row_does_not_unpin_into_the_sessions() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let project = seedRemoteProject(fx)
        let tab = try #require(fx.state.workspaces[project.id]?.activeTab)
        fx.state.pinTab(tab.id, fromProject: project.id)
        fx.state.closeTab(tab.id, projectID: PinnedTabs.projectID)
        #expect(!fx.state.isPinnedTabLoaded(tab.id))

        fx.state.moveTab(tab.id, from: PinnedTabs.projectID, to: sessionsID, destPath: SessionTabs.fallbackRoot)

        #expect(fx.state.pinnedRecords.map(\.id) == [tab.id])
        #expect(!fx.state.hasSessions)
    }

    // MARK: - Keyboard cycling

    /// Pinned, then sessions, then the projects in order: the order of the
    /// sidebar. With three or more stops, a wrong order lands elsewhere.
    @Test
    func project_cycling_goes_through_the_sessions_between_pinned_and_projects() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let first = seedProject(fx, name: "first")
        let second = seedProject(fx, name: "second", path: "/var")
        let pinned = try #require(fx.state.workspaces[second.id]?.activeTab)
        fx.state.pinTab(pinned.id, fromProject: second.id)
        try run(.newSession, fx)
        let projects = [first, second]
        fx.state.selectPinnedProject()

        fx.state.selectNextProject(projects: projects)
        #expect(fx.state.activeProjectID == sessionsID)
        fx.state.selectNextProject(projects: projects)
        #expect(fx.state.activeProjectID == first.id)
        fx.state.selectPreviousProject(projects: projects)
        #expect(fx.state.activeProjectID == sessionsID)
        fx.state.selectPreviousProject(projects: projects)
        #expect(fx.state.activeProjectID == PinnedTabs.projectID)
    }

    @Test
    func global_tab_cycling_visits_the_sessions_between_pinned_and_projects() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        let project = seedProject(fx)
        let pinned = try #require(fx.state.workspaces[project.id]?.activeTab)
        // The folder of `seedProject` (`Project.path` is optional where projects
        // can have no folder).
        let projectTab = try #require(fx.state.workspaces[project.id]?.createTab(projectPath: "/tmp"))
        fx.state.pinTab(pinned.id, fromProject: project.id)
        try run(.newSession, fx)
        let session = try #require(fx.state.sessionWorkspace?.activeTab)
        let projects = [project]
        fx.state.selectPinnedTab(pinned.id)

        fx.state.selectGlobalTab(.next, projects: projects)
        #expect(fx.state.activeProjectID == sessionsID)
        #expect(fx.state.sessionWorkspace?.activeTabID == session.id)

        fx.state.selectGlobalTab(.next, projects: projects)
        #expect(fx.state.activeProjectID == project.id)
        #expect(fx.state.workspaces[project.id]?.activeTabID == projectTab.id)

        fx.state.selectGlobalTab(.previous, projects: projects)
        #expect(fx.state.activeProjectID == sessionsID)
    }

    // MARK: - Commands that are only for projects

    @Test
    func project_commands_do_not_apply_to_the_sessions() throws {
        let fx = makeFixture()
        _ = keyWindow(fx.state)
        try run(.newSession, fx)

        for command in [AppCommand.renameProject, .unloadProject, .removeProject, .saveLayout, .applyLayout, .files] {
            #expect(command.action(in: fx.ctx) == nil, "\(command)")
        }
        // A session is a tab like any other: it can be pinned.
        #expect(AppCommand.pinTab.action(in: fx.ctx) != nil)
    }

    // MARK: - Reserved name

    @Test
    func reserves_its_own_name_in_any_case_and_padding_only() {
        for name in ["Sessions", "sessions", "SESSIONS", " Sessions ", "\tsessions\n"] {
            #expect(SessionTabs.reservesName(name), "\(name)")
            #expect(ReservedProjectName.isReserved(name), "\(name)")
            #expect(ReservedProjectName.message(for: name) == SessionTabs.reservedNameMessage)
        }
        for name in ["", "Sessions 2", "Session", "my sessions", SessionTabs.projectID.uuidString] {
            #expect(!SessionTabs.reservesName(name), "\(name)")
        }
        // The pinned name keeps its own message.
        #expect(ReservedProjectName.isReserved("Pinned"))
        #expect(ReservedProjectName.message(for: "Pinned") == PinnedTabs.reservedNameMessage)
    }

    @Test
    func a_folder_with_the_reserved_name_opens_as_a_second_one() {
        let fx = makeFixture()

        let project = fx.store.create(name: "sessions", path: "/tmp/sessions")

        #expect(project.name == "sessions 2")
    }

    @Test
    func a_project_cannot_be_renamed_to_the_reserved_name() {
        let fx = makeFixture()
        let project = fx.store.create(name: "api", path: "/tmp/api")

        fx.store.rename(id: project.id, to: "Sessions")

        #expect(fx.store.projects.first?.name == "api")
    }
}
