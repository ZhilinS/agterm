import Foundation
import Testing
@testable import agtermCore

@MainActor
struct AppStoreFolderCompanionTests {
    private func fixture() throws -> (AppStore, UUID, [Session]) {
        let store = makeStore()
        let workspace = store.addWorkspace(name: "w")
        let sessions = try ["a", "b", "c"].map { try #require(store.addSession(toWorkspace: workspace.id, cwd: "/", name: $0)) }
        return (store, workspace.id, sessions)
    }

    private func shapeOf(_ store: AppStore, _ id: UUID) -> String {
        shape(store.workspaces.first { $0.id == id }!)
    }

    @discardableResult
    private func companion(_ name: String, of parent: Session, in store: AppStore) throws -> Session {
        try store.addCompanion(to: parent.id, options: CompanionOptions(name: name)).get()
    }

    @Test func aCompanionOfAFolderMemberJoinsItsFolder() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id])
        let x = try companion("x", of: s[0], in: store)
        #expect(shapeOf(store, ws) == "F(a x) b c")
        #expect(store.companions(of: s[0].id).map(\.id) == [x.id])
    }

    @Test func aFolderMadeFromAParentTakesItsCompanions() throws {
        let (store, ws, s) = try fixture()
        try companion("x", of: s[1], in: store)
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[1].id])
        #expect(shapeOf(store, ws) == "a F(b x) c")
    }

    @Test func movingAParentIntoAFolderCarriesItsCompanions() throws {
        let (store, ws, s) = try fixture()
        try companion("x", of: s[0], in: store)
        let folder = try #require(store.addFolder(toWorkspace: ws, name: "F", containing: [s[2].id]))
        #expect(store.moveSessions([s[0].id], toFolder: folder.id) == 2)
        #expect(shapeOf(store, ws) == "b F(c a x)")
    }

    @Test func movingAParentOutOfItsFolderCarriesItsCompanions() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id, s[1].id])
        try companion("x", of: s[0], in: store)
        #expect(store.moveSession(s[0].id, toWorkspace: ws))
        #expect(shapeOf(store, ws) == "F(b) c a x")
    }

    @Test func aSessionAddedAfterAParentLandsPastItsGroup() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id])
        try companion("x", of: s[0], in: store)
        store.addSession(toWorkspace: ws, cwd: "/", name: "n", anchor: .after(s[0].id))
        #expect(shapeOf(store, ws) == "F(a x n) b c")
    }

    @Test func aCompanionReordersOnlyAmongItsSiblings() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id])
        let x = try companion("x", of: s[0], in: store)
        let y = try companion("y", of: s[0], in: store)
        #expect(store.moveSessions([y.id], anchor: .before(x.id)) == 1)
        #expect(shapeOf(store, ws) == "F(a y x) b c")
        #expect(store.moveSessions([y.id], anchor: .after(s[1].id)) == 0)
        #expect(shapeOf(store, ws) == "F(a y x) b c")
    }

    @Test func movingAParentBesideItsOwnCompanionKeepsTheGroup() throws {
        let (store, ws, s) = try fixture()
        let x = try companion("x", of: s[0], in: store)
        #expect(store.moveSessions([s[0].id], anchor: .after(x.id)) == 0)
        #expect(shapeOf(store, ws) == "a x b c")
    }

    @Test func movingAGroupBeforeAnotherParentsCompanionKeepsItsOrder() throws {
        let (store, ws, s) = try fixture()
        let x = try companion("x", of: s[0], in: store)
        try companion("y", of: s[1], in: store)
        #expect(store.moveSessions([s[1].id], anchor: .before(x.id)) == 2)
        #expect(shapeOf(store, ws) == "a x b y c")
        #expect(store.companions(of: s[0].id).map(\.id) == [x.id])
    }

    @Test func reorderingAGroupDownStaysInItsFolder() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id, s[1].id, s[2].id])
        try companion("x", of: s[0], in: store)
        store.reorderSession(s[0].id, .down)
        #expect(shapeOf(store, ws) == "F(b a x c)")
    }

    @Test func anEmptyFolderStaysOutOfAGroupFormedBesideIt() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "w").id
        let a = try #require(store.addSession(toWorkspace: ws, cwd: "/", name: "a"))
        store.addFolder(toWorkspace: ws, name: "F")
        try companion("x", of: a, in: store)
        #expect(shapeOf(store, ws) == "a x F()")
    }

    @Test func reopeningIntoAFolderLandsPastAGroupFormedSince() throws {
        let (store, recent, _) = makeStoreWithRecentClosed()
        let ws = store.addWorkspace(name: "w").id
        let s = try ["a", "b"].map { try #require(store.addSession(toWorkspace: ws, cwd: "/", name: $0)) }
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[0].id, s[1].id])
        store.closeSession(s[1].id)
        try companion("x", of: s[0], in: store)
        let item = try #require(recent.load().first { $0.session?.snapshot.id == s[1].id })
        #expect(store.restoreRecentClosed(item))
        #expect(shapeOf(store, ws) == "F(a x b)")
    }

    @Test func outlineSlotsSkipCompanionRows() {
        let flags = [false, true, true, false, false]
        #expect(SidebarDrop.listIndex(forSlot: 1, companions: flags) == 3)
        #expect(SidebarDrop.listIndex(forSlot: 3, companions: flags) == 5)
        #expect(SidebarDrop.slot(forListIndex: 3, companions: flags) == 1)
        #expect(SidebarDrop.slot(forListIndex: 5, companions: flags) == 3)
        #expect(SidebarDrop.listIndex(forSlot: SidebarDrop.onItemIndex, companions: flags) == SidebarDrop.onItemIndex)
    }

    @Test func aCompanionInAFolderSurvivesARestore() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[1].id])
        let x = try companion("x", of: s[1], in: store)
        let restored = makeStore()
        restored.restore(from: store.snapshot())
        #expect(shapeOf(restored, ws) == "a F(b x) c")
        #expect(restored.companions(of: s[1].id).map(\.id) == [x.id])
    }

    @Test(arguments: [false, true])
    func reopeningAClosedFolderParentBringsTheGroupBack(softClose: Bool) throws {
        let (store, recent, _) = makeStoreWithRecentClosed()
        let ws = store.addWorkspace(name: "w").id
        let s = try ["a", "b", "c"].map { try #require(store.addSession(toWorkspace: ws, cwd: "/", name: $0)) }
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[1].id])
        try companion("x", of: s[1], in: store)
        if softClose {
            store.softCloseSession(s[1].id)
            store.finalizePendingClose(ofSession: s[1].id)
        } else {
            store.closeSession(s[1].id)
        }
        #expect(shapeOf(store, ws) == "a c")
        let item = try #require(recent.load().first { $0.session?.snapshot.id == s[1].id })
        #expect(store.restoreRecentClosed(item))
        #expect(shapeOf(store, ws) == "a F(b x) c")
    }

    @Test func undoingAFolderParentsCloseBringsTheGroupBack() throws {
        let (store, ws, s) = try fixture()
        store.addFolder(toWorkspace: ws, name: "F", containing: [s[1].id])
        try companion("x", of: s[1], in: store)
        store.softCloseSession(s[1].id)
        #expect(shapeOf(store, ws) == "a c")
        #expect(store.undoPendingClose())
        #expect(shapeOf(store, ws) == "a F(b x) c")
    }
}
