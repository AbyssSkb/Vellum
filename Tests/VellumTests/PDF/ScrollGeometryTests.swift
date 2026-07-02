import Testing
import AppKit
@testable import VellumCore

@Suite("Scroll geometry")
struct ScrollGeometryTests {
    @Test
    func nextCoordinateAppliesDeltaWithinScrollableContent() {
        #expect(ScrollGeometry.nextCoordinate(origin: 20, delta: 15, contentLength: 300, viewportLength: 100, maxValue: 200) == 35)
        #expect(ScrollGeometry.nextCoordinate(origin: 190, delta: 20, contentLength: 300, viewportLength: 100, maxValue: 200) == 200)
        #expect(ScrollGeometry.nextCoordinate(origin: 10, delta: -20, contentLength: 300, viewportLength: 100, maxValue: 200) == 0)
    }

    @Test
    func nextCoordinateLeavesUnscrollableOrZeroDeltaOriginsAlone() {
        #expect(ScrollGeometry.nextCoordinate(origin: 20, delta: 0, contentLength: 300, viewportLength: 100, maxValue: 200) == 20)
        #expect(ScrollGeometry.nextCoordinate(origin: 20, delta: 15, contentLength: 100, viewportLength: 100, maxValue: 0) == 20)
    }

    @Test
    func directWheelDeltaUsesPreciseDeltaWithoutLineScaling() {
        #expect(ScrollGeometry.directWheelDelta(scrollingDelta: 12, fallbackDelta: 0, hasPreciseScrollingDeltas: true) == 12)
        #expect(ScrollGeometry.nextCoordinate(origin: 20, delta: 12, contentLength: 300, viewportLength: 100, maxValue: 200) == 32)
    }

    @Test
    func directWheelDeltaScalesLegacyWheelTicks() {
        #expect(ScrollGeometry.directWheelDelta(scrollingDelta: -3, fallbackDelta: 0, hasPreciseScrollingDeltas: false) == -30)
        #expect(ScrollGeometry.nextCoordinate(origin: 80, delta: -30, contentLength: 300, viewportLength: 100, maxValue: 200) == 50)
    }

    @Test
    func directWheelDeltaFallsBackToLegacyDeltaWhenScrollingDeltaIsEmpty() {
        #expect(ScrollGeometry.directWheelDelta(scrollingDelta: 0, fallbackDelta: 4, hasPreciseScrollingDeltas: false) == 40)
    }

    @Test
    func restoredCoordinateClampsOnlyScrollableContent() {
        #expect(ScrollGeometry.restoredCoordinate(origin: -10, contentLength: 300, viewportLength: 100, maxValue: 200) == 0)
        #expect(ScrollGeometry.restoredCoordinate(origin: 240, contentLength: 300, viewportLength: 100, maxValue: 200) == 200)
        #expect(ScrollGeometry.restoredCoordinate(origin: 240, contentLength: 100, viewportLength: 100, maxValue: 0) == 240)
    }

    @Test
    func centeredCoordinateCentersPointAndClampsToBounds() {
        #expect(ScrollGeometry.centeredCoordinate(point: 120, currentOrigin: 0, contentLength: 400, viewportLength: 100, maxValue: 300) == 70)
        #expect(ScrollGeometry.centeredCoordinate(point: 20, currentOrigin: 80, contentLength: 400, viewportLength: 100, maxValue: 300) == 0)
        #expect(ScrollGeometry.centeredCoordinate(point: 380, currentOrigin: 80, contentLength: 400, viewportLength: 100, maxValue: 300) == 300)
        #expect(ScrollGeometry.centeredCoordinate(point: 120, currentOrigin: 80, contentLength: 100, viewportLength: 100, maxValue: 0) == 80)
    }

    @Test
    func verticalEdgeCoordinateAccountsForFlippedDocumentViews() {
        #expect(ScrollGeometry.verticalEdgeCoordinate(edge: .top, isFlipped: true, maxValue: 300) == 0)
        #expect(ScrollGeometry.verticalEdgeCoordinate(edge: .bottom, isFlipped: true, maxValue: 300) == 300)
        #expect(ScrollGeometry.verticalEdgeCoordinate(edge: .top, isFlipped: false, maxValue: 300) == 300)
        #expect(ScrollGeometry.verticalEdgeCoordinate(edge: .bottom, isFlipped: false, maxValue: 300) == 0)
    }

    @Test
    func comfortableVisibleOriginLeavesComfortableTargetsAlone() {
        let nextOrigin = ScrollGeometry.comfortableVisibleOrigin(
            currentOrigin: NSPoint(x: 0, y: 0),
            visibleSize: NSSize(width: 500, height: 400),
            documentBounds: NSRect(x: 0, y: 0, width: 1_000, height: 1_000),
            targetRect: NSRect(x: 120, y: 120, width: 20, height: 20)
        )

        #expect(nextOrigin == nil)
    }

    @Test
    func comfortableVisibleOriginScrollsTargetIntoMargin() {
        let nextOrigin = ScrollGeometry.comfortableVisibleOrigin(
            currentOrigin: NSPoint(x: 100, y: 100),
            visibleSize: NSSize(width: 500, height: 400),
            documentBounds: NSRect(x: 0, y: 0, width: 1_000, height: 1_000),
            targetRect: NSRect(x: 130, y: 130, width: 20, height: 20)
        )

        #expect(nextOrigin == NSPoint(x: 86, y: 74))
    }

    @Test
    func comfortableVisibleOriginClampsToDocumentBounds() {
        let nextOrigin = ScrollGeometry.comfortableVisibleOrigin(
            currentOrigin: NSPoint(x: 480, y: 570),
            visibleSize: NSSize(width: 500, height: 400),
            documentBounds: NSRect(x: 0, y: 0, width: 1_000, height: 1_000),
            targetRect: NSRect(x: 940, y: 980, width: 80, height: 60)
        )

        #expect(nextOrigin == NSPoint(x: 500, y: 600))
    }

    @Test
    func comfortableVisibleOriginIgnoresSubpixelAdjustments() {
        let nextOrigin = ScrollGeometry.comfortableVisibleOrigin(
            currentOrigin: NSPoint(x: 100, y: 100),
            visibleSize: NSSize(width: 500, height: 400),
            documentBounds: NSRect(x: 0, y: 0, width: 1_000, height: 1_000),
            targetRect: NSRect(x: 155.7, y: 156.3, width: 20, height: 20)
        )

        #expect(nextOrigin == nil)
    }
}
