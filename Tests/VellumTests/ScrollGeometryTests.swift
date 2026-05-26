import Testing
@testable import Vellum

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
}
