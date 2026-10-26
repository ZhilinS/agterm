import Foundation

public struct SessionContainerLocation: Equatable, Sendable {
    public let workspace: UUID
    public let folder: UUID?
    public let index: Int
    public let count: Int
}

extension AppStore {
    public func folder(withID folderID: UUID) -> SessionFolder? {
        workspaces.lazy.compactMap { $0.folder(withID: folderID) }.first
    }

    public func workspace(forFolder folderID: UUID) -> Workspace? {
        workspaceIndex(ofFolder: folderID).map { workspaces[$0] }
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
    /// without teardown. `AppActions.deleteFolder` closes them first, and closing the last one removes it.
    public func deleteFolder(_ folderID: UUID) {
        guard let index = workspaceIndex(ofFolder: folderID),
              workspaces[index].folder(withID: folderID)?.sessions.isEmpty == true else { return }
        workspaces[index].removeFolder(id: folderID)
        scheduleTreeChanged()
        save()
    }

    /// The session's container and its slot there: a folder's session list, or the workspace's `items`.
    public func containerLocation(ofSession id: UUID) -> SessionContainerLocation? {
        guard let workspace = workspace(forSession: id) else { return nil }
        if let folderID = workspace.container(ofSession: id), let folder = workspace.folder(withID: folderID),
           let slot = folder.sessions.firstIndex(where: { $0.id == id }) {
            return SessionContainerLocation(workspace: workspace.id, folder: folderID, index: slot, count: folder.sessions.count)
        }
        guard let slot = workspace.itemIndex(ofLooseSession: id) else { return nil }
        return SessionContainerLocation(workspace: workspace.id, folder: nil, index: slot, count: workspace.items.count)
    }

    /// The drop form of `moveSessions(_:toWorkspace:at:)`: the block lands loose at `slot` of the target's
    /// post-removal `items`. Returns the count moved.
    @discardableResult
    public func moveSessions(_ sessionIDs: [UUID], toWorkspace targetID: UUID, atItem slot: Int) -> Int {
        guard let target = workspaces.firstIndex(where: { $0.id == targetID }) else { return 0 }
        // the slot is in `SidebarDrop`'s space: moving loose sessions already taken out, folders as they stand.
        // one this move empties is gone when the block lands, so the slot comes down by one per such folder
        let ids = Set(sessionIDs)
        var position = 0
        var emptiedAhead = 0
        for item in workspaces[target].items where position < slot {
            switch item {
            case .session(let session) where ids.contains(session.id):
                continue
            case .session:
                position += 1
            case .folder(let folder):
                if !folder.sessions.isEmpty, folder.sessions.allSatisfy({ ids.contains($0.id) }) {
                    emptiedAhead += 1
                }
                position += 1
            }
        }
        let moving = removeForMove(sessionIDs)
        for (offset, session) in moving.sessions.enumerated() {
            workspaces[target].insertSession(session, atItem: slot - emptiedAhead + offset)
        }
        finishMove(moving)
        return moving.sessions.count
    }

    /// Moves sessions, in tree order, beside `anchor` in the anchor's container; the anchor itself never moves.
    @discardableResult
    public func moveSessions(_ sessionIDs: [UUID], anchor: SessionAnchor) -> Int {
        let anchorID = switch anchor {
        case .after(let id), .before(let id): id
        }
        guard let target = workspaces.firstIndex(where: { $0.sessions.contains { $0.id == anchorID } }) else { return 0 }
        let moving = removeForMove(sessionIDs.filter { $0 != anchorID })
        var next = anchor
        for session in moving.sessions {
            workspaces[target].insertSession(session, anchor: next)
            if case .after = anchor { next = .after(session.id) }
        }
        finishMove(moving)
        return moving.sessions.count
    }

    /// Moves sessions, in tree order, into a folder of any workspace: all are removed first, then the block
    /// lands at `index` of the folder's post-removal list, nil appends. Returns the count moved.
    @discardableResult
    public func moveSessions(_ sessionIDs: [UUID], toFolder folderID: UUID, at index: Int? = nil) -> Int {
        guard let target = workspaceIndex(ofFolder: folderID),
              let folder = workspaces[target].folder(withID: folderID),
              let slot = workspaces[target].itemIndex(ofFolder: folderID) else { return 0 }
        let ahead = workspaces[target].itemShape.prefix(slot).compactMap(\.first)
        let moving = removeForMove(sessionIDs)
        // moving every member out drops the folder on the way; put it back where the survivors leave it
        let survivors = Set(workspaces[target].itemShape.compactMap(\.first))
        workspaces[target].restoreFolder(ClosedFolder(
            id: folderID,
            name: folder.name,
            isExpanded: folder.isExpanded,
            itemIndex: ahead.count(where: survivors.contains)
        ))
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

    /// Whether any pending close would put folder `id` back: a member other than `sessionID` recorded in it,
    /// or a closed workspace still holding it.
    func pendingHoldsFolder(_ id: UUID, besides sessionID: UUID) -> Bool {
        pendingCloseRecords.values.contains { record in
            switch record {
            case .sessions(let close): return close.sessions.contains { $0.session.id != sessionID && $0.folder?.id == id }
            case .workspace(let close): return close.workspace.folder(withID: id) != nil
            }
        }
    }

    /// Rebuilds items, dropping sessions `keep` rejects; a folder stays even when it ends up empty.
    func workspaceItems(from items: [WorkspaceItemSnapshot], launchRestore: Bool = false,
                        keep: (UUID) -> Bool = { _ in true }) -> [WorkspaceItem] {
        items.compactMap { item in
            switch item {
            case .session(let snapshot):
                keep(snapshot.id) ? .session(session(from: snapshot, launchRestore: launchRestore)) : nil
            case .folder(let folder):
                .folder(SessionFolder(id: folder.id, name: folder.name, isExpanded: !(folder.collapsed ?? false),
                                      sessions: folder.sessions.filter { keep($0.id) }
                                          .map { session(from: $0, launchRestore: launchRestore) }))
            }
        }
    }
}
