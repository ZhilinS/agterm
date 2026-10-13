import AppKit
import XCTest
@testable import agterm
import agtermCore

/// Hosted coverage for Control-click as the secondary click on sidebar rows (issue #668), and for the plain
/// row-click toggle. CI does not run the UI tests that drive a real click, so this sends a Control-click
/// straight to `mouseDown` and checks which menu was requested; `SidebarUITests` owns the menu actually opening.
@MainActor
final class SidebarControlClickTests: XCTestCase {
    private var stateDir: URL!
    private var library: WindowLibrary!
    private var actions: AppActions!
    private var window: NSWindow!
    private var outline: NSOutlineView!
    private var coordinator: WorkspaceSidebar.Coordinator!
    private var savedRowClickExpands = true
    private var savedRenameOnDoubleClick = true

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            savedRowClickExpands = GhosttyApp.shared.workspaceRowClickExpands
            savedRenameOnDoubleClick = GhosttyApp.shared.renameOnDoubleClick
            GhosttyApp.shared.setWorkspaceRowClickExpands(true)
            GhosttyApp.shared.setRenameOnDoubleClick(true)
            stateDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("agterm-control-click-tests-\(UUID().uuidString)", isDirectory: true)
            library = WindowLibrary(directory: stateDir)
            actions = AppActions(library: library)
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            GhosttyApp.shared.setWorkspaceRowClickExpands(savedRowClickExpands)
            GhosttyApp.shared.setRenameOnDoubleClick(savedRenameOnDoubleClick)
            window?.orderOut(nil)
            window = nil
            outline = nil
            coordinator = nil
            actions = nil
            library = nil
            try? FileManager.default.removeItem(at: stateDir)
            stateDir = nil
        }
        try await super.tearDown()
    }

    func testControlClickOnSessionRowOpensMenuAndNarrowsSelection() throws {
        let store = try XCTUnwrap(library.activeStore)
        let first = try XCTUnwrap(store.activeSession)
        let ws = try XCTUnwrap(store.workspaces.first)
        let second = try XCTUnwrap(store.addSession(toWorkspace: ws.id, cwd: "/tmp/second"))
        store.selectSession(first.id)
        buildSidebar(for: store)
        let row = try XCTUnwrap(rowIndex { $0.kind == .session && $0.id == second.id })
        XCTAssertFalse(outline.selectedRowIndexes.contains(row))

        let menus = try controlClick(row: row)
        XCTAssertEqual(menus.count, 1, "Control-click should open the row's context menu")
        XCTAssertTrue(menus.first?.contains("Close Session") == true, "it should be the session row's menu: \(menus)")
        XCTAssertEqual(outline.selectedRowIndexes, IndexSet(integer: row), "Control-click should narrow like a right-click")
    }

    func testControlClickOnWorkspaceRowOpensMenuWithoutTogglingExpansion() throws {
        let store = try XCTUnwrap(library.activeStore)
        let ws = try XCTUnwrap(store.workspaces.first)
        buildSidebar(for: store)
        let row = try XCTUnwrap(rowIndex { $0.kind == .workspace && $0.id == ws.id })
        let node = try XCTUnwrap(outline.item(atRow: row))
        XCTAssertTrue(outline.isItemExpanded(node))

        let menus = try controlClick(row: row)
        XCTAssertEqual(menus.count, 1, "Control-click should open the workspace row's context menu")
        XCTAssertTrue(menus.first?.contains("Delete Workspace") == true, "it should be the workspace row's menu: \(menus)")
        RunLoop.main.run(until: Date().addingTimeInterval(NSEvent.doubleClickInterval + 0.2))
        XCTAssertTrue(outline.isItemExpanded(node), "Control-click must not schedule the row-click expansion toggle")
    }

    func testRowClickTogglesAtOnceWithoutDoubleClickRename() throws {
        GhosttyApp.shared.setRenameOnDoubleClick(false)
        for node in try buildGroupRows() {
            for _ in 0..<2 {
                let wasExpanded = outline.isItemExpanded(node)
                try click(node, count: 1)
                XCTAssertNotEqual(outline.isItemExpanded(node), wasExpanded, "\(node.kind) row should toggle at once")
            }
        }
    }

    func testRowClickWaitsForTheDoubleClickIntervalWithDoubleClickRename() throws {
        for node in try buildGroupRows() {
            let wasExpanded = outline.isItemExpanded(node)
            try click(node, count: 1)
            XCTAssertEqual(outline.isItemExpanded(node), wasExpanded, "\(node.kind) row should wait out a rename double-click")
            drainDoubleClickInterval()
            XCTAssertNotEqual(outline.isItemExpanded(node), wasExpanded, "\(node.kind) row should then toggle")
        }
    }

    func testDoubleClickTogglesOnceAndRenamesNothingWithoutDoubleClickRename() throws {
        GhosttyApp.shared.setRenameOnDoubleClick(false)
        for node in try buildGroupRows() {
            for _ in 0..<2 {
                let wasExpanded = outline.isItemExpanded(node)
                try click(node, count: 1)
                try click(node, count: 2)
                drainDoubleClickInterval()
                XCTAssertNotEqual(outline.isItemExpanded(node), wasExpanded, "\(node.kind) double-click should toggle exactly once")
                XCTAssertFalse(coordinator.renameController.isEditing, "\(node.kind) double-click should not rename")
            }
        }
        let session = try XCTUnwrap(library.activeStore?.activeSession)
        try click(try XCTUnwrap(coordinator.cachedNode(session.id)), count: 2)
        XCTAssertTrue(coordinator.renameController.isEditing, "a session double-click still renames")
    }

    func testRowClickDoesNothingWhenRowClickExpansionIsOff() throws {
        GhosttyApp.shared.setWorkspaceRowClickExpands(false)
        let nodes = try buildGroupRows()
        for renames in [false, true] {
            GhosttyApp.shared.setRenameOnDoubleClick(renames)
            for node in nodes {
                let wasExpanded = outline.isItemExpanded(node)
                try click(node, count: 1)
                drainDoubleClickInterval()
                XCTAssertEqual(outline.isItemExpanded(node), wasExpanded, "\(node.kind) row must not toggle, renames=\(renames)")
            }
        }
    }

    func testControlClickOnWorkspaceAddButtonOpensMenuWithoutAddingSession() throws {
        let store = try XCTUnwrap(library.activeStore)
        let ws = try XCTUnwrap(store.workspaces.first)
        buildSidebar(for: store)
        let row = try XCTUnwrap(rowIndex { $0.kind == .workspace && $0.id == ws.id })
        let cell = try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarCellView)
        cell.setAddButtonVisible(true)
        window.contentView?.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(cell.addButton)
        let sessionCount = ws.sessions.count

        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        let menus = try controlClick(button, at: point)
        XCTAssertEqual(menus.count, 1, "Control-click on + should open the workspace row's menu")
        XCTAssertTrue(menus.first?.contains("Delete Workspace") == true, "it should be the workspace row's menu: \(menus)")
        XCTAssertEqual(store.workspaces.first?.sessions.count, sessionCount, "Control-click must not run the + action")
    }

    private final class MenuRequestRecorder: @unchecked Sendable {
        var menus: [NSMenu] = []
    }

    private typealias PopUp = @convention(block) (AnyObject, NSMenu, NSEvent, NSView) -> Void

    /// Returns the item titles of each context menu the click asked for. A real popup is a window-server
    /// surface no test window owns, so it would draw on screen; the request is recorded in its place.
    private func controlClick(row: Int) throws -> [[String]] {
        let rect = outline.rect(ofRow: row)
        return try controlClick(outline, at: outline.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil))
    }

    private func controlClick(_ view: NSView, at point: NSPoint) throws -> [[String]] {
        let recorder = MenuRequestRecorder()
        let selector = #selector(NSMenu.popUpContextMenu(_:with:for:))
        let method = try XCTUnwrap(class_getClassMethod(NSMenu.self, selector))
        let record: PopUp = { _, menu, _, _ in recorder.menus.append(menu) }
        let replacement = imp_implementationWithBlock(record)
        let original = method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        view.mouseDown(with: try mouseEvent(.leftMouseDown, at: point))
        return recorder.menus.map { $0.items.map(\.title) }
    }

    /// `clickedRow` is read-only, and AppKit never sends the action for a synthesized click.
    private final class ClickedRowOutline: NSOutlineView {
        var forcedClickedRow = -1
        override var clickedRow: Int { forcedClickedRow }
    }

    /// A workspace holding a folder, built on a `ClickedRowOutline`; the folder comes first so collapsing the
    /// workspace cannot hide it mid-test.
    private func buildGroupRows() throws -> [SidebarNode] {
        let store = try XCTUnwrap(library.activeStore)
        let ws = try XCTUnwrap(store.workspaces.first)
        let member = try XCTUnwrap(store.addSession(toWorkspace: ws.id, cwd: "/tmp/member"))
        let folder = try XCTUnwrap(store.addFolder(toWorkspace: ws.id, name: "F", containing: [member.id]))
        buildSidebar(for: store, outline: ClickedRowOutline())
        return [try XCTUnwrap(coordinator.cachedNode(folder.id)), try XCTUnwrap(coordinator.cachedNode(ws.id))]
    }

    /// Dispatches one row-body mouse-up the way `NSTableView.mouseDown` does: `action` for the first click,
    /// `doubleAction` alone for the second. The mouse-up becomes `NSApp.currentEvent`, which the hit test reads.
    private func click(_ node: SidebarNode, count: Int) throws {
        let row = outline.row(forItem: node)
        XCTAssertGreaterThanOrEqual(row, 0, "\(node.kind) row should be visible")
        let rect = outline.rect(ofRow: row)
        let point = outline.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        NSApp.postEvent(try mouseEvent(.leftMouseUp, at: point, modifierFlags: [], clickCount: count), atStart: true)
        _ = NSApp.nextEvent(matching: .leftMouseUp, until: .distantFuture, inMode: .default, dequeue: true)
        try XCTUnwrap(outline as? ClickedRowOutline).forcedClickedRow = row
        let selector = try XCTUnwrap(count == 1 ? outline.action : outline.doubleAction)
        XCTAssertTrue(NSApp.sendAction(selector, to: outline.target, from: outline))
    }

    private func drainDoubleClickInterval() {
        RunLoop.main.run(until: Date().addingTimeInterval(NSEvent.doubleClickInterval + 0.2))
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint,
                            modifierFlags: NSEvent.ModifierFlags = .control, clickCount: Int = 1) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifierFlags,
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                         clickCount: clickCount, pressure: 1))
    }

    private func rowIndex(matching predicate: (SidebarNode) -> Bool) -> Int? {
        (0..<outline.numberOfRows).first { row in
            (outline.item(atRow: row) as? SidebarNode).map(predicate) ?? false
        }
    }

    private func buildSidebar(for store: AppStore, outline: NSOutlineView = SidebarOutlineView()) {
        self.outline = outline
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
        outline.action = #selector(WorkspaceSidebar.Coordinator.handleSingleClick(_:))
        outline.doubleAction = #selector(WorkspaceSidebar.Coordinator.handleDoubleClick(_:))
        outline.target = coordinator

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        scroll.documentView = outline
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false // see SidebarStatusBlinkTests for why
        window.contentView = scroll

        coordinator.outlineView = outline
        coordinator.renameController.outlineView = outline
        coordinator.seedExpansionFromModel()
        coordinator.reconcile()
    }
}
