import Foundation
import Testing
@testable import agtermCore

struct QuickTerminalMetricsTests {
    /// Compared with a tolerance: a share of a screen is a floating-point product, so 70% of 1440 lands on
    /// 1007.9999999999999. The panel is framed in fractional points either way, as it was before the setting.
    private func expectSize(_ size: WindowGeometry.Size, _ width: Double, _ height: Double) {
        #expect(abs(size.width - width) < 0.001)
        #expect(abs(size.height - height) < 0.001)
    }

    /// A 32" 4K display in points, the case from the report that motivated the setting.
    private let large = WindowGeometry.Size(width: 2560, height: 1440)
    /// A small external display in points, under the roughly 1111 of shorter side where the built-in
    /// maximum takes over, so the default share binds.
    private let small = WindowGeometry.Size(width: 1200, height: 760)

    @Test func defaultCapsALargeScreenAtTheBuiltInMaximum() {
        expectSize(QuickTerminalMetrics.panelSize(visible: large, sizePercent: nil), 1000, 750)
    }

    @Test func defaultTakesTheShareWhenItFallsUnderTheMaximum() {
        expectSize(QuickTerminalMetrics.panelSize(visible: small, sizePercent: nil), 684, 513)
    }

    @Test func defaultTakesTheWidthFromTheShorterSide() {
        let visible = WindowGeometry.Size(width: 2000, height: 600)
        expectSize(QuickTerminalMetrics.panelSize(visible: visible, sizePercent: nil), 540, 405)
    }

    @Test func setPercentageReplacesTheMaximumInsteadOfRaisingIt() {
        expectSize(QuickTerminalMetrics.panelSize(visible: large, sizePercent: 70), 1008, 756)
    }

    @Test func setPercentageAppliesToASmallScreenToo() {
        expectSize(QuickTerminalMetrics.panelSize(visible: small, sizePercent: 50), 380, 285)
    }

    /// Why nil keeps its own path: the two regimes disagree. Where the share binds, 90% IS the default;
    /// where the maximum binds, no offered percentage reproduces it, so no single choice serves both.
    @Test func noPercentageReproducesTheDefaultOnBothScreens() {
        #expect(choicesMatchingTheDefault(on: small) == [90])
        #expect(choicesMatchingTheDefault(on: large).isEmpty)
    }

    private func choicesMatchingTheDefault(on visible: WindowGeometry.Size) -> [Int] {
        let byDefault = QuickTerminalMetrics.panelSize(visible: visible, sizePercent: nil)
        return QuickTerminalMetrics.sizePercentChoices.filter {
            let sized = QuickTerminalMetrics.panelSize(visible: visible, sizePercent: $0)
            return abs(sized.width - byDefault.width) < 0.001 && abs(sized.height - byDefault.height) < 0.001
        }
    }

    @Test func percentageAboveTheRangeClampsToTheCeiling() {
        expectSize(QuickTerminalMetrics.panelSize(visible: large, sizePercent: 400),
                   QuickTerminalMetrics.panelSize(visible: large, sizePercent: 90).width,
                   QuickTerminalMetrics.panelSize(visible: large, sizePercent: 90).height)
    }

    @Test func percentageBelowTheRangeClampsToTheFloor() {
        expectSize(QuickTerminalMetrics.panelSize(visible: large, sizePercent: 0),
                   QuickTerminalMetrics.panelSize(visible: large, sizePercent: 40).width,
                   QuickTerminalMetrics.panelSize(visible: large, sizePercent: 40).height)
    }

    @Test func clampSizePercentBoundsBothEnds() {
        #expect(QuickTerminalMetrics.clampSizePercent(-5) == QuickTerminalMetrics.sizePercentRange.lowerBound)
        #expect(QuickTerminalMetrics.clampSizePercent(1000) == QuickTerminalMetrics.sizePercentRange.upperBound)
        #expect(QuickTerminalMetrics.clampSizePercent(70) == 70)
    }

    @Test func everyOfferedChoiceIsInRange() {
        for percent in QuickTerminalMetrics.sizePercentChoices {
            #expect(QuickTerminalMetrics.clampSizePercent(percent) == percent)
        }
    }

    @Test func percentageIsMonotonicAcrossTheOfferedChoices() {
        let widths = QuickTerminalMetrics.sizePercentChoices.map {
            QuickTerminalMetrics.panelSize(visible: large, sizePercent: $0).width
        }
        #expect(widths == widths.sorted())
        #expect(Set(widths).count == widths.count)
    }

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
