import Foundation
@testable import Macterm
import Testing

/// The CLI and the tabs without a project (`SessionTabs`): `tab new` with no
/// project opens a session, as New Tab does in the app, and `--project
/// sessions` addresses the section, which the project verbs refuse to change.
@MainActor
struct ControlHandlerSessionTests {
    // MARK: - Setup helpers (tempdir stores, mirroring ControlHandlerTests)

    private func makeHandler() -> (ControlHandler, AppState, ProjectStore) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("macterm-control-session-tests-\(UUID().uuidString).json")
        let projectsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macterm-control-session-tests-projects-\(UUID().uuidString)", isDirectory: true)
        let appState = AppState(
            workspaceStore: WorkspaceStore(fileURL: tmp),
            projectFiles: ProjectFileStore(directoryURL: projectsDir)
        )
        appState.zmx = .noop
        appState.incubatePane = { _ in }
        let projectStore = ProjectStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("macterm-control-session-tests-store-\(UUID().uuidString).json"))
        return (ControlHandler(appState: appState, projectStore: projectStore), appState, projectStore)
    }

    /// A key window that shows no project.
    private func keyWindow(_ appState: AppState) -> WindowState {
        let window = WindowState()
        appState.registerWindow(window)
        appState.noteKeyWindow(window)
        return window
    }

    private func request(_ command: String, args: ControlArgs? = nil) -> ControlRequest {
        ControlRequest(command: command, args: args)
    }

    // MARK: - tab new

    @Test
    func tab_new_with_no_project_opens_a_session_and_shows_it() async {
        let (handler, appState, _) = makeHandler()
        let window = keyWindow(appState)

        let response = await handler.handle(request("tab.new"))

        #expect(response.ok)
        #expect(response.data?.tabs?.count == 1)
        #expect(appState.sessionWorkspace?.tabs.count == 1)
        #expect(window.activeProjectID == SessionTabs.projectID)
        let status = await handler.handle(request("status"))
        #expect(status.data?.status?.activeProjectID == SessionTabs.projectID.uuidString)
        #expect(status.data?.status?.activeProject == SessionTabs.displayName)
    }

    /// The window remembers the session that it showed last; the new one is
    /// the one that it shows.
    @Test
    func tab_new_with_no_project_shows_the_new_session_over_a_remembered_one() async throws {
        let (handler, appState, projectStore) = makeHandler()
        let window = keyWindow(appState)
        _ = await handler.handle(request("tab.new"))
        let older = try #require(appState.sessionWorkspace?.activeTab)
        let project = Project(name: "demo", path: "/tmp", sortOrder: 0)
        projectStore.add(project)
        appState.selectProject(project)
        appState.removeProject(project.id)
        #expect(window.activeProjectID == nil)

        let response = await handler.handle(request("tab.new"))

        let newID = try #require(response.data?.tabs?.first?.id)
        #expect(newID != older.id.uuidString)
        #expect(appState.selectedTab(for: SessionTabs.projectID, in: window)?.id.uuidString == newID)
    }

    @Test
    func the_sessions_uuid_selects_them_in_any_case() async {
        let (handler, appState, _) = makeHandler()
        _ = keyWindow(appState)
        _ = await handler.handle(request("tab.new"))

        for selector in [SessionTabs.projectID.uuidString, SessionTabs.projectID.uuidString.lowercased()] {
            let listed = await handler.handle(request("tab.list", args: ControlArgs(project: selector)))
            #expect(listed.data?.tabs?.count == 1, "\(selector)")
        }
    }

    @Test
    func tab_new_no_focus_with_no_project_opens_a_session_and_leaves_the_window() async {
        let (handler, appState, _) = makeHandler()
        let window = keyWindow(appState)

        let response = await handler.handle(request("tab.new", args: ControlArgs(focus: false)))

        #expect(response.ok)
        #expect(appState.sessionWorkspace?.tabs.count == 1)
        #expect(window.activeProjectID == nil)
    }

    @Test
    func the_sessions_selector_opens_and_lists_sessions_in_any_case() async {
        let (handler, appState, projectStore) = makeHandler()
        _ = keyWindow(appState)
        let project = Project(name: "demo", path: "/tmp", sortOrder: 0)
        projectStore.add(project)
        appState.selectProject(project)

        let first = await handler.handle(request("tab.new", args: ControlArgs(project: "sessions")))
        let second = await handler.handle(request("tab.new", args: ControlArgs(project: "Sessions")))
        let listed = await handler.handle(request("tab.list", args: ControlArgs(project: "SESSIONS")))

        #expect(first.ok)
        #expect(second.ok)
        #expect(listed.data?.tabs?.count == 2)
        // A tab opened in a section that the window does not show stays in
        // the background, as for a project.
        #expect(appState.activeProjectID == project.id)
        let byID = await handler.handle(request(
            "tab.list", args: ControlArgs(project: SessionTabs.projectID.uuidString)
        ))
        #expect(byID.data?.tabs?.count == 2)
    }

    @Test
    func a_session_selector_finds_its_pane_in_the_sessions() async throws {
        let (handler, appState, projectStore) = makeHandler()
        _ = keyWindow(appState)
        _ = await handler.handle(request("tab.new"))
        let pane = try #require(appState.sessionWorkspace?.tabs.first?.splitRoot.allPanes().first)
        // The user looks at a project now; the session still resolves.
        let project = Project(name: "demo", path: "/tmp", sortOrder: 0)
        projectStore.add(project)
        appState.selectProject(project)

        let response = await handler.handle(request("tab.list", args: ControlArgs(session: pane.sessionName)))

        #expect(response.ok)
        #expect(response.data?.tabs?.count == 1)
    }

    // MARK: - project verbs

    @Test
    func project_select_sessions_needs_a_session() async {
        let (handler, appState, _) = makeHandler()
        let window = keyWindow(appState)

        let empty = await handler.handle(request("project.select", args: ControlArgs(project: "sessions")))
        #expect(empty.error?.code == .notFound)

        _ = await handler.handle(request("tab.new", args: ControlArgs(focus: false)))
        let selected = await handler.handle(request("project.select", args: ControlArgs(project: "sessions")))
        #expect(selected.ok)
        #expect(window.activeProjectID == SessionTabs.projectID)
    }

    @Test
    func the_sessions_section_cannot_be_renamed_removed_or_given_a_layout() async {
        let (handler, appState, _) = makeHandler()
        _ = keyWindow(appState)
        _ = await handler.handle(request("tab.new"))

        let renamed = await handler.handle(request(
            "project.rename", args: ControlArgs(project: "sessions", name: "scratch")
        ))
        let removed = await handler.handle(request("project.remove", args: ControlArgs(project: "sessions")))
        let saved = await handler.handle(request("layout.save", args: ControlArgs(project: "sessions")))

        #expect(renamed.error?.code == .badRequest)
        #expect(removed.error?.code == .badRequest)
        #expect(saved.error?.code == .badRequest)
        #expect(appState.sessionWorkspace?.tabs.count == 1)
    }

    @Test
    func project_create_refuses_the_reserved_name() async throws {
        let (handler, _, projectStore) = makeHandler()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macterm-control-session-tests-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let response = await handler.handle(request(
            "project.create", args: ControlArgs(path: dir.path, name: " sessions ")
        ))

        #expect(response.error?.code == .badRequest)
        #expect(response.error?.message == "\"Sessions\" is a reserved name for the tabs without a project")
        #expect(projectStore.projects.isEmpty)
    }
}
