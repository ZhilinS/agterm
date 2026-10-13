import Foundation
import Testing
@testable import agtermCore

@MainActor
struct SnapshotFolderTests {
    @Test func foldersRoundTripThroughRestore() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "w")
        let a = try #require(store.addSession(toWorkspace: ws.id, cwd: "/", name: "a"))
        _ = store.addSession(toWorkspace: ws.id, cwd: "/", name: "b")
        let folder = try #require(store.addFolder(toWorkspace: ws.id, name: "F", containing: [a.id]))
        store.setFolderExpanded(folder.id, expanded: false)
        store.addFolder(toWorkspace: ws.id, name: "E")

        let data = try JSONEncoder().encode(store.snapshot())
        let restored = makeStore()
        restored.restore(from: try JSONDecoder().decode(Snapshot.self, from: data))

        let workspace = try #require(restored.workspaces.first { $0.id == ws.id })
        #expect(shape(workspace) == "F(a) b E()")
        #expect(workspace.folders.map(\.isExpanded) == [false, true])
        #expect(workspace.folders.first?.id == folder.id)
    }

    @Test func itemsEncodeAsSingleKeyObjectsWithoutASessionsKey() throws {
        let session = SessionSnapshot(id: UUID(), customName: nil, cwd: "/a")
        let workspace = WorkspaceSnapshot(id: UUID(), name: "w", items: [
            .session(session),
            .folder(FolderSnapshot(id: UUID(), name: "F", sessions: [session])),
        ])
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        #expect(json["sessions"] == nil)
        let items = try #require(json["items"] as? [[String: Any]])
        #expect(items.map { $0.keys.sorted() } == [["session"], ["folder"]])
        let folder = try #require(items[1]["folder"] as? [String: Any])
        #expect(folder.keys.sorted() == ["id", "name", "sessions"])
    }

    @Test func folderCollapsedIsLossy() throws {
        let json = #"{ "id": "\#(UUID().uuidString)", "name": "F", "collapsed": "yes", "sessions": [] }"#
        let folder = try JSONDecoder().decode(FolderSnapshot.self, from: Data(json.utf8))
        #expect(folder.collapsed == nil)
    }

    @Test func anUpstreamSessionsSnapshotLoadsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("agterm-folders-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = #"{ "version": 1, "workspaces": [ { "id": "\#(UUID().uuidString)", "name": "w", "sessions": [] } ] }"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("workspaces.json"))
        #expect(PersistenceStore(directory: directory).load().workspaces.isEmpty)
    }
}
