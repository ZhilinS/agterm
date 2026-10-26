import Foundation
import agtermCore

// Fork: page sharing's control actions, kept out of upstream's ControlServer files.
extension ControlServer: PageShareActions {
    /// The Share button's control twin, minus the clipboard: the socket never writes it, the reply carries the link.
    func shareSessionOverlay(_ target: String?, window: String?, pane: OverlayPane?) async -> ControlResponse {
        switch sharedFile(target, window: window, pane: pane) {
        case .failure(let response): return response
        case .success(let (session, path)):
            let share = await PageSharing.shared.share(file: path, copyLink: false)
            return share?.response(session: session) ?? ControlResponse(ok: false, error: PageShareError.notConfigured)
        }
    }

    func sessionOverlayComments(_ target: String?, window: String?, pane: OverlayPane?) async -> ControlResponse {
        switch sharedFile(target, window: window, pane: pane) {
        case .failure(let response): return response
        case .success(let (_, path)):
            guard let config = PageSharing.shared.config else {
                return ControlResponse(ok: false, error: PageShareError.notConfigured)
            }
            return await PageComments.response(file: path, config: config, transport: PageSharing.shared.transport)
        }
    }

    /// sharedFile is the session and file of the addressed file page, once sharing is configured.
    private func sharedFile(_ target: String?, window: String?,
                            pane: OverlayPane?) -> ControlTargetResolver.Resolution<(UUID, String)> {
        guard PageSharing.shared.config != nil else {
            return .failure(ControlResponse(ok: false, error: PageShareError.notConfigured))
        }
        switch resolver.resolveSessionTarget(target, window: window) {
        case .failure(let response): return .failure(response)
        case .success(let (store, id)):
            switch store.sharedPage(id, pane: pane) {
            case .failure(let failure): return .failure(ControlResponse(ok: false, error: failure.message))
            case .success(let page):
                guard case .file(let file, _) = page.source else {
                    return .failure(ControlResponse(ok: false, error: PageShareError.notFile))
                }
                return .success((id, file))
            }
        }
    }
}
