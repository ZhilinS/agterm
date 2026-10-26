import agtermCore
import AppKit
import SwiftUI

extension AppActions {
    /// Delete a folder of `store`'s window: an empty one at once; otherwise, after the Delete Workspace confirm, its
    /// sessions close through the multi-select close path and the emptied folder goes.
    func deleteFolder(_ folderID: UUID, in store: AppStore, confirm: ((String, Int) -> Bool)? = nil) {
        guard let folder = store.folder(withID: folderID) else { return }
        let ids = folder.sessions.map(\.id)
        if !ids.isEmpty {
            guard (confirm ?? confirmDelete)(folder.name, ids.count) else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                if closeGraceUndoEnabled {
                    _ = store.softCloseSessions(ids)
                } else {
                    for id in ids { store.closeSession(id) }
                }
            }
        }
        store.deleteFolder(folderID)
        focusActiveSession()
    }

    /// resolvedNewSessionAnchor applies the placement setting to the supplied store's tree; nil appends.
    func resolvedNewSessionAnchor(in workspaceID: UUID, store: AppStore) -> SessionAnchor? {
        store.newSessionAnchor(inWorkspace: workspaceID,
                               placement: settingsModel?.settings.effectiveNewSessionPlacement ?? .end)
    }
}
