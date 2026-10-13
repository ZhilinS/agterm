import Foundation

extension AppStore {
    public func folder(withID folderID: UUID) -> SessionFolder? {
        workspaces.lazy.compactMap { $0.folder(withID: folderID) }.first
    }

    func workspaceIndex(ofFolder folderID: UUID) -> Int? {
        workspaces.firstIndex { $0.folder(withID: folderID) != nil }
    }

    /// A folder holding `sessionIDs` of this workspace, in tree order, at the first one's slot (after its
    /// folder when that one is already inside one). Without ids, an empty folder appended. Nil on an unknown
    /// workspace.
    @discardableResult
    public func addFolder(toWorkspace workspaceID: UUID, name: String, containing sessionIDs: [UUID] = []) -> SessionFolder? {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return nil }
        let wanted = Set(sessionIDs)
        let moving = workspaces[index].sessions.map(\.id).filter(wanted.contains)
        var slot: Int?
        if let first = moving.first {
            slot = workspaces[index].itemIndex(ofLooseSession: first)
                ?? workspaces[index].container(ofSession: first).flatMap(workspaces[index].itemIndex(ofFolder:)).map { $0 + 1 }
        }
        let folder = SessionFolder(name: TerminalText.sanitized(name).trimmedOrNil ?? "folder")
        workspaces[index].addFolder(folder, at: slot)
        for id in moving {
            if let session = workspaces[index].removeSession(id: id) {
                workspaces[index].insertSession(session, inFolder: folder.id)
            }
        }
        scheduleTreeChanged()
        save()
        return workspaces[index].folder(withID: folder.id)
    }

    public func renameFolder(_ folderID: UUID, to name: String) {
        guard let trimmed = TerminalText.sanitized(name).trimmedOrNil,
              let index = workspaceIndex(ofFolder: folderID),
              workspaces[index].folder(withID: folderID)?.name != trimmed else { return }
        workspaces[index].renameFolder(folderID, to: trimmed)
        scheduleTreeChanged()
        save()
    }

    public func setFolderExpanded(_ folderID: UUID, expanded: Bool) {
        guard let index = workspaceIndex(ofFolder: folderID),
              workspaces[index].folder(withID: folderID)?.isExpanded != expanded else { return }
        workspaces[index].setFolderExpanded(folderID, expanded)
        save()
    }

    /// Removes an EMPTY folder; one still holding sessions is left alone, since dropping it would drop them
    /// without teardown. `AppActions.deleteFolder` closes them first.
    public func deleteFolder(_ folderID: UUID) {
        guard let index = workspaceIndex(ofFolder: folderID),
              workspaces[index].folder(withID: folderID)?.sessions.isEmpty == true else { return }
        workspaces[index].removeFolder(id: folderID)
        scheduleTreeChanged()
        save()
    }

    /// The session's container and its slot there: a folder's session list, or the workspace's `items`.
    public func containerLocation(ofSession id: UUID) -> (workspace: UUID, folder: UUID?, index: Int, count: Int)? {
        guard let workspace = workspace(forSession: id) else { return nil }
        if let folderID = workspace.container(ofSession: id), let folder = workspace.folder(withID: folderID),
           let slot = folder.sessions.firstIndex(where: { $0.id == id }) {
            return (workspace.id, folderID, slot, folder.sessions.count)
        }
        guard let slot = workspace.itemIndex(ofLooseSession: id) else { return nil }
        return (workspace.id, nil, slot, workspace.items.count)
    }

    /// The drop form of `moveSessions(_:toWorkspace:at:)`: the block lands loose at `slot` of the target's
    /// post-removal `items`. Returns the count moved.
    @discardableResult
    public func moveSessions(_ sessionIDs: [UUID], toWorkspace targetID: UUID, atItem slot: Int) -> Int {
        guard let target = workspaces.firstIndex(where: { $0.id == targetID }) else { return 0 }
        let moving = removeForMove(sessionIDs)
        for (offset, session) in moving.sessions.enumerated() {
            workspaces[target].insertSession(session, atItem: slot + offset)
        }
        finishMove(moving)
        return moving.sessions.count
    }

    /// Moves sessions, in tree order, into a folder of any workspace: all are removed first, then the block
    /// lands at `index` of the folder's post-removal list, nil appends. Returns the count moved.
    @discardableResult
    public func moveSessions(_ sessionIDs: [UUID], toFolder folderID: UUID, at index: Int? = nil) -> Int {
        guard let target = workspaceIndex(ofFolder: folderID) else { return 0 }
        let moving = removeForMove(sessionIDs)
        for (offset, session) in moving.sessions.enumerated() {
            workspaces[target].insertSession(session, inFolder: folderID, at: index.map { $0 + offset })
        }
        finishMove(moving)
        return moving.sessions.count
    }

    private func removeForMove(_ sessionIDs: [UUID]) -> (sessions: [Session], before: [[[UUID]]]) {
        let before = workspaces.map(\.itemShape)
        var moving: [Session] = []
        for id in orderedSessionIDs(matching: Set(sessionIDs)) {
            guard let location = location(ofSession: id),
                  let session = workspaces[location.workspaceIndex].removeSession(id: id) else { continue }
            moving.append(session)
        }
        return (moving, before)
    }

    private func finishMove(_ moving: (sessions: [Session], before: [[[UUID]]])) {
        if let selectedSessionID, moving.sessions.contains(where: { $0.id == selectedSessionID }) {
            disableFocusIfSelectionOutsideSet(selectedSessionID)
        }
        pruneSidebarSelection()
        if moving.before != workspaces.map(\.itemShape) { scheduleTreeChanged() }
        save()
    }
}
