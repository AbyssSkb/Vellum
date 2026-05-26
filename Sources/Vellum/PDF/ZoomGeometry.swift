import AppKit

enum ZoomGeometry {
    static let fitMargin: CGFloat = 0.985

    static func clampedScale(_ scale: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(scale, minimum), maximum)
    }

    static func displaySize(bounds: NSRect, rotation: Int) -> NSSize? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let normalizedRotation = ((rotation % 360) + 360) % 360
        if normalizedRotation == 90 || normalizedRotation == 270 {
            return NSSize(width: bounds.height, height: bounds.width)
        }

        return bounds.size
    }

    static func widthFitScale(
        viewportSize: NSSize,
        pageSize: NSSize,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat? {
        guard viewportSize.width > 0, pageSize.width > 0 else { return nil }

        return clampedScale((viewportSize.width * fitMargin) / pageSize.width, minimum: minimum, maximum: maximum)
    }

    static func pageFitScale(
        viewportSize: NSSize,
        pageSize: NSSize,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat? {
        guard viewportSize.width > 0,
              viewportSize.height > 0,
              pageSize.width > 0,
              pageSize.height > 0 else { return nil }

        let widthScale = (viewportSize.width * fitMargin) / pageSize.width
        let heightScale = (viewportSize.height * fitMargin) / pageSize.height
        return clampedScale(min(widthScale, heightScale), minimum: minimum, maximum: maximum)
    }

    static func isSameViewportSize(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }
}
