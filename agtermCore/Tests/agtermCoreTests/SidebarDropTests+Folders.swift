import Foundation
import Testing
@testable import agtermCore

// Fork: kept out of upstream's SidebarDropTests.swift.
extension SidebarDropTests {
    private static let folderWsA = UUID()
    private static let folderWsB = UUID()
    private static let folder = UUID()

    private func batch(_ source: SidebarDrop.SessionSource, _ target: SidebarDrop.SessionDropTarget,
                       _ childIndex: Int) -> SidebarDrop.SessionResolution? {
        SidebarDrop.resolveSessions(sources: [source], target: target, childIndex: childIndex)
    }

    private func into(_ workspace: UUID, folder: UUID? = folder, _ dropChildIndex: Int, _ destination: Int)
        -> SidebarDrop.SessionResolution {
        SidebarDrop.SessionResolution(workspace: workspace, folder: folder, dropChildIndex: dropChildIndex,
                                      destination: destination)
    }

    @Test func dropOnAFolderRowAppendsToIt() {
        let move = batch(.init(workspace: Self.folderWsA, index: 0), .folderRow(workspace: Self.folderWsA, folder: Self.folder, sessionCount: 2),
                         SidebarDrop.onItemIndex)
        #expect(move == into(Self.folderWsA, SidebarDrop.onItemIndex, 2))
    }

    @Test func downwardMoveInsideAFolderAppliesMinusOne() {
        let move = batch(.init(workspace: Self.folderWsA, folder: Self.folder, index: 0),
                         .folderRow(workspace: Self.folderWsA, folder: Self.folder, sessionCount: 3), 2)
        #expect(move == into(Self.folderWsA, 2, 1))
    }

    @Test func dropOnASessionRowInsideAFolderLandsAfterItThere() {
        let move = batch(.init(workspace: Self.folderWsA, index: 0),
                         .sessionRow(workspace: Self.folderWsA, folder: Self.folder, sessionIndex: 1, sessionCount: 2), SidebarDrop.onItemIndex)
        #expect(move == into(Self.folderWsA, 2, 2))
    }

    @Test func dragOutOfAFolderTakesTheWorkspaceSlotUnadjusted() {
        let move = batch(.init(workspace: Self.folderWsA, folder: Self.folder, index: 0),
                         .workspaceRow(id: Self.folderWsA, sessionCount: 3), 1)
        #expect(move == into(Self.folderWsA, folder: nil, 1, 1))
    }

    @Test(arguments: [1, 2])
    func droppingBackIntoTheSameFolderSlotIsANoOp(childIndex: Int) {
        #expect(batch(.init(workspace: Self.folderWsA, folder: Self.folder, index: 1),
                      .folderRow(workspace: Self.folderWsA, folder: Self.folder, sessionCount: 2), childIndex) == nil)
    }

    @Test func crossWorkspaceDropIntoAFolderKeepsTheIndex() {
        let move = batch(.init(workspace: Self.folderWsB, index: 0),
                         .folderRow(workspace: Self.folderWsA, folder: Self.folder, sessionCount: 1), 0)
        #expect(move == into(Self.folderWsA, 0, 0))
    }
}
