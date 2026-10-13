import agtermCore
import AppKit

/// Folder rows: the per-workspace child build from `Workspace.items` and folder expansion.
extension WorkspaceSidebar.Coordinator {
    /// The ordinary tree follows `items`, folders included; the flagged tree keeps its flat flagged rows.
    func childNodes(of workspace: Workspace, projected sessions: [Session], seen: inout Set<UUID>) -> [SidebarNode] {
        func sessionNode(_ session: Session) -> SidebarNode {
            seen.insert(session.id)
            return node(for: session.id, kind: .session)
        }
        guard store.sidebarMode == .tree else { return sessions.map(sessionNode) }
        var nodes: [SidebarNode] = []
        for item in workspace.items {
            switch item {
            case .session(let session):
                nodes.append(sessionNode(session))
            case .folder(let folder):
                seen.insert(folder.id)
                let folderNode = node(for: folder.id, kind: .folder)
                folderNode.children = folder.sessions.map(sessionNode)
                nodes.append(folderNode)
            }
        }
        return nodes
    }

    /// The workspace row, then the folder row, holding the session.
    func ancestors(ofSession sessionID: UUID) -> [SidebarNode] {
        for root in roots {
            if root.children.contains(where: { $0.id == sessionID }) { return [root] }
            if let folder = root.children.first(where: { $0.kind == .folder && $0.children.contains { $0.id == sessionID } }) {
                return [root, folder]
            }
        }
        return []
    }

    /// An outline forgets the expansion of rows it has not loaded, so a workspace that opens re-applies its
    /// folders' tracked state, view only.
    func restoreFolderExpansion(in workspaceNode: SidebarNode) {
        guard let outline = outlineView else { return }
        let wasSuppressed = suppressExpansionPersist
        suppressExpansionPersist = true
        for child in workspaceNode.children where child.kind == .folder && expandedWorkspaceIDs.contains(child.id) {
            outline.expandItem(child)
        }
        suppressExpansionPersist = wasSuppressed
    }

    func persistExpansion(of node: SidebarNode, expanded: Bool) {
        if node.kind == .folder {
            store.setFolderExpanded(node.id, expanded: expanded)
        } else {
            store.setWorkspaceExpanded(node.id, expanded: expanded)
        }
    }
}
