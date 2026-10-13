import Foundation

extension AppStore {
    /// Duplicates a session: a fresh shell in the SAME workspace, inserted directly after the source, rooted
    /// at its focused-pane cwd (`focusedCwd`, the directory the sidebar row shows) passed through
    /// `localWorkingDirectory`, since the duplicate is a local shell even when the source is a remote pane.
    ///
    /// ONLY the directory carries over: auto basename (no inherited `customName`), no split, scratch, status,
    /// flag or `initialCommand` — `New Session` seeded with the source's cwd, not a clone of its state.
    /// Returns nil if no session matches. Backs the sidebar row's "Duplicate" and `session.duplicate`.
    @discardableResult
    public func duplicateSession(_ id: UUID) -> Session? {
        guard let session = session(withID: id), let workspace = workspace(forSession: id) else { return nil }
        let cwd = session.localWorkingDirectory(reported: session.focusedCwd,
                                                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
        return addSession(toWorkspace: workspace.id, cwd: cwd, anchor: .after(id))
    }
}
