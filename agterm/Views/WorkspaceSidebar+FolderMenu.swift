import agtermCore
import AppKit

// Fork: kept out of upstream's WorkspaceSidebar+ContextMenu.swift.
extension WorkspaceSidebar.Coordinator {
    func folderMenu(_ node: SidebarNode) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, action) in [("New Session", #selector(menuNewSessionInFolder(_:))), ("Rename", #selector(menuRename(_:))),
                                ("Copy Name", #selector(menuCopyName(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = node
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let delete = NSMenuItem(title: "Delete Folder", action: #selector(menuDeleteFolder(_:)), keyEquivalent: "")
        delete.target = self
        delete.representedObject = node
        menu.addItem(delete)
        return menu
    }

    /// "Move to" with a `Workspaces` and a `Folders` section; a target that already holds every session is left out.
    func moveToItem(for sessionIDs: [UUID]) -> NSMenuItem? {
        let containers = sessionIDs.compactMap { id in store.containerLocation(ofSession: id).map { $0.folder ?? $0.workspace } }
        let workspaces = store.workspaces.filter { workspace in containers.contains { $0 != workspace.id } }
        let folders = store.workspaces.flatMap { workspace in
            workspace.folders.filter { folder in containers.contains { $0 != folder.id } }.map { (workspace, $0) }
        }
        guard !workspaces.isEmpty || !folders.isEmpty else { return nil }
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        func addItem(_ title: String, _ action: Selector, _ targetID: UUID) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = SessionBatchRequest(sessionIDs: sessionIDs, targetID: targetID)
            submenu.addItem(item)
        }
        if !workspaces.isEmpty {
            submenu.addItem(.sectionHeader(title: "Workspaces"))
            for workspace in workspaces { addItem(workspace.name, #selector(menuMove(_:)), workspace.id) }
        }
        if !folders.isEmpty {
            if !workspaces.isEmpty { submenu.addItem(.separator()) }
            submenu.addItem(.sectionHeader(title: "Folders"))
            for (workspace, folder) in folders {
                addItem("\(folder.name) — \(workspace.name)", #selector(menuMoveToFolder(_:)), folder.id)
            }
        }
        let moveTo = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        moveTo.submenu = submenu
        return moveTo
    }

    @objc func menuMoveToFolder(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? SessionBatchRequest, let folderID = request.targetID else { return }
        store.moveSessions(request.sessionIDs, toFolder: folderID)
    }

    @objc func menuNewFolderFromSessions(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? SessionBatchRequest, let workspaceID = request.targetID,
              let folder = store.addFolder(toWorkspace: workspaceID, name: "New Folder", containing: request.sessionIDs) else { return }
        beginRenamingNewFolder(folder.id)
    }

    @objc func menuNewFolder(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? SidebarNode,
              let folder = store.addFolder(toWorkspace: node.id, name: "New Folder") else { return }
        beginRenamingNewFolder(folder.id)
    }

    /// The store change reaches the outline on SwiftUI's next update, so rebuild now to have a row to edit.
    func beginRenamingNewFolder(_ folderID: UUID) {
        reconcile()
        guard let outline = outlineView, let node = cachedNode(folderID),
              let workspace = store.workspace(forFolder: folderID), let owner = cachedNode(workspace.id) else { return }
        if !outline.isItemExpanded(owner) { outline.expandItem(owner) }
        DispatchQueue.main.async { [weak self] in self?.renameController.beginEditing(node: node) }
    }

    @objc func menuNewSessionInFolder(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? SidebarNode, let workspace = store.workspace(forFolder: node.id) else { return }
        addSession(toWorkspace: workspace.id, cwd: actions.resolvedNewSessionCwd(), folder: node.id)
    }

    @objc func menuDeleteFolder(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? SidebarNode else { return }
        actions.deleteFolder(node.id, in: store)
    }

    func collapseSpringLoaded(keeping count: Int) {
        while springLoadedIDs.count > count {
            let id = springLoadedIDs.removeLast()
            guard let outlineView, let node = cachedNode(id), outlineView.isItemExpanded(node) else { continue }
            suppressExpansionPersist = true
            outlineView.collapseItem(node)
            suppressExpansionPersist = false
        }
    }

    func cancelPendingSpringLoad() {
        pendingSpringLoadedExpansion?.workItem.cancel()
        pendingSpringLoadedExpansion = nil
    }
}
