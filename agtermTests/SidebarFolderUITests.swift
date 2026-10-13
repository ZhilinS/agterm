import AppKit
import XCTest
@testable import agterm
import agtermCore

@MainActor
final class SidebarFolderUITests: XCTestCase {
    private var stateDir: URL!
    private var library: WindowLibrary!
    private var actions: AppActions!
    private var window: NSWindow!
    private var outline: SidebarOutlineView!
    private var coordinator: WorkspaceSidebar.Coordinator!
    private var store: AppStore!
    private var workspace: UUID!
    private var sessions: [Session] = []

    override func setUp() async throws {
        try await super.setUp()
        stateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agterm-folder-tests-\(UUID().uuidString)", isDirectory: true)
        library = WindowLibrary(directory: stateDir)
        actions = AppActions(library: library)
        store = try XCTUnwrap(library.activeStore)
        let first = try XCTUnwrap(store.activeSession)
        workspace = try XCTUnwrap(store.workspaces.first).id
        sessions = try [first] + ["/tmp/b", "/tmp/c"].map { try XCTUnwrap(store.addSession(toWorkspace: workspace, cwd: $0)) }
        store.selectSession(first.id)
        buildSidebar()
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        outline = nil
        coordinator = nil
        actions = nil
        store = nil
        library = nil
        try? FileManager.default.removeItem(at: stateDir)
        stateDir = nil
        try await super.tearDown()
    }

