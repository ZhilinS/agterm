import Foundation

/// A named group of sessions inside a workspace, one level deep. A session knows nothing about folders.
@MainActor
public struct SessionFolder: Identifiable {
    public let id: UUID
    public var name: String
    public var isExpanded: Bool
    public var sessions: [Session]

    public init(id: UUID = UUID(), name: String, isExpanded: Bool = true, sessions: [Session] = []) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
        self.sessions = sessions
    }

    public var unseenCount: Int { sessions.reduce(0) { $0 + $1.unseenCount } }
}

@MainActor
public enum WorkspaceItem {
    case session(Session)
    case folder(SessionFolder)
}

/// A user-named group of sessions (e.g. "work", "personal"). A value type with
/// a stable UUID identity; `items` is the only order and the only membership.
@MainActor
public struct Workspace: Identifiable {
    public let id: UUID
    public var name: String
    public var items: [WorkspaceItem]
    /// Whether the sidebar row is expanded (its session rows shown). Defaults true so a freshly created
    /// workspace opens; persisted per workspace so the collapse state survives a relaunch.
    public var isExpanded: Bool

    public init(name: String, sessions: [Session] = [], isExpanded: Bool = true) {
        self.init(id: UUID(), name: name, items: sessions.map(WorkspaceItem.session), isExpanded: isExpanded)
    }

    public init(id: UUID, name: String, sessions: [Session] = [], isExpanded: Bool = true) {
        self.init(id: id, name: name, items: sessions.map(WorkspaceItem.session), isExpanded: isExpanded)
    }

    public init(id: UUID, name: String, items: [WorkspaceItem], isExpanded: Bool = true) {
        self.id = id
        self.name = name
        self.items = items
        self.isExpanded = isExpanded
    }

    /// Preorder walk of `items`, which is the visual order. Read only: writes go through the methods below.
    public var sessions: [Session] {
        items.flatMap { item -> [Session] in
            switch item {
            case .session(let session): [session]
            case .folder(let folder): folder.sessions
            }
        }
    }

    public var folders: [SessionFolder] {
        items.compactMap { if case .folder(let folder) = $0 { folder } else { nil } }
    }

    /// Total unseen-notification count across this workspace's sessions, for the badge on a
    /// collapsed workspace row (when its session rows are hidden).
    public var unseenCount: Int { sessions.reduce(0) { $0 + $1.unseenCount } }

    /// Item order with folder membership, for change detection a flat id list cannot see.
    var itemShape: [[UUID]] {
        items.map { item in
            switch item {
            case .session(let session): [session.id]
            case .folder(let folder): [folder.id] + folder.sessions.map(\.id)
            }
        }
    }

    public func folder(withID id: UUID) -> SessionFolder? {
        folders.first { $0.id == id }
    }

    /// The folder holding the session, nil when it is loose or absent.
    public func container(ofSession sessionID: UUID) -> UUID? {
        folders.first { $0.sessions.contains { $0.id == sessionID } }?.id
    }

    @discardableResult
    public mutating func removeSession(id sessionID: UUID) -> Session? {
        for index in items.indices {
            switch items[index] {
            case .session(let session) where session.id == sessionID:
                items.remove(at: index)
                return session
            case .folder(var folder):
                guard let slot = folder.sessions.firstIndex(where: { $0.id == sessionID }) else { continue }
                let session = folder.sessions.remove(at: slot)
                items[index] = .folder(folder)
                return session
            default:
                continue
            }
        }
        return nil
    }

    /// Inserts where the session now at flat preorder index `flat` sits, in its container; past the end
    /// (or `flat == sessions.count`) appends at workspace level.
    public mutating func insertSession(_ session: Session, atFlat flat: Int) {
        var remaining = max(0, flat)
        for index in items.indices {
            switch items[index] {
            case .session:
                if remaining == 0 {
                    items.insert(.session(session), at: index)
                    return
                }
                remaining -= 1
            case .folder(var folder):
                if remaining < folder.sessions.count {
                    folder.sessions.insert(session, at: remaining)
                    items[index] = .folder(folder)
                    return
                }
                remaining -= folder.sessions.count
            }
        }
        items.append(.session(session))
    }

    public mutating func appendSession(_ session: Session) {
        items.append(.session(session))
    }

    /// Inserts loose at a clamped `items` slot, which can sit before a folder where a flat index cannot.
    public mutating func insertSession(_ session: Session, atItem slot: Int) {
        items.insert(.session(session), at: max(0, min(slot, items.count)))
    }

    /// Inserts into the folder at a clamped slot; no-op on an unknown folder.
    public mutating func insertSession(_ session: Session, inFolder folderID: UUID, at slot: Int? = nil) {
        updateFolder(folderID) { folder in
            folder.sessions.insert(session, at: max(0, min(slot ?? folder.sessions.count, folder.sessions.count)))
        }
    }

    /// Inserts a folder at the clamped item slot, nil appends.
    public mutating func addFolder(_ folder: SessionFolder, at slot: Int? = nil) {
        items.insert(.folder(folder), at: max(0, min(slot ?? items.count, items.count)))
    }

    @discardableResult
    public mutating func removeFolder(id folderID: UUID) -> SessionFolder? {
        guard let index = itemIndex(ofFolder: folderID), case .folder(let folder) = items[index] else { return nil }
        items.remove(at: index)
        return folder
    }

    public mutating func renameFolder(_ folderID: UUID, to name: String) {
        updateFolder(folderID) { $0.name = name }
    }

    public mutating func setFolderExpanded(_ folderID: UUID, _ expanded: Bool) {
        updateFolder(folderID) { $0.isExpanded = expanded }
    }

    /// The `items` slot of the folder, or of the loose session.
    func itemIndex(ofFolder folderID: UUID) -> Int? {
        items.firstIndex { if case .folder(let folder) = $0 { folder.id == folderID } else { false } }
    }

    func itemIndex(ofLooseSession sessionID: UUID) -> Int? {
        items.firstIndex { if case .session(let session) = $0 { session.id == sessionID } else { false } }
    }

    private mutating func updateFolder(_ folderID: UUID, _ change: (inout SessionFolder) -> Void) {
        guard let index = itemIndex(ofFolder: folderID), case .folder(var folder) = items[index] else { return }
        change(&folder)
        items[index] = .folder(folder)
    }
}
