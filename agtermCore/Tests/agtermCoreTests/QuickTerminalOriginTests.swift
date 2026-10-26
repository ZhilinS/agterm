import Foundation
import Testing
@testable import agtermCore

// Fork: kept out of upstream's QuickTerminalMetricsTests.swift.
struct QuickTerminalOriginTests {
    private let screen = WindowGeometry.Rect(origin: WindowGeometry.Point(x: 1920, y: 25),
                                             size: WindowGeometry.Size(width: 2560, height: 1415))
    private let panel = WindowGeometry.Size(width: 1100, height: 700)

    @Test func noRecordCentersThePanel() {
        let origin = QuickTerminalMetrics.panelOrigin(visible: screen, size: panel, remembered: nil)
        #expect(origin == WindowGeometry.Point(x: 1920 + (2560 - 1100) / 2, y: 25 + (1415 - 700) / 2))
    }

    @Test func recordIsAnOffsetFromTheVisibleFrameOrigin() {
        let origin = QuickTerminalMetrics.panelOrigin(visible: screen, size: panel,
                                                      remembered: WindowGeometry.Point(x: 100, y: 40))
        #expect(origin == WindowGeometry.Point(x: 2020, y: 65))
    }

    @Test func recordPastTheFarEdgeIsPulledBackInside() {
        let origin = QuickTerminalMetrics.panelOrigin(visible: screen, size: panel,
                                                      remembered: WindowGeometry.Point(x: 2000, y: 1300))
        #expect(origin == WindowGeometry.Point(x: 1920 + 2560 - 1100, y: 25 + 1415 - 700))
    }

    @Test func negativeRecordIsPulledToTheNearEdge() {
        let origin = QuickTerminalMetrics.panelOrigin(visible: screen, size: panel,
                                                      remembered: WindowGeometry.Point(x: -50, y: -10))
        #expect(origin == screen.origin)
    }

    @Test func panelLargerThanTheScreenSitsAtTheOrigin() {
        let huge = WindowGeometry.Size(width: 3000, height: 2000)
        let origin = QuickTerminalMetrics.panelOrigin(visible: screen, size: huge,
                                                      remembered: WindowGeometry.Point(x: 300, y: 300))
        #expect(origin == screen.origin)
    }
}
