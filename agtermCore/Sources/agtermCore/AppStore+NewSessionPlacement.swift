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

    /// The folder-aware form of `newSessionInsertionIndex`: a sibling right after the selection.
    public func newSessionAnchor(inWorkspace workspaceID: UUID, placement: AppSettings.NewSessionPlacement) -> SessionAnchor? {
        guard newSessionInsertionIndex(inWorkspace: workspaceID, placement: placement) != nil,
              let selectedSessionID else { return nil }
        return .after(selectedSessionID)
    }
}
