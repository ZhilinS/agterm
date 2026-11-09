import Foundation

// Fork: folder drop targets, kept out of upstream's SidebarDrop.swift.
extension SidebarDrop {
    struct Container {
        let workspace: UUID
        let folder: UUID?
        let count: Int
        let dropChildIndex: Int
    }

    /// A container's list index of its `slot`-th outline row: companions nest under their parent's row, so
    /// `companions` (one flag per list entry) are skipped. `onItemIndex` passes through.
    public static func listIndex(forSlot slot: Int, companions: [Bool]) -> Int {
        guard slot >= 0 else { return slot }
        let rows = companions.indices.filter { !companions[$0] }
        return slot < rows.count ? rows[slot] : companions.count
    }

    /// The inverse of `listIndex(forSlot:companions:)`: the outline slot in front of list entry `index`.
    public static func slot(forListIndex index: Int, companions: [Bool]) -> Int {
        guard index >= 0 else { return index }
        return companions.prefix(index).count { !$0 }
    }

    static func container(of target: SessionDropTarget, childIndex: Int) -> Container {
        switch target {
        case let .workspaceRow(id, sessionCount):
            Container(workspace: id, folder: nil, count: sessionCount, dropChildIndex: childIndex)
        case let .sessionRow(owner, folder, sessionIndex, sessionCount):
            Container(workspace: owner, folder: folder, count: sessionCount,
                      dropChildIndex: childIndex == onItemIndex ? sessionIndex + 1 : childIndex)
        case let .folderRow(owner, folder, sessionCount):
            Container(workspace: owner, folder: folder, count: sessionCount, dropChildIndex: childIndex)
        }
    }
}
