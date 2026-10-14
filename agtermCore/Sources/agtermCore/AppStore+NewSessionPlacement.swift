import Foundation

extension AppStore {
    /// newSessionInsertionIndex returns the slot after the selection in `workspaceID` for `afterCurrent`,
    /// or nil to append.
    public func newSessionInsertionIndex(inWorkspace workspaceID: UUID,
                                         placement: AppSettings.NewSessionPlacement) -> Int? {
        guard placement == .afterCurrent, let selectedSessionID,
              let location = sessionLocation(ofSession: selectedSessionID),
              location.workspace == workspaceID else { return nil }
        return location.index + 1
    }

    /// The folder-aware form of `newSessionInsertionIndex`: a sibling right after the selection, or at the end
    /// of the selection's folder for `end`. Nil appends to the workspace.
    public func newSessionAnchor(inWorkspace workspaceID: UUID, placement: AppSettings.NewSessionPlacement) -> SessionAnchor? {
        guard let selectedSessionID, let workspace = workspace(forSession: selectedSessionID),
              workspace.id == workspaceID else { return nil }
        switch placement {
        case .afterCurrent:
            return .after(selectedSessionID)
        case .end:
            guard let folderID = workspace.container(ofSession: selectedSessionID),
                  let last = workspace.folder(withID: folderID)?.sessions.last else { return nil }
            return .after(last.id)
        }
    }
}
