// Fork: kept out of upstream's QuickTerminalMetrics.swift.
extension QuickTerminalMetrics {
    /// Where the panel's bottom-left corner goes on a screen whose visible frame is `visible`. With no
    /// record it is centered; a record is the offset from that frame's origin where the user last left
    /// the panel on this screen, pulled back inside the frame so a size or resolution change since
    /// cannot leave it off-screen.
    public static func panelOrigin(visible: WindowGeometry.Rect, size: WindowGeometry.Size,
                                   remembered: WindowGeometry.Point?) -> WindowGeometry.Point {
        guard let remembered else {
            return WindowGeometry.Point(x: visible.origin.x + (visible.size.width - size.width) / 2,
                                        y: visible.origin.y + (visible.size.height - size.height) / 2)
        }
        let maxX = max(0, visible.size.width - size.width)
        let maxY = max(0, visible.size.height - size.height)
        return WindowGeometry.Point(x: visible.origin.x + min(max(0, remembered.x), maxX),
                                    y: visible.origin.y + min(max(0, remembered.y), maxY))
    }
}
