import Foundation
import Testing
@testable import agtermCore

/// Renders items as `a F(b c) d E()`, sessions by custom name, folders by name.
@MainActor func shape(_ workspace: Workspace) -> String {
    workspace.items.map { item in
        switch item {
        case .session(let session): session.customName ?? "?"
        case .folder(let folder): "\(folder.name)(\(folder.sessions.map { $0.customName ?? "?" }.joined(separator: " ")))"
        }
    }.joined(separator: " ")
}

@MainActor
struct WorkspaceItemsTests {
    private func session(_ name: String) -> Session { Session(initialCwd: "/", customName: name) }

    private func fixture() -> Workspace {
        Workspace(id: UUID(), name: "w", items: [
            .session(session("a")),
            .folder(SessionFolder(name: "F", sessions: [session("b"), session("c")])),
            .session(session("d")),
            .folder(SessionFolder(name: "E")),
        ])
    }

    @Test(arguments: [
        (0, "x a F(b c) d E()"),
        (1, "a F(x b c) d E()"),
        (2, "a F(b x c) d E()"),
        (3, "a F(b c) x d E()"),
        (4, "a F(b c) d E() x"),
        (9, "a F(b c) d E() x"),
    ])
    func insertAtFlatLandsInTheContainerOfTheSessionAtThatIndex(flat: Int, expected: String) {
        var workspace = fixture()
        workspace.insertSession(session("x"), atFlat: flat)
        #expect(shape(workspace) == expected)
    }

    @Test func sessionsIsThePreorder() {
        #expect(fixture().sessions.map(\.customName) == ["a", "b", "c", "d"])
    }

    @Test func removeSessionSearchesFoldersAndKeepsAnEmptiedFolder() {
        var workspace = fixture()
        let b = workspace.sessions[1], c = workspace.sessions[2], a = workspace.sessions[0]
        #expect(workspace.removeSession(id: b.id) === b)
        #expect(workspace.removeSession(id: c.id) === c)
        #expect(workspace.removeSession(id: a.id) === a)
        #expect(workspace.removeSession(id: UUID()) == nil)
        #expect(shape(workspace) == "F() d E()")
    }

    @Test func containerNamesTheOwningFolder() {
        let workspace = fixture()
        let folder = workspace.folders[0]
        #expect(workspace.container(ofSession: workspace.sessions[1].id) == folder.id)
        #expect(workspace.container(ofSession: workspace.sessions[0].id) == nil)
    }

    @Test func insertInFolderClampsAndIgnoresAnUnknownFolder() {
        var workspace = fixture()
        let folder = workspace.folders[0].id
        workspace.insertSession(session("x"), inFolder: folder, at: 0)
        workspace.insertSession(session("y"), inFolder: folder, at: 99)
        workspace.insertSession(session("z"), inFolder: UUID())
        #expect(shape(workspace) == "a F(x b c y) d E()")
    }

    @Test(arguments: [
        ("a", true, "a x F(b c) d E()"),
        ("a", false, "x a F(b c) d E()"),
        ("b", false, "a F(x b c) d E()"),
        ("c", true, "a F(b c x) d E()"),
        ("d", true, "a F(b c) d x E()"),
    ])
    func anchoredInsertStaysInTheAnchorsContainer(anchor: String, after: Bool, expected: String) throws {
        var workspace = fixture()
        let id = try #require(workspace.sessions.first { $0.customName == anchor }).id
        let inserted = workspace.insertSession(session("x"), anchor: after ? .after(id) : .before(id))
        #expect(inserted)
        #expect(shape(workspace) == expected)
    }

    @Test func aPlacementPutsASessionBackInItsFolderOrWhereTheFolderStood() throws {
        var workspace = fixture()
        let c = workspace.sessions[2]
        let placement = try #require(workspace.placement(ofSession: c.id))
        #expect(placement == SessionPlacement(folderID: workspace.folders[0].id, folderSlot: 1, itemIndex: 1))
        workspace.removeSession(id: c.id)
        workspace.insertSession(c, at: placement)
        #expect(shape(workspace) == "a F(b c) d E()")

        workspace.removeSession(id: c.id)
        let b = workspace.sessions[1]
        workspace.removeSession(id: b.id)
        workspace.removeFolder(id: workspace.folders[0].id)
        workspace.insertSession(c, at: placement)
        #expect(shape(workspace) == "a c d E()")
    }

    @Test func droppingAnEarlierMemberShiftsLaterPlacements() {
        let folder = UUID()
        let inFolder = SessionPlacement(folderID: folder, folderSlot: 2, itemIndex: 3)
        #expect(inFolder.shifted(afterDropping: SessionPlacement(folderID: folder, folderSlot: 0, itemIndex: 3))
            == SessionPlacement(folderID: folder, folderSlot: 1, itemIndex: 3))
        #expect(inFolder.shifted(afterDropping: SessionPlacement(itemIndex: 1))
            == SessionPlacement(folderID: folder, folderSlot: 2, itemIndex: 2))
        #expect(SessionPlacement(itemIndex: 1).shifted(afterDropping: SessionPlacement(itemIndex: 4)) == SessionPlacement(itemIndex: 1))
    }
}
