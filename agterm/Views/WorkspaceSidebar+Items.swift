import agtermCore
import AppKit

/// Folder rows: the per-workspace child build from `Workspace.items` and folder expansion.
extension WorkspaceSidebar.Coordinator {
    /// The ordinary tree follows `items`, folders included, and nests companions under their parent's row.
    func childNodes(of workspace: Workspace, projected sessions: [Session], seen: inout Set<UUID>) -> [SidebarNode] {
        seen.formUnion(sessions.map(\.id))
        guard store.sidebarMode == .tree else { return sessionNodes(for: sessions) }
        var nodes: [SidebarNode] = []
        var loose: [Session] = []
        for item in workspace.items {
            switch item {
            case .session(let session):
                loose.append(session)
            case .folder(let folder):
                nodes += sessionNodes(for: loose)
                loose = []
                seen.insert(folder.id)
                let folderNode = node(for: folder.id, kind: .folder)
                folderNode.children = sessionNodes(for: folder.sessions)
                nodes.append(folderNode)
            }
        }
        return nodes + sessionNodes(for: loose)
    }

    /// The rows holding the session, outermost first: its workspace, its folder, its parent.
    func ancestors(ofSession sessionID: UUID) -> [SidebarNode] {
        func path(_ nodes: [SidebarNode]) -> [SidebarNode]? {
            for node in nodes {
                if node.children.contains(where: { $0.id == sessionID }) { return [node] }
                if let below = path(node.children) { return [node] + below }
            }
            return nil
        }
        return path(roots) ?? []
    }

    /// An outline forgets the expansion of rows it has not loaded, so a workspace that opens re-applies its
    /// folders' tracked state, view only.
    func restoreFolderExpansion(in workspaceNode: SidebarNode) {
        guard let outline = outlineView else { return }
        let wasSuppressed = suppressExpansionPersist
        suppressExpansionPersist = true
        for child in workspaceNode.children where child.kind == .folder && expandedWorkspaceIDs.contains(child.id) {
            outline.expandItem(child)
            applyParentExpansion(under: child)
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
