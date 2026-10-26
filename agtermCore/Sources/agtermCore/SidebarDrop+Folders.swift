import Foundation

// Fork: folder drop targets, kept out of upstream's SidebarDrop.swift.
extension SidebarDrop {
    struct Container {
        let workspace: UUID
        let folder: UUID?
        let count: Int
        let dropChildIndex: Int
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
