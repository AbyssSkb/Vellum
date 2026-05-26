@preconcurrency import AppKit

enum ScrollGeometry {
    enum VerticalEdge {
        case top
        case bottom
    }

    static func nextCoordinate(
        origin: CGFloat,
        delta: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard delta != 0 else { return origin }
        guard contentLength > viewportLength else { return origin }
        return clamped(origin + delta, maxValue: maxValue)
    }

    static func restoredCoordinate(
        origin: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard contentLength > viewportLength else { return origin }
        return clamped(origin, maxValue: maxValue)
    }

    static func centeredCoordinate(
        point: CGFloat,
        currentOrigin: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        maxValue: CGFloat
    ) -> CGFloat {
        guard contentLength > viewportLength else { return currentOrigin }
        return clamped(point - viewportLength / 2, maxValue: maxValue)
    }

    static func verticalEdgeCoordinate(edge: VerticalEdge, isFlipped: Bool, maxValue: CGFloat) -> CGFloat {
        switch (edge, isFlipped) {
        case (.top, true), (.bottom, false):
            return 0
        case (.top, false), (.bottom, true):
            return maxValue
        }
    }

    private static func clamped(_ value: CGFloat, maxValue: CGFloat) -> CGFloat {
        min(max(0, value), maxValue)
    }
}
