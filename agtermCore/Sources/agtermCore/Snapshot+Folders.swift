import Foundation

// Fork: session folders in the snapshot, kept out of upstream's Snapshot.swift.

/// `{"session": …}` or `{"folder": …}`.
public enum WorkspaceItemSnapshot: Codable, Equatable, Sendable {
    case session(SessionSnapshot)
    case folder(FolderSnapshot)

    enum CodingKeys: String, CodingKey {
        case session, folder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let session = try c.decodeIfPresent(SessionSnapshot.self, forKey: .session) {
            self = .session(session)
        } else {
            self = .folder(try c.decode(FolderSnapshot.self, forKey: .folder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .session(let session): try c.encode(session, forKey: .session)
        case .folder(let folder): try c.encode(folder, forKey: .folder)
        }
    }
}

public struct FolderSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Inverse of `isExpanded`, lossy and only written when true, like the workspace one.
    public var collapsed: Bool?
    public var sessions: [SessionSnapshot]

    public init(id: UUID, name: String, collapsed: Bool? = nil, sessions: [SessionSnapshot]) {
        self.id = id
        self.name = name
        self.collapsed = collapsed
        self.sessions = sessions
    }

    enum CodingKeys: String, CodingKey {
        case id, name, collapsed, sessions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        collapsed = (try? c.decodeIfPresent(Bool.self, forKey: .collapsed)) ?? nil
        sessions = try c.decode([SessionSnapshot].self, forKey: .sessions)
    }
}

extension WorkspaceSnapshot {
    /// Loose sessions only.
    public init(id: UUID, name: String, sessions: [SessionSnapshot], collapsed: Bool? = nil) {
        self.init(id: id, name: name, items: sessions.map(WorkspaceItemSnapshot.session), collapsed: collapsed)
    }

    /// Preorder of `items`, folder sessions in place.
    public var sessions: [SessionSnapshot] {
        items.flatMap { item -> [SessionSnapshot] in
            switch item {
            case .session(let session): [session]
            case .folder(let folder): folder.sessions
            }
        }
    }

    public mutating func mapSessions(_ change: (inout SessionSnapshot) -> Void) {
        for index in items.indices {
            switch items[index] {
            case .session(var session):
                change(&session)
                items[index] = .session(session)
            case .folder(var folder):
                for slot in folder.sessions.indices { change(&folder.sessions[slot]) }
                items[index] = .folder(folder)
            }
        }
    }
}
