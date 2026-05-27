import AppKit
import Testing
@testable import VellumCore

@Suite("Zoom geometry")
struct ZoomGeometryTests {
    @Test
    func displaySizeSwapsPageDimensionsForSidewaysRotations() {
        let bounds = NSRect(x: 0, y: 0, width: 200, height: 300)

        #expect(ZoomGeometry.displaySize(bounds: bounds, rotation: 0) == NSSize(width: 200, height: 300))
        #expect(ZoomGeometry.displaySize(bounds: bounds, rotation: 90) == NSSize(width: 300, height: 200))
        #expect(ZoomGeometry.displaySize(bounds: bounds, rotation: 270) == NSSize(width: 300, height: 200))
        #expect(ZoomGeometry.displaySize(bounds: bounds, rotation: -90) == NSSize(width: 300, height: 200))
    }

    @Test
    func displaySizeRejectsEmptyBounds() {
        #expect(ZoomGeometry.displaySize(bounds: NSRect(x: 0, y: 0, width: 0, height: 300), rotation: 0) == nil)
        #expect(ZoomGeometry.displaySize(bounds: NSRect(x: 0, y: 0, width: 200, height: 0), rotation: 0) == nil)
    }

    @Test
    func widthFitScaleUsesViewportWidthAndMargin() {
        let scale = ZoomGeometry.widthFitScale(
            viewportSize: NSSize(width: 800, height: 600),
            pageSize: NSSize(width: 400, height: 900),
            minimum: 0.1,
            maximum: 8
        )

        #expect(scale == 1.97)
    }

    @Test
    func pageFitScaleUsesSmallerAxisScale() {
        let scale = ZoomGeometry.pageFitScale(
            viewportSize: NSSize(width: 800, height: 600),
            pageSize: NSSize(width: 400, height: 900),
            minimum: 0.1,
            maximum: 8
        )

        #expect(scale == 0.6566666666666666)
    }

    @Test
    func fitScalesClampToConfiguredBounds() {
        #expect(ZoomGeometry.widthFitScale(
            viewportSize: NSSize(width: 10_000, height: 600),
            pageSize: NSSize(width: 100, height: 100),
            minimum: 0.1,
            maximum: 8
        ) == 8)

        #expect(ZoomGeometry.pageFitScale(
            viewportSize: NSSize(width: 10, height: 10),
            pageSize: NSSize(width: 1_000, height: 1_000),
            minimum: 0.1,
            maximum: 8
        ) == 0.1)
    }

    @Test
    func fitScalesRejectEmptyDimensions() {
        #expect(ZoomGeometry.widthFitScale(
            viewportSize: NSSize(width: 0, height: 600),
            pageSize: NSSize(width: 400, height: 900),
            minimum: 0.1,
            maximum: 8
        ) == nil)

        #expect(ZoomGeometry.pageFitScale(
            viewportSize: NSSize(width: 800, height: 600),
            pageSize: NSSize(width: 400, height: 0),
            minimum: 0.1,
            maximum: 8
        ) == nil)
    }

    @Test
    func viewportSizeComparisonAllowsSubpixelDrift() {
        #expect(ZoomGeometry.isSameViewportSize(
            NSSize(width: 800, height: 600),
            NSSize(width: 800.4, height: 599.6)
        ))
        #expect(!ZoomGeometry.isSameViewportSize(
            NSSize(width: 800, height: 600),
            NSSize(width: 800.5, height: 600)
        ))
    }
}
