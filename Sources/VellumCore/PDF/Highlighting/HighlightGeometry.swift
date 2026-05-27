@preconcurrency import AppKit
import PDFKit

enum HighlightGeometry {
    static func tightBounds(for selection: PDFSelection, on page: PDFPage) -> NSRect? {
        let rawBounds = selection.bounds(for: page)
        guard rawBounds.width > 0, rawBounds.height > 0 else { return nil }

        let verticalInset = min(max(rawBounds.height * 0.10, 0.45), 1.4)
        let horizontalOutset: CGFloat = 0.35
        let bounds = rawBounds.insetBy(dx: -horizontalOutset, dy: verticalInset)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        return bounds
    }

    static func quadrilateralPoints(for bounds: NSRect) -> [NSValue] {
        [
            NSValue(point: NSPoint(x: 0, y: bounds.height)),
            NSValue(point: NSPoint(x: bounds.width, y: bounds.height)),
            NSValue(point: NSPoint(x: 0, y: 0)),
            NSValue(point: NSPoint(x: bounds.width, y: 0))
        ]
    }

    static func regions(for annotation: PDFAnnotation) -> [NSRect] {
        guard let quadrilateralPoints = annotation.quadrilateralPoints,
              quadrilateralPoints.count >= 4 else {
            return [annotation.bounds]
        }

        let regions = stride(from: 0, to: quadrilateralPoints.count - 3, by: 4).compactMap { index in
            quadBounds(
                Array(quadrilateralPoints[index..<(index + 4)]),
                relativeTo: annotation.bounds
            )
        }

        return regions.isEmpty ? [annotation.bounds] : regions
    }

    static func rect(containing points: [NSPoint]) -> NSRect? {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max(),
              maxX > minX,
              maxY > minY else {
            return nil
        }

        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func matches(annotationBounds: NSRect, selectionBounds: NSRect) -> Bool {
        guard annotationBounds.width > 0,
              annotationBounds.height > 0,
              selectionBounds.width > 0,
              selectionBounds.height > 0 else {
            return false
        }

        let intersection = annotationBounds.intersection(selectionBounds)
        guard !intersection.isNull,
              intersection.width > 0,
              intersection.height > 0 else {
            return false
        }

        let verticalOverlap = intersection.height / min(annotationBounds.height, selectionBounds.height)
        guard verticalOverlap >= 0.55 else { return false }

        if selectionBounds.contains(center(of: annotationBounds))
            || annotationBounds.contains(center(of: selectionBounds)) {
            return true
        }

        let annotationArea = annotationBounds.width * annotationBounds.height
        let selectionArea = selectionBounds.width * selectionBounds.height
        let intersectionArea = intersection.width * intersection.height
        let smallerArea = min(annotationArea, selectionArea)

        return smallerArea > 0 && intersectionArea / smallerArea >= 0.42
    }

    static func annotationsAreConnected(_ lhs: PDFAnnotation, _ rhs: PDFAnnotation) -> Bool {
        if lhs === rhs { return true }

        return regions(for: lhs).contains { lhsRegion in
            regions(for: rhs).contains { rhsRegion in
                rectsAreConnected(lhsRegion, rhsRegion)
            }
        }
    }

    static func rectsAreConnected(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else {
            return false
        }

        if lhs.intersects(rhs) {
            return true
        }

        let verticalGap = max(0, max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY))
        let horizontalGap = max(0, max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX))
        let lineHeight = min(lhs.height, rhs.height)
        let adjacentLineGap = max(2.5, lineHeight * 0.9)
        let relatedHorizontalGap = max(24, lineHeight * 6)

        return verticalGap <= adjacentLineGap && horizontalGap <= relatedHorizontalGap
    }

    static func colorsMatch(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        guard let lhs = lhs?.usingColorSpace(.deviceRGB),
              let rhs = rhs?.usingColorSpace(.deviceRGB) else {
            return lhs == nil && rhs == nil
        }

        return abs(lhs.redComponent - rhs.redComponent) < 0.015
            && abs(lhs.greenComponent - rhs.greenComponent) < 0.015
            && abs(lhs.blueComponent - rhs.blueComponent) < 0.015
            && abs(lhs.alphaComponent - rhs.alphaComponent) < 0.03
    }

    private static func quadBounds(_ values: [NSValue], relativeTo annotationBounds: NSRect) -> NSRect? {
        let points = values.map(\.pointValue)
        guard points.count == 4 else { return nil }

        guard let relativeBounds = rect(containing: points.map { point in
            NSPoint(x: annotationBounds.minX + point.x, y: annotationBounds.minY + point.y)
        }),
              let absoluteBounds = rect(containing: points) else {
            return nil
        }
        let expandedAnnotationBounds = annotationBounds.insetBy(dx: -1, dy: -1)

        if expandedAnnotationBounds.intersects(relativeBounds) {
            return relativeBounds
        }

        if expandedAnnotationBounds.intersects(absoluteBounds) {
            return absoluteBounds
        }

        return relativeBounds
    }

    private static func center(of rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }
}
