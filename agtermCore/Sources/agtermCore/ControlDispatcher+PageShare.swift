// Fork: page sharing's dispatch, a protocol of its own so upstream's ControlActions stays untouched.
@MainActor
public protocol PageShareActions {
    /// Publishes the addressed file page to GitLab Pages; the reply comes once the commit landed, before the pipeline.
    func shareSessionOverlay(_ target: String?, window: String?, pane: OverlayPane?) async -> ControlResponse
    /// Reads the comments of the addressed shared file page from its GitLab issue.
    func sessionOverlayComments(_ target: String?, window: String?, pane: OverlayPane?) async -> ControlResponse
}

extension ControlDispatcher {
    func dispatchSessionOverlayShare(_ request: ControlRequest) async -> ControlResponse {
        guard let sharing = actions as? any PageShareActions else {
            return ControlResponse(ok: false, error: ControlActionsUnsupported.message(request.cmd.rawValue))
        }
        switch parseOverlayPane(request.args?.pane) {
        case .rejected(let response): return response
        case .pane(let pane) where request.cmd == .sessionOverlayComments:
            return await sharing.sessionOverlayComments(request.target, window: request.args?.window, pane: pane)
        case .pane(let pane):
            return await sharing.shareSessionOverlay(request.target, window: request.args?.window, pane: pane)
        }
    }
}
