"""Sessions: tabs that belong to no project (`SessionTabs`).

A session opens in a section of its own, its shell starts in the home
folder, and New Tab in a window that shows no project opens one. The CLI
reaches the section as `--project sessions`.

The janitor closes only the tabs of the active project, so each test closes
its sessions itself.
"""

import json
import os
import uuid

from _harness import MactermHarness, wait_for

SESSIONS_ID = "5E551045-0000-4000-8000-4D6163536573"


def _text(app, session, scrollback=False):
    """The session pane's text, or None while its surface isn't live yet."""
    extra = ["--scrollback"] if scrollback else []
    result = app.cli("pane", "dump", "--session", session, *extra, "--json", check=False)
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)["dump"]["text"]


def _session_tab_ids(app):
    return [tab["id"] for tab in app.cli_json("tab", "list", "--project", "sessions").get("tabs") or []]


def _close_sessions(app, tab_ids):
    for tab_id in tab_ids:
        app.cli("tab", "close", tab_id, "--project", "sessions", "--force", check=False)


def test_a_session_runs_a_shell_in_the_home_folder_without_a_project(app):
    """`--no-focus` opens the session in the background; its shell starts
    without a visit (the warm), and the active project does not move."""
    before = app.cli_json("status")["status"].get("activeProjectID")
    created = app.cli_json("tab", "new", "--project", "sessions", "--no-focus")["tabs"][0]
    try:
        assert created["id"] in _session_tab_ids(app)
        panes = wait_for(
            lambda: app.cli_json("pane", "list", "--project", "sessions", "--tab", created["id"]).get("panes"),
            message="the session's pane",
        )
        session = panes[0]["session"]
        # Its zmx session groups under one slug, not the home folder's name.
        assert session.startswith("macterm-session-"), session
        wait_for(lambda: _text(app, session), timeout=60, message="the session's shell prompt")

        nonce = uuid.uuid4().hex[:12]
        app.pane_run(f'/bin/sh -c "printf started-%s {nonce}; echo; printf cwd-%s $PWD; echo"', session=session)
        text = wait_for(
            lambda: (t := _text(app, session)) and f"started-{nonce}" in t and t,
            timeout=30,
            message="the marker in the session",
        )
        # The throwaway home is under /tmp, a link: the shell may name it
        # either way.
        assert f"cwd-{app.home}" in text or f"cwd-{os.path.realpath(app.home)}" in text
        assert app.cli_json("status")["status"].get("activeProjectID") == before
    finally:
        _close_sessions(app, [created["id"]])


def test_new_tab_in_a_window_that_shows_no_project_opens_a_session(app, tmp_path):
    """Removing the project that the window shows leaves it on no project.
    There, `tab new` opens a session and shows it, as New Tab does."""
    original = app.cli_json("status")["status"].get("activeProjectID")
    folder = tmp_path / "gone"
    folder.mkdir()
    created = app.cli_json("project", "create", str(folder), "--select")["projects"][0]
    opened = []
    try:
        app.cli("project", "remove", created["id"], "--force")
        assert app.cli_json("status")["status"].get("activeProjectID") is None

        opened.append(app.cli_json("tab", "new")["tabs"][0]["id"])

        assert opened[0] in _session_tab_ids(app)
        status = app.cli_json("status")["status"]
        assert status["activeProjectID"] == SESSIONS_ID
        assert status["activeProject"] == "Sessions"
        # The window shows the new session, not only the section: it is the
        # selected tab, and its terminal goes live. Nothing warms a tab that
        # a window shows, so only the window's render starts that terminal.
        focused = [w for w in app.cli_json("window", "list")["windows"] if w.get("focused")]
        assert [w.get("tabID") for w in focused] == [opened[0]]
        panes = app.cli_json("pane", "list", "--project", "sessions", "--tab", opened[0]).get("panes") or []
        assert len(panes) == 1
        wait_for(lambda: _text(app, panes[0]["session"]), timeout=60, message="the shown session's terminal")
    finally:
        # The last session closes first: the window leaves the section, and
        # the original project comes back for the other tests.
        _close_sessions(app, opened)
        app.cli("project", "select", original, check=False)


def test_a_session_comes_back_after_a_relaunch_with_its_shell(request):
    """The snapshot keeps the session, and the relaunch reattaches its pane
    to the same zmx session: the output from before is in its scrollback,
    and the shell still answers. Its own instance, since the shared one must
    not be restarted under the other tests."""
    harness = MactermHarness(request.config.getoption("--app"), home_prefix="macterm-e2e-sessions-home-")
    try:
        harness.launch()
        harness.wait_for_socket()
        created = harness.cli_json("tab", "new", "--project", "sessions", "--no-focus")["tabs"][0]
        panes = wait_for(
            lambda: harness.cli_json("pane", "list", "--project", "sessions", "--tab", created["id"]).get("panes"),
            message="the session's pane",
        )
        session = panes[0]["session"]
        wait_for(lambda: _text(harness, session), timeout=60, message="the session's shell prompt")
        nonce = uuid.uuid4().hex[:12]
        harness.pane_run(f'/bin/sh -c "printf before-%s {nonce}; echo"', session=session)
        wait_for(lambda: f"before-{nonce}" in (_text(harness, session) or ""), timeout=30, message="the first marker")

        harness.kill()
        harness.launch()
        harness.wait_for_socket()

        wait_for(lambda: created["id"] in _session_tab_ids(harness), timeout=30, message="the session to be restored")
        # Selecting the sessions starts the surfaces of their panes, which
        # attach to the zmx sessions that survived the kill.
        harness.cli("project", "select", "sessions")
        wait_for(
            lambda: f"before-{nonce}" in (_text(harness, session, scrollback=True) or ""),
            timeout=60,
            message="the output from before the relaunch",
        )
        harness.pane_run(f'/bin/sh -c "printf after-%s {nonce}; echo"', session=session)
        wait_for(lambda: f"after-{nonce}" in (_text(harness, session) or ""), timeout=30, message="the second marker")
    finally:
        harness.cleanup()
