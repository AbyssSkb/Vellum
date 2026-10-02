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
        switch rotation {
        case 90: topPagePoint = NSPoint(x: crop.minX, y: crop.midY)
        case 180: topPagePoint = NSPoint(x: crop.midX, y: crop.minY)
        case 270, -90: topPagePoint = NSPoint(x: crop.maxX, y: crop.midY)
        default: topPagePoint = NSPoint(x: crop.midX, y: crop.maxY)
        }

        #expect(geometry.rect(forPageRect: crop) == geometry.bounds)
        #expect(geometry.point(forPagePoint: topPagePoint) == NSPoint(x: geometry.bounds.midX, y: geometry.bounds.maxY))
        #expect(geometry.pagePoint(forDisplayPoint: NSPoint(x: geometry.bounds.midX, y: geometry.bounds.maxY)) == topPagePoint)
        let textRect = NSRect(x: 120, y: 220, width: 160, height: 20)
        #expect(geometry.pageRect(forDisplayRect: geometry.rect(forPageRect: textRect)) == textRect)

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
        let sourceGeometry = PDFPageDisplayGeometry(page: sourcePage, box: .cropBox)
        view.centerBothAxes(on: PDFDestination(page: sourcePage, at: sourceGeometry.pagePoint(forDisplayPoint: NSPoint(
            x: sourceGeometry.bounds.width * 0.35, y: sourceGeometry.bounds.height * 0.6
        ))))

        for delta in [1, -1] {
            view.vimMoveByPage(delta)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            let state = try #require(view.currentPageState())
            #expect(state.pageIndex == (delta == 1 ? 1 : 0))
            let geometry = PDFPageDisplayGeometry(page: state.page, box: .cropBox)
            let point = geometry.point(forPagePoint: state.pointOnPage)
            #expect(abs(point.x / geometry.bounds.width - 0.35) < 0.005)
            #expect(abs(point.y / geometry.bounds.height - 0.6) < 0.005)
        }
    }

    @Test(arguments: [CGFloat(600), CGFloat(1_200)])
    @MainActor
    func scrollAnimationReclampsAfterViewportResize(viewportLength: CGFloat) throws {
        _ = NSApplication.shared
        let view = VellumPDFView()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 1_000))
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: 800, y: 800))
        view.animationState.scrollTargetOrigin = NSPoint(x: 800, y: 800)
        clipView.setFrameSize(NSSize(width: viewportLength, height: viewportLength))

        view.stepScrollAnimation(in: scrollView)

        let maximum = max(0, 1_000 - viewportLength)
        if viewportLength < 1_000 {
            if let target = view.animationState.scrollTargetOrigin {
                #expect(target == NSPoint(x: maximum, y: maximum))
            }
            #expect(clipView.bounds.origin.x >= 0 && clipView.bounds.origin.x <= maximum)
            #expect(clipView.bounds.origin.y >= 0 && clipView.bounds.origin.y <= maximum)
        } else {
            #expect(clipView.bounds.contains(NSRect(x: 0, y: 0, width: 1_000, height: 1_000)))
        }
    }

    @Test @MainActor
    func scrollAnimationReachesFractionalTarget() throws {
        _ = NSApplication.shared
        let view = VellumPDFView()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 1_000))
        let target = NSPoint(x: 123.4, y: 456.65)
        view.animationState.scrollTargetOrigin = target
        for _ in 0..<60 {
            view.animationState.lastScrollTick = Date.timeIntervalSinceReferenceDate - 1.0 / 30.0
            view.stepScrollAnimation(in: scrollView)
        }
        #expect(scrollView.contentView.bounds.origin == target)
        #expect(view.animationState.scrollTargetOrigin == nil)
    }
}
