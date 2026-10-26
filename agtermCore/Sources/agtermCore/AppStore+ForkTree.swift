import Foundation

// Fork: the fork's tree read-back and page lookup, hooked into upstream's controlTree by one call.
extension AppStore {
    /// forkDecorated adds each session's `folder` and each file page's `share` to the nodes upstream built.
    func forkDecorated(_ sessions: [ControlSessionNode], in workspace: Workspace) -> [ControlSessionNode] {
        sessions.map { node in
            var node = node
            node.folder = UUID(uuidString: node.id)
                .flatMap { workspace.container(ofSession: $0) }
                .flatMap { workspace.folder(withID: $0)?.name }
            node.htmlOverlays = node.htmlOverlays?.map { page in
                var page = page
                if page.replica != true, let file = page.file {
                    page.share = PageShares.shared.share(forFile: file)?.node
                }
                return page
            }
            return node
        }
    }

    /// sharedPage is the page in the slot `pane` addresses, or why that slot holds none.
    public func sharedPage(_ sessionID: UUID, pane: OverlayPane?) -> Result<HtmlOverlay, HtmlOverlayCommandFailure> {
        guard let session = session(withID: sessionID) else { return .failure(.unknownSession) }
        let occupied = pane.map { session.paneOverlay($0) != nil } ?? (session.overlayActive && !session.hudActive)
        guard occupied else { return .failure(.noOverlay) }
        let page = pane.map { session.paneOverlay($0)?.html } ?? session.htmlOverlay
        return page.map { .success($0) } ?? .failure(.notHtml)
    }
}
