import XCTest
@testable import agterm
import agtermCore

private actor CannedGitLab: GitLabTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let url = request.url?.absoluteString ?? ""
        if url.hasSuffix("/pages") {
            return (Data(#"{"url":"https://snippets.pages.example.com"}"#.utf8), 200)
        }
        if url.contains("/repository/files/") {
            return (Data(#"{"message":"404 File Not Found"}"#.utf8), 404)
        }
        if url.hasSuffix("/repository/commits") {
            return (Data(#"{"id":"c0ffee"}"#.utf8), 201)
        }
        if url.contains("/issues?") {
            return (Data("[]".utf8), 200)
        }
        return (Data(#"[{"status":"success","web_url":"https://gitlab.example.com/p/1"}]"#.utf8), 200)
    }
}

@MainActor
private final class CopyRecorder: HtmlSharing {
    var copied: [String] = []

    func reveal(_: URL) {}
    func copy(_ text: String) { copied.append(text) }
}

@MainActor
final class ControlServerShareTests: XCTestCase {
    private var stateDir: URL!
    private var library: WindowLibrary!
    private var server: ControlServer!
    private var saved: (settings: @MainActor () -> AppSettings, token: String?, transport: any GitLabTransport)!
    private let recorder = CopyRecorder()

    override func setUp() async throws {
        stateDir = FileManager.default.temporaryDirectory.appendingPathComponent("agterm-share-tests-\(UUID().uuidString)")
        library = WindowLibrary(directory: stateDir)
        server = ControlServer(library: library, actions: AppActions(library: library),
                               settingsModel: SettingsModel(library: library, settingsStore: SettingsStore(directory: stateDir)),
                               identity: AppIdentity(version: "9.9.9", commit: "testsha"),
                               socketPath: stateDir.appendingPathComponent("control.sock").path)
        let sharing = PageSharing.shared
        saved = (sharing.settings, sharing.token, sharing.transport)
        sharing.settings = { AppSettings(shareGitLabURL: "https://gitlab.example.com", shareGitLabProject: "team/snippets") }
        sharing.token = "secret"
        sharing.transport = CannedGitLab()
        HtmlOverlayRegistry.shared.sharing = recorder
    }

    override func tearDown() async throws {
        PageSharing.shared.settings = saved.settings
        PageSharing.shared.token = saved.token
        PageSharing.shared.transport = saved.transport
        HtmlOverlayRegistry.shared.sharing = SystemHtmlSharing()
        server = nil
        library = nil
        try? FileManager.default.removeItem(at: stateDir)
    }

    private func open(_ source: HtmlSource) throws -> Session {
        let store = try XCTUnwrap(library.activeStore)
        let session = try XCTUnwrap(store.addSession(toWorkspace: try XCTUnwrap(store.currentWorkspaceID), cwd: NSHomeDirectory()))
        XCTAssertNil(store.openHtmlOverlay(session.id, pane: nil, overlay: HtmlOverlay(source: source), sizePercent: nil))
        return session
    }

    func testShareRepliesWithTheLinkAndTheTreeReadsItBackWithoutTouchingTheClipboard() async throws {
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let file = stateDir.appendingPathComponent("page.html")
        try Data("<h1>hi</h1>".utf8).write(to: file)
        let session = try open(.file(path: file.path, grantRoot: nil))
        let url = "https://snippets.pages.example.com/\(PageShares.id(forFile: file.path))/"

        let response = await server.shareSessionOverlay(session.id.uuidString, window: nil, pane: nil)

        XCTAssertTrue(response.ok, response.error ?? "")
        XCTAssertEqual(response.result?.text, url)
        XCTAssertEqual(response.result?.share,
                       ControlPageShareNode(url: url, state: "idle", pipelineURL: "https://gitlab.example.com/p/1"))
        XCTAssertEqual(recorder.copied, [], "the socket never writes the clipboard")
        let node = server.controlTree(window: nil).result?.tree?.workspaces.flatMap(\.sessions)
            .first { $0.id == session.id.uuidString }
        XCTAssertEqual(node?.htmlOverlays?.first?.share, response.result?.share)
    }

    func testShareRefusesWhenSharingIsNotConfigured() async throws {
        PageSharing.shared.settings = { AppSettings() }
        let session = try open(.file(path: "/tmp/a/page.html", grantRoot: nil))

        let response = await server.shareSessionOverlay(session.id.uuidString, window: nil, pane: nil)

        XCTAssertEqual(response.error, PageShareError.notConfigured)
    }

    func testShareRefusesAWebPageAndAnEmptySlot() async throws {
        let page = try open(.url(try XCTUnwrap(URL(string: "http://localhost:5173/"))))
        let empty = try XCTUnwrap(library.activeStore?.addSession(
            toWorkspace: try XCTUnwrap(library.activeStore?.currentWorkspaceID), cwd: NSHomeDirectory()))

        let web = await server.shareSessionOverlay(page.id.uuidString, window: nil, pane: nil)
        let none = await server.shareSessionOverlay(empty.id.uuidString, window: nil, pane: nil)

        XCTAssertEqual(web.error, PageShareError.notFile)
        XCTAssertEqual(none.error, OverlayHtmlError.noOverlay)
    }

    func testCommentsReadTheFilePagesIssueAndNeedTheOAuthApp() async throws {
        let session = try open(.file(path: "/tmp/a/page.html", grantRoot: nil))
        let web = try open(.url(try XCTUnwrap(URL(string: "http://localhost:5173/"))))

        let off = await server.sessionOverlayComments(session.id.uuidString, window: nil, pane: nil)
        PageSharing.shared.settings = {
            AppSettings(shareGitLabURL: "https://gitlab.example.com", shareGitLabProject: "team/snippets",
                        shareGitLabOAuthAppID: "app-1")
        }
        let on = await server.sessionOverlayComments(session.id.uuidString, window: nil, pane: nil)
        let url = await server.sessionOverlayComments(web.id.uuidString, window: nil, pane: nil)

        XCTAssertEqual(off.error, PageShareError.noComments)
        XCTAssertEqual(on, ControlResponse(ok: true, result: ControlResult(discussions: [])))
        XCTAssertEqual(url.error, PageShareError.notFile)
    }
}
