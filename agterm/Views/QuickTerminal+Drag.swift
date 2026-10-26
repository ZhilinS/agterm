import agtermCore
import AppKit
import SwiftUI

// Fork: kept out of upstream's QuickTerminal.swift.
extension QuickTerminalController {
    /// On the focused screen at whatever `QuickTerminalMetrics` sizes it to, where a ⌘-drag last left it
    /// there or centered, and its whole visible frame while zoomed. The panel follows the POINTER's screen,
    /// not the app's: it is summoned from another application, where agterm's own key window is no guide
    /// to where the user is looking. The user's size is read here rather than cached because the frame is
    /// recomputed on every show, so a Settings change lands on the next summon with nothing to notify.
    func targetFrame(zoomed: Bool) -> NSRect {
        let screen = Self.activeScreen()
        let visible = screen.visibleFrame
        guard !zoomed else { return visible }
        let size = QuickTerminalMetrics.panelSize(
            visible: WindowGeometry.Size(width: visible.width, height: visible.height),
            sizePercent: GhosttyApp.shared.quickTerminalSizePercent)
        let origin = QuickTerminalMetrics.panelOrigin(
            visible: Self.geometry(visible), size: size,
            remembered: Self.displayID(of: screen).flatMap { rememberedOrigins[$0] })
        return NSRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    /// Records where a drag left the panel, against the display showing most of it, which need not be
    /// the one it was summoned onto.
    func rememberOrigin(of frame: NSRect) {
        let screens = NSScreen.screens
        guard let index = WindowGeometry.bestDisplayIndex(for: Self.geometry(frame),
                                                          among: screens.map { Self.geometry($0.frame) }),
              let id = Self.displayID(of: screens[index]) else { return }
        let visible = screens[index].visibleFrame
        rememberedOrigins[id] = WindowGeometry.Point(x: frame.minX - visible.minX, y: frame.minY - visible.minY)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func geometry(_ rect: NSRect) -> WindowGeometry.Rect {
        WindowGeometry.Rect(origin: WindowGeometry.Point(x: rect.minX, y: rect.minY),
                            size: WindowGeometry.Size(width: rect.width, height: rect.height))
    }
}

extension QuickTerminalPanel {
    /// A borderless panel has no title bar to grab and the terminal takes every mouse event, so the drag
    /// is intercepted here, ahead of the view. The event's own location is used, not `NSEvent.mouseLocation`,
    /// so a synthesized event in a test moves the panel the way a real one does.
    override func sendEvent(_ event: NSEvent) {
        let location = convertPoint(toScreen: event.locationInWindow)
        switch event.type {
        case .leftMouseDown where dragEnabled()
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command):
            swallowingRelease = false
            pendingCommandDown = event
            dragging = false
            lastDragLocation = location
        case .leftMouseDown:
            // a gesture the panel lost track of (hidden or blurred mid-way) must not pair with this press.
            cancelDrag()
            swallowingRelease = false
            super.sendEvent(event)
        case .leftMouseDragged where swallowingRelease:
            return
        case .leftMouseUp where swallowingRelease:
            swallowingRelease = false
        case .leftMouseDragged where pendingCommandDown != nil || dragging:
            if !dragging {
                guard hypot(location.x - lastDragLocation.x, location.y - lastDragLocation.y) > Self.dragThreshold
                else { return }
                dragging = true
                pendingCommandDown = nil
            }
            setFrameOrigin(NSPoint(x: frame.minX + location.x - lastDragLocation.x,
                                   y: frame.minY + location.y - lastDragLocation.y))
            lastDragLocation = location
        case .leftMouseUp where pendingCommandDown != nil:
            let down = pendingCommandDown
            pendingCommandDown = nil
            down.map { super.sendEvent($0) }
            super.sendEvent(event)
        case .leftMouseUp where dragging:
            dragging = false
            onMoved?(frame)
        default:
            super.sendEvent(event)
        }
    }

    /// Forgets a gesture in flight: a held ⌘-click is dropped, a drag ends where the panel is without
    /// being recorded, and the gesture's remaining events never reach the terminal.
    func cancelDrag() {
        // keep an earlier cancel's suppression: resign-key cancels and then hides, which cancels again.
        swallowingRelease = swallowingRelease || pendingCommandDown != nil || dragging
        pendingCommandDown = nil
        dragging = false
    }
}
