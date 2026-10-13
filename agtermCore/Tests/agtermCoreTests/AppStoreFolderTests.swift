import Foundation
import Testing
@testable import agtermCore

@MainActor
struct AppStoreFolderTests {
    private func fixture() throws -> (AppStore, UUID, [Session]) {
        let store = makeStore()
        let workspace = store.addWorkspace(name: "w")
        let sessions = try ["a", "b", "c"].map { try #require(store.addSession(toWorkspace: workspace.id, cwd: "/", name: $0)) }
        return (store, workspace.id, sessions)
    }

    private func shapeOf(_ store: AppStore, _ id: UUID) -> String {
        shape(store.workspaces.first { $0.id == id }!)
    }

    @Test func newFolderTakesTheFirstSelectedSlotAndTheSelectionInTreeOrder() throws {
        let (store, ws, s) = try fixture()
        let folder = try #require(store.addFolder(toWorkspace: ws, name: " F ", containing: [s[2].id, s[0].id]))
        #expect(shapeOf(store, ws) == "F(a c) b")
        #expect(folder.sessions.map(\.id) == [s[0].id, s[2].id])
    }

    @Test func newFolderFromAFolderMemberLandsAfterThatFolder() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id, s[1].id])
        store.addFolder(toWorkspace: ws, name: "G", containing: [s[1].id])
        #expect(shapeOf(store, ws) == "F(a) G(b) c")
    }

    @Test func newFolderWithoutSessionsAppendsEmpty() throws {
        let (store, ws, _) = try fixture()
        store.addFolder(toWorkspace: ws, name: "")
        #expect(shapeOf(store, ws) == "a b c folder()")
        #expect(store.addFolder(toWorkspace: UUID(), name: "x") == nil)
    }

    @Test func renameAndExpansionPersist() throws {
        let (store, ws, s) = try fixture()
        let folder = try #require(store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id]))
        store.renameFolder(folder.id, to: "  ")
        store.renameFolder(folder.id, to: " G ")
        store.setFolderExpanded(folder.id, expanded: false)
        #expect(store.folder(withID: folder.id)?.name == "G")
        guard case .folder(let saved) = store.snapshot().workspaces.first(where: { $0.id == ws })?.items.first else {
            Issue.record("folder missing from snapshot")
            return
        }
        #expect(saved.name == "G" && saved.collapsed == true)
    }

    @Test func deleteFolderRemovesOnlyAnEmptyOne() throws {
        let (store, ws, s) = try fixture()
        let full = try #require(store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id]))
        let empty = try #require(store.addFolder(toWorkspace: ws, name: "E"))
        store.deleteFolder(full.id)
        store.deleteFolder(empty.id)
        #expect(shapeOf(store, ws) == "F(a) b c")
    }

    @Test func moveIntoAFolderUsesThePostRemovalIndex() throws {
        let (store, ws, s) = try fixture()
        let folder = try #require(store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id, s[1].id]))
        #expect(store.moveSessions([s[0].id], toFolder: folder.id, at: 1) == 1)
        #expect(shapeOf(store, ws) == "F(b a) c")
        store.moveSessions([s[2].id], toFolder: folder.id, at: 0)
        #expect(shapeOf(store, ws) == "F(c b a)")
    }

    @Test func moveAcrossWorkspacesLandsInsideTheFolder() throws {
        let (store, ws, s) = try fixture()
        let other = store.addWorkspace(name: "o")
        let d = try #require(store.addSession(toWorkspace: other.id, cwd: "/", name: "d"))
        let folder = try #require(store.addFolder(toWorkspace: other.id, name: "F", containing: [d.id]))
        #expect(store.moveSessions([s[1].id, s[0].id], toFolder: folder.id) == 2)
        #expect(shapeOf(store, ws) == "c")
        #expect(shapeOf(store, other.id) == "F(d a b)")
    }

    @Test func moveToTheOwnWorkspaceTakesAFolderMemberOutLoose() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id, s[1].id])
        #expect(store.moveSessions([s[0].id, s[2].id], toWorkspace: ws) == 1)
        #expect(shapeOf(store, ws) == "F(b) c a")
        store.moveSessions([s[1].id], toWorkspace: ws, at: 0)
        #expect(shapeOf(store, ws) == "F() b c a")
    }

    @Test func treeReportsTheFolderName() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[1].id])
        let nodes = store.controlTree().workspaces.first { $0.id == ws.uuidString }?.sessions
        #expect(nodes?.map(\.folder) == [nil, "F", nil])
    }

    @Test func itemSlotMoveCanLandBeforeAFolder() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id])
        #expect(store.moveSessions([s[2].id], toWorkspace: ws, atItem: 0) == 1)
        #expect(shapeOf(store, ws) == "c F(a) b")
        #expect(store.containerLocation(ofSession: s[0].id)?.index == 0)
        #expect(store.containerLocation(ofSession: s[1].id).map { [$0.index, $0.count] } == [2, 3])
    }
}
