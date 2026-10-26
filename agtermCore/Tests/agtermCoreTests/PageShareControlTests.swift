import Foundation
import Testing
@testable import agtermCore

extension MockControlActions: PageShareActions {
    func shareSessionOverlay(_ target: String?, window: String?, pane: OverlayPane?) async -> ControlResponse {
        calls.append(.overlayShare(target: target, window: window, pane: pane))
        return ControlResponse(ok: true)
    }

    func sessionOverlayComments(_ target: String?, window: String?, pane: OverlayPane?) async -> ControlResponse {
        calls.append(.overlayComments(target: target, window: window, pane: pane))
        return ControlResponse(ok: true)
    }
}

// Fork: page sharing's tree, dispatcher and page-bridge coverage, kept out of upstream's test files.
@MainActor
struct PageShareControlTests {
    @Test func aSharedFilePageReportsItsShare() throws {
        let store = makeStore()
        let workspace = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: workspace.id, cwd: "/tmp"))
        let path = "/tmp/a/shared-\(UUID().uuidString).html"
        #expect(store.openHtmlOverlay(session.id, pane: nil, overlay: HtmlOverlay(source: .file(path: path, grantRoot: nil)),
                                      sizePercent: nil) == nil)
        let notShared = try #require(store.controlTree().workspaces[0].sessions[0].htmlOverlays?.first)
        #expect(notShared.share == nil)
        #expect(!String(decoding: try JSONEncoder().encode(notShared), as: UTF8.self).contains(#""share""#))

        let id = PageShares.id(forFile: path)
        PageShares.shared.shares[id] = PageShare(url: "https://pages/\(id)/", state: .failed, pipelineURL: "https://p/1",
                                                 error: "pipeline failed")
        defer { PageShares.shared.shares[id] = nil }

        let node = try #require(store.controlTree().workspaces[0].sessions[0].htmlOverlays?.first)
        #expect(node.share == ControlPageShareNode(url: "https://pages/\(id)/", state: "failed", pipelineURL: "https://p/1",
                                                   error: "pipeline failed"))
        #expect(try JSONDecoder().decode(ControlHtmlOverlayNode.self, from: JSONEncoder().encode(node)) == node)
    }

    @Test func shareRoutesThePaneAndRejectsAnUnknownOne() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)

        _ = await dispatcher.dispatch(ControlRequest(cmd: .sessionOverlayShare, target: "session",
                                                     args: ControlArgs(window: "win", pane: "split")))
        _ = await dispatcher.dispatch(ControlRequest(cmd: .sessionOverlayShare))
        let bad = await dispatcher.dispatch(ControlRequest(cmd: .sessionOverlayShare, args: ControlArgs(pane: "middle")))

        #expect(bad == ControlResponse(ok: false, error: PaneOverlayError.invalidPane))
        #expect(actions.calls == [.overlayShare(target: "session", window: "win", pane: .right),
                                  .overlayShare(target: nil, window: nil, pane: nil)])
    }

    @Test func commentsRouteThePaneAndRejectAnUnknownOne() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)

        _ = await dispatcher.dispatch(ControlRequest(cmd: .sessionOverlayComments, target: "session",
                                                     args: ControlArgs(window: "win", pane: "primary")))
        _ = await dispatcher.dispatch(ControlRequest(cmd: .sessionOverlayComments))
        let bad = await dispatcher.dispatch(ControlRequest(cmd: .sessionOverlayComments, args: ControlArgs(pane: "middle")))

        #expect(bad == ControlResponse(ok: false, error: PaneOverlayError.invalidPane))
        #expect(actions.calls == [.overlayComments(target: "session", window: "win", pane: .left),
                                  .overlayComments(target: nil, window: nil, pane: nil)])
    }

    @Test(arguments: ["session.overlay.share", "session.overlay.comments"])
    func thePageBridgeFillsThePagesOwnPane(_ cmd: String) throws {
        let session = UUID()
        let page = HtmlBridgePage(window: "W1", session: session, pane: .right)
        let built = try HtmlBridge.request(from: Data(#"{"cmd":"\#(cmd)"}"#.utf8), page: page).get()
        #expect(built.target == session.uuidString)
        #expect(built.args?.pane == "right")
    }
}
