import AppKit
import PDFKit
import Testing
@testable import VellumCore

@Suite("PDF display coordinates")
struct PDFPageDisplayGeometryTests {
    @Test(arguments: [0, 90, 180, 270, -90])
    @MainActor
    func croppedRotatedCoordinatesMatchDisplayEdges(rotation: Int) {
        let page = PDFPage()
        let crop = NSRect(x: 40, y: 60, width: 800, height: 1_200)
        page.setBounds(NSRect(x: 0, y: 0, width: 1_000, height: 1_600), for: .mediaBox)
        page.setBounds(crop, for: .cropBox)
        page.rotation = rotation
        let geometry = PDFPageDisplayGeometry(page: page, box: .cropBox)
        let topPagePoint: NSPoint
        let displayBounds: NSRect
        let displayTextRect: NSRect
        switch rotation {
        case 90:
            topPagePoint = NSPoint(x: 40, y: 660)
            displayBounds = NSRect(x: 0, y: 0, width: 1_200, height: 800)
            displayTextRect = NSRect(x: 160, y: 560, width: 20, height: 160)
        case 180:
            topPagePoint = NSPoint(x: 440, y: 60)
            displayBounds = NSRect(x: 0, y: 0, width: 800, height: 1_200)
            displayTextRect = NSRect(x: 560, y: 1_020, width: 160, height: 20)
        case 270, -90:
            topPagePoint = NSPoint(x: 840, y: 660)
            displayBounds = NSRect(x: 0, y: 0, width: 1_200, height: 800)
            displayTextRect = NSRect(x: 1_020, y: 80, width: 20, height: 160)
        default:
            topPagePoint = NSPoint(x: 440, y: 1_260)
            displayBounds = NSRect(x: 0, y: 0, width: 800, height: 1_200)
            displayTextRect = NSRect(x: 80, y: 160, width: 160, height: 20)
        }

        #expect(geometry.bounds == displayBounds)
        #expect(geometry.rect(forPageRect: crop) == displayBounds)
        #expect(geometry.point(forPagePoint: topPagePoint) == NSPoint(x: displayBounds.midX, y: displayBounds.maxY))
        #expect(geometry.pagePoint(forDisplayPoint: NSPoint(x: displayBounds.midX, y: displayBounds.maxY)) == topPagePoint)
        let textRect = NSRect(x: 120, y: 220, width: 160, height: 20)
        #expect(geometry.rect(forPageRect: textRect) == displayTextRect)
        #expect(geometry.pageRect(forDisplayRect: displayTextRect) == textRect)

        let view = VellumPDFView()
        view.displayBox = .cropBox
        #expect(view.topDestination(for: page).point == topPagePoint)
    }

    @Test(arguments: [0, 90, 180, 270])
    @MainActor
    func movingBetweenPagesPreservesHorizontalAndVerticalDisplayPosition(rotation: Int) async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for (index, rotation) in [rotation, (rotation + 90) % 360].enumerated() {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 2_000, height: 2_000), for: .mediaBox)
            page.setBounds(index == 0
                ? NSRect(x: 40, y: 60, width: 800, height: 1_200)
                : NSRect(x: 100, y: 120, width: 1_600, height: 1_000), for: .cropBox)
            page.rotation = rotation
            document.insert(page, at: index)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = VellumPDFView(frame: window.contentView!.bounds)
        window.contentView = view
        view.displayMode = .singlePageContinuous
        view.displayBox = .cropBox
        view.document = document
        view.autoScales = false
        view.scaleFactor = 1
        view.layoutDocumentView()
        let sourcePage = try #require(document.page(at: 0))
        let sourcePoint: NSPoint
        let targetPoint: NSPoint
        switch rotation {
        case 90:
            sourcePoint = NSPoint(x: 360, y: 480)
            targetPoint = NSPoint(x: 1_140, y: 520)
        case 180:
            sourcePoint = NSPoint(x: 560, y: 540)
            targetPoint = NSPoint(x: 1_060, y: 770)
        case 270:
            sourcePoint = NSPoint(x: 520, y: 840)
            targetPoint = NSPoint(x: 660, y: 720)
        default:
            sourcePoint = NSPoint(x: 320, y: 780)
            targetPoint = NSPoint(x: 740, y: 470)
        }
        view.centerBothAxes(on: PDFDestination(page: sourcePage, at: sourcePoint))

        for delta in [1, -1] {
            view.vimMoveByPage(delta)
            await nextTestMainQueueTurn()
            let state = try #require(view.currentPageState())
            #expect(state.pageIndex == (delta == 1 ? 1 : 0))
            let expectedPoint = delta == 1 ? targetPoint : sourcePoint
            let cropSize = delta == 1 ? NSSize(width: 1_600, height: 1_000) : NSSize(width: 800, height: 1_200)
            #expect(abs(state.pointOnPage.x - expectedPoint.x) / cropSize.width < 0.005)
            #expect(abs(state.pointOnPage.y - expectedPoint.y) / cropSize.height < 0.005)
        }
    }
}
