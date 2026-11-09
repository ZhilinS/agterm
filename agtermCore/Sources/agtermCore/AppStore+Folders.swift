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
        let wanted = movingGroupIDs(sessionIDs)
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
        let ids = movingGroupIDs(sessionIDs)
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
        var previous: UUID?
        for session in moving.sessions {
            if let previous {
                _ = workspaces[target].insertSession(session, after: previous)
            } else {
                workspaces[target].insertSession(session, atItem: slot - emptiedAhead)
            }
            previous = session.id
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
        if !sessionIDs.isEmpty, sessionIDs.allSatisfy({ session(withID: $0)?.parentID != nil }) {
            // companions reorder among their siblings through upstream's move, which refuses any other slot
            let remaining = workspaces[target].sessions.filter { !sessionIDs.contains($0.id) }
            guard let slot = remaining.firstIndex(where: { $0.id == anchorID }) else { return 0 }
            let index = if case .after = anchor { slot + 1 } else { slot }
            return moveSessions(sessionIDs, toWorkspace: workspaces[target].id, at: index)
        }
        // the anchor's own group stays put, so moving a parent beside its companion is a no-op
        let anchorParent = session(withID: anchorID)?.parentID ?? anchorID
        let anchorGroup = movingGroupIDs([anchorParent])
        let moving = removeForMove(sessionIDs.filter { !anchorGroup.contains($0) })
        let start = topLevelAnchor(anchor, in: workspaces[target])
        var next = start
        for session in moving.sessions {
            workspaces[target].insertSession(session, anchor: next)
            if case .after = start { next = .after(session.id) }
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
        var previous: UUID?
        for session in moving.sessions {
            if let previous {
                _ = workspaces[target].insertSession(session, after: previous)
            } else {
                workspaces[target].insertSession(session, inFolder: folderID, at: index)
            }
            previous = session.id
        }
        finishMove(moving)
        return moving.sessions.count
    }

    private func removeForMove(_ sessionIDs: [UUID]) -> (sessions: [Session], before: [[[UUID]]]) {
        let before = workspaces.map(\.itemShape)
        var moving: [Session] = []
        for id in orderedSessionIDs(matching: movingGroupIDs(sessionIDs)) {
            guard let location = location(ofSession: id),
                  let session = workspaces[location.workspaceIndex].removeSession(id: id) else { continue }
            moving.append(session)
        }
        return (moving, before)
    }

    /// `movingGroupIDs` in tree order, the sessions a fork move of `sessionIDs` takes.
    public func movingGroup(_ sessionIDs: [UUID]) -> [UUID] {
        orderedSessionIDs(matching: movingGroupIDs(sessionIDs))
    }

    /// The parents among `sessionIDs` with their companions: a companion moves only with its parent here, as in
    /// upstream's moves, so a group never splits across containers.
    func movingGroupIDs(_ sessionIDs: [UUID]) -> Set<UUID> {
        let parents = sessionIDs.filter { session(withID: $0)?.parentID == nil }
        return Set(parents + parents.flatMap { companions(of: $0).map(\.id) })
    }

    /// A top-level anchor outside any companion group: one naming a group member stands after the group's last.
    func topLevelAnchor(_ anchor: SessionAnchor, in workspace: Workspace) -> SessionAnchor {
        let id = switch anchor {
        case .after(let id), .before(let id): id
        }
        let sessions = workspace.sessions
        guard var parent = sessions.firstIndex(where: { $0.id == id }) else { return anchor }
        if case .before = anchor, sessions[parent].parentID == nil { return anchor }
        while parent > 0, sessions[parent].parentID != nil { parent -= 1 }
        return .after(sessions[Self.groupEnd(from: parent, in: sessions) - 1].id)
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