    func testNewFolderFromSessionRowWrapsItAndRenamesInline() throws {
        try perform("New Folder", onRowOf: sessions[1].id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let folder = try XCTUnwrap(store.workspaces.first?.folders.first)
        XCTAssertEqual(folder.sessions.map(\.id), [sessions[1].id])
        let folderRow = try XCTUnwrap(row(of: folder.id))
        XCTAssertEqual(outline.level(forRow: folderRow), 1)
        XCTAssertEqual(row(of: sessions[1].id), folderRow + 1)
        XCTAssertTrue(coordinator.renameController.isEditing, "a new folder opens in inline rename")

        let cell = try XCTUnwrap(outline.view(atColumn: 0, row: folderRow, makeIfNecessary: false) as? NSTableCellView)
        let field = try XCTUnwrap(cell.textField)
        field.stringValue = "feature"
        window.makeFirstResponder(nil)
        XCTAssertEqual(store.folder(withID: folder.id)?.name, "feature")
        XCTAssertEqual(field.accessibilityIdentifier(), "folder-row")
    }

    func testDropIntoAndOutOfAFolder() throws {
        let folder = try XCTUnwrap(store.addFolder(toWorkspace: workspace, name: "F", containing: [sessions[0].id]))
        coordinator.reconcile()
        let folderNode = try XCTUnwrap(node(folder.id))
        XCTAssertTrue(drop([sessions[2].id], on: folderNode, childIndex: SidebarDrop.onItemIndex))
        XCTAssertEqual(store.folder(withID: folder.id)?.sessions.map(\.id), [sessions[0].id, sessions[2].id])

        coordinator.reconcile()
        let workspaceNode = try XCTUnwrap(node(workspace))
        XCTAssertTrue(drop([sessions[0].id], on: workspaceNode, childIndex: 0))
        XCTAssertEqual(store.folder(withID: folder.id)?.sessions.map(\.id), [sessions[2].id])
        XCTAssertEqual(store.workspaces.first?.itemShape, [[sessions[0].id], [folder.id, sessions[2].id], [sessions[1].id]])
    }

    func testDeleteFolderClosesItsSessionsAfterConfirming() throws {
        let folder = try XCTUnwrap(store.addFolder(toWorkspace: workspace, name: "F", containing: [sessions[1].id, sessions[2].id]))
        var asked: (String, Int)?
        actions.deleteFolder(folder.id, in: store) { name, count in
            asked = (name, count)
            return false
        }
        XCTAssertNotNil(store.folder(withID: folder.id), "a declined confirm keeps the folder")
        actions.deleteFolder(folder.id, in: store) { name, count in
            asked = (name, count)
            return true
        }
        XCTAssertEqual(asked?.0, "F")
        XCTAssertEqual(asked?.1, 2)
        XCTAssertNil(store.folder(withID: folder.id))
        XCTAssertEqual(store.workspaces.first?.sessions.map(\.id), [sessions[0].id])

        let empty = try XCTUnwrap(store.addFolder(toWorkspace: workspace, name: "E"))
        actions.deleteFolder(empty.id, in: store) { _, _ in
            XCTFail("an empty folder deletes without confirming")
            return false
        }
        XCTAssertNil(store.folder(withID: empty.id))
    }

    func testFolderExpansionPersistsAndSurvivesRebuild() throws {
        let folder = try XCTUnwrap(store.addFolder(toWorkspace: workspace, name: "F", containing: [sessions[0].id]))
        coordinator.reconcile()
        let folderNode = try XCTUnwrap(node(folder.id))
        XCTAssertTrue(outline.isItemExpanded(folderNode))
        outline.collapseItem(folderNode)
        XCTAssertEqual(store.folder(withID: folder.id)?.isExpanded, false)
        coordinator.rebuildAndReload()
        XCTAssertFalse(outline.isItemExpanded(folderNode), "a rebuild keeps a collapsed folder collapsed")
        outline.expandItem(folderNode)
        XCTAssertEqual(store.folder(withID: folder.id)?.isExpanded, true)
    }

    func testSpringLoadingAFolderKeepsItsSpringOpenedWorkspaceOpen() throws {
        let folder = try XCTUnwrap(store.addFolder(toWorkspace: workspace, name: "F", containing: [sessions[1].id]))
        let other = store.addWorkspace(name: "other")
        let dragged = try XCTUnwrap(store.addSession(toWorkspace: other.id, cwd: "/tmp/d"))
        try collapse(folder.id, then: workspace)
        let workspaceNode = try XCTUnwrap(node(workspace))
        let info = sessionDrag([dragged.id])

        XCTAssertEqual(validate(info, on: workspaceNode), .move)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertTrue(outline.isItemExpanded(workspaceNode))
        let folderNode = try XCTUnwrap(node(folder.id))
        XCTAssertEqual(validate(info, on: folderNode), .move)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertTrue(outline.isItemExpanded(workspaceNode), "hovering the folder keeps its workspace open")
        XCTAssertTrue(outline.isItemExpanded(folderNode))

        XCTAssertEqual(coordinator.springLoadedIDs, [workspace, folder.id])
        coordinator.finishDraggingSequence()
        XCTAssertEqual(coordinator.springLoadedIDs, [])
        XCTAssertFalse(outline.isItemExpanded(folderNode))
        XCTAssertFalse(outline.isItemExpanded(workspaceNode))
        XCTAssertEqual(store.workspaces.first?.isExpanded, false)
        XCTAssertEqual(store.folder(withID: folder.id)?.isExpanded, false)
    }

    func testSelectingASessionInACollapsedFolderRevealsBothRows() throws {
        let folder = try XCTUnwrap(store.addFolder(toWorkspace: workspace, name: "F", containing: [sessions[1].id]))
        try collapse(folder.id, then: workspace)
        store.selectSession(sessions[1].id)
        coordinator.syncSelection()
        XCTAssertTrue(outline.isItemExpanded(try XCTUnwrap(node(workspace))))
        XCTAssertTrue(outline.isItemExpanded(try XCTUnwrap(node(folder.id))))
        XCTAssertEqual(outline.selectedRow, row(of: sessions[1].id))
        XCTAssertEqual(store.folder(withID: folder.id)?.isExpanded, false, "a reveal does not persist")
        XCTAssertEqual(store.workspaces.first?.isExpanded, false)
    }

    func testFlaggedModeRoundTripKeepsFolderExpansion() throws {
        let open = try XCTUnwrap(store.addFolder(toWorkspace: workspace, name: "open", containing: [sessions[1].id]))
        let shut = try XCTUnwrap(store.addFolder(toWorkspace: workspace, name: "shut", containing: [sessions[2].id]))
        coordinator.reconcile()
        outline.collapseItem(try XCTUnwrap(node(shut.id)))
        store.setSidebarMode(.flagged)
        coordinator.reconcile()
        XCTAssertNil(node(open.id))
        store.setSidebarMode(.tree)
        coordinator.reconcile()
        XCTAssertTrue(outline.isItemExpanded(try XCTUnwrap(node(open.id))))
        XCTAssertFalse(outline.isItemExpanded(try XCTUnwrap(node(shut.id))))
    }

    private func collapse(_ folderID: UUID, then workspaceID: UUID) throws {
        coordinator.reconcile()
        outline.collapseItem(try XCTUnwrap(node(folderID)))
        let workspaceNode = try XCTUnwrap(node(workspaceID))
        outline.collapseItem(workspaceNode)
        XCTAssertFalse(outline.isItemExpanded(workspaceNode))
        XCTAssertNil(node(folderID), "the folder row is hidden inside the collapsed workspace")
    }

    private func node(_ id: UUID) -> SidebarNode? {
        row(of: id).flatMap { outline.item(atRow: $0) as? SidebarNode }
    }

    private func row(of id: UUID) -> Int? {
        (0..<outline.numberOfRows).first { (outline.item(atRow: $0) as? SidebarNode)?.id == id }
    }

    private func perform(_ title: String, onRowOf id: UUID) throws {
        let row = try XCTUnwrap(row(of: id))
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let item = try XCTUnwrap(coordinator.menu(forRow: row)?.items.first { $0.title == title })
        NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
    }

    private func sessionDrag(_ ids: [UUID]) -> FakeSessionDrag {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("agterm-folder-tests-\(UUID().uuidString)"))
        addTeardownBlock { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString(ids.map(\.uuidString).joined(separator: "\n"), forType: sessionPasteboardType)
        return FakeSessionDrag(pasteboard, over: outline)
    }

    private func validate(_ info: FakeSessionDrag, on node: SidebarNode, childIndex: Int = SidebarDrop.onItemIndex) -> NSDragOperation {
        coordinator.outlineView(outline, validateDrop: info, proposedItem: node, proposedChildIndex: childIndex)
    }

    private func drop(_ ids: [UUID], on node: SidebarNode, childIndex: Int) -> Bool {
        let info = sessionDrag(ids)
        guard validate(info, on: node, childIndex: childIndex) == .move else { return false }
        return coordinator.outlineView(outline, acceptDrop: info, item: node, childIndex: childIndex)
    }

    private func buildSidebar() {
        outline = SidebarOutlineView()
        coordinator = WorkspaceSidebar.Coordinator(store: store, actions: actions)
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.headerView = nil
        outline.rowSizeStyle = .custom
        outline.rowHeight = AppSettings.sidebarRowHeight(fontSize: GhosttyApp.shared.sidebarFontSize)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.allowsMultipleSelection = true

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        scroll.documentView = outline
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll

        coordinator.outlineView = outline
        coordinator.renameController.outlineView = outline
        coordinator.seedExpansionFromModel()
        coordinator.reconcile()
    }
}

@MainActor
private final class FakeSessionDrag: NSObject, @preconcurrency NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow?
    let draggingLocation: NSPoint

    init(_ pasteboard: NSPasteboard, over view: NSView) {
        draggingPasteboard = pasteboard
        draggingDestinationWindow = view.window
        draggingLocation = .zero
    }

    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to _: NSPoint) {}
    func enumerateDraggingItems(options _: NSDraggingItemEnumerationOptions = [], for _: NSView?, classes _: [AnyClass],
                                searchOptions _: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using _: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}
