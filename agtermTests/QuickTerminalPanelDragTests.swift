import XCTest
@testable import agterm

@MainActor
final class QuickTerminalPanelDragTests: XCTestCase {
    private final class RecordingView: NSView {
        var received: [NSEvent.EventType] = []
        override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) { received.append(.leftMouseDown) }
        override func mouseDragged(with event: NSEvent) { received.append(.leftMouseDragged) }
        override func mouseUp(with event: NSEvent) { received.append(.leftMouseUp) }
    }

    private let start = NSRect(x: 100, y: 100, width: 400, height: 300)
    private var panels: [QuickTerminalPanel] = []

    override func tearDown() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        super.tearDown()
    }

    /// Ordered in and key, as `show` leaves it: `sendEvent` hit-tests only a window on screen, and a plain
    /// press on a non-key window only activates it. The host keeps the panel invisible.
    private func makePanel() -> (QuickTerminalPanel, RecordingView) {
        let panel = QuickTerminalPanel(onBecomeKey: {}, onResignKey: {})
        let view = RecordingView(frame: NSRect(origin: .zero, size: start.size))
        panel.setFrame(start, display: false)
        panel.contentView = view
        panel.orderFrontRegardless()
        panel.makeKey()
        panels.append(panel)
        return (panel, view)
    }

    private func send(_ type: NSEvent.EventType, at screenPoint: NSPoint, to panel: QuickTerminalPanel,
                      command: Bool = true) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: panel.convertPoint(fromScreen: screenPoint),
            modifierFlags: command ? [.command] : [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        panel.sendEvent(event)
    }

    func testCommandDragMovesThePanelAndForwardsNothing() throws {
        let (panel, view) = makePanel()
        var moved: NSRect?
        panel.onMoved = { moved = $0 }

        try send(.leftMouseDown, at: NSPoint(x: 200, y: 200), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 230, y: 220), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 260, y: 240), to: panel)
        try send(.leftMouseUp, at: NSPoint(x: 260, y: 240), to: panel)

        XCTAssertEqual(panel.frame.origin, NSPoint(x: 160, y: 140))
        XCTAssertEqual(moved?.origin, NSPoint(x: 160, y: 140))
        XCTAssertEqual(view.received, [])
    }

    func testCommandClickReachesTheViewAsDownThenUp() throws {
        let (panel, view) = makePanel()
        var moved = false
        panel.onMoved = { _ in moved = true }

        try send(.leftMouseDown, at: NSPoint(x: 200, y: 200), to: panel)
        XCTAssertEqual(view.received, [])
        try send(.leftMouseUp, at: NSPoint(x: 200, y: 200), to: panel)

        XCTAssertEqual(view.received, [.leftMouseDown, .leftMouseUp])
        XCTAssertEqual(panel.frame, start)
        XCTAssertFalse(moved)
    }

    func testMovementUnderTheThresholdStaysAClick() throws {
        let (panel, view) = makePanel()

        try send(.leftMouseDown, at: NSPoint(x: 200, y: 200), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 202, y: 201), to: panel)
        try send(.leftMouseUp, at: NSPoint(x: 202, y: 201), to: panel)

        XCTAssertEqual(view.received, [.leftMouseDown, .leftMouseUp])
        XCTAssertEqual(panel.frame, start)
    }

    func testPlainPressIsForwardedAtOnce() throws {
        let (panel, view) = makePanel()
        try send(.leftMouseDown, at: NSPoint(x: 200, y: 200), to: panel, command: false)
        XCTAssertEqual(view.received, [.leftMouseDown])
    }

    func testDisabledDragForwardsTheCommandPressAtOnce() throws {
        let (panel, view) = makePanel()
        panel.dragEnabled = { false }
        try send(.leftMouseDown, at: NSPoint(x: 200, y: 200), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 260, y: 240), to: panel)
        XCTAssertEqual(view.received, [.leftMouseDown, .leftMouseDragged])
        XCTAssertEqual(panel.frame, start)
    }

    func testCancelDropsTheHeldPressAndTheNextPressIsOrdinary() throws {
        let (panel, view) = makePanel()
        var moved = false
        panel.onMoved = { _ in moved = true }

        // an earlier real click, so AppKit has a recipient for a release the panel fails to swallow
        try send(.leftMouseDown, at: NSPoint(x: 200, y: 200), to: panel, command: false)
        try send(.leftMouseUp, at: NSPoint(x: 200, y: 200), to: panel, command: false)
        try send(.leftMouseDown, at: NSPoint(x: 200, y: 200), to: panel)
        try send(.leftMouseDragged, at: NSPoint(x: 230, y: 220), to: panel)
        // resign-key cancels, then hides, which cancels again
        panel.cancelDrag()
        panel.cancelDrag()
        try send(.leftMouseDragged, at: NSPoint(x: 260, y: 240), to: panel)
        try send(.leftMouseUp, at: NSPoint(x: 260, y: 240), to: panel)
        try send(.leftMouseDown, at: NSPoint(x: 200, y: 200), to: panel, command: false)
        try send(.leftMouseUp, at: NSPoint(x: 200, y: 200), to: panel, command: false)

        XCTAssertEqual(panel.frame.origin, NSPoint(x: 130, y: 120))
        XCTAssertFalse(moved)
        XCTAssertEqual(view.received, [.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp])
    }

    func testCancelWithNoGestureSwallowsNothing() throws {
        let (panel, view) = makePanel()
        try send(.leftMouseDown, at: NSPoint(x: 200, y: 200), to: panel, command: false)
        panel.cancelDrag()
        try send(.leftMouseUp, at: NSPoint(x: 200, y: 200), to: panel, command: false)
        XCTAssertEqual(view.received, [.leftMouseDown, .leftMouseUp])
    }
}
