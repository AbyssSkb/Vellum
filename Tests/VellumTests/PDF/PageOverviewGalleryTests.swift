@preconcurrency import AppKit
import PDFKit
import QuartzCore
import Testing
@testable import VellumCore

@MainActor
@Suite("Page overview gallery")
struct PageOverviewGalleryTests {
    @Test
    func previewsGrowWithViewportAndKeepEachPageAspectRatio() {
        let document = PDFDocument()
        for size in [NSSize(width: 612, height: 792), NSSize(width: 842, height: 595)] {
            let page = PDFPage()
            page.setBounds(NSRect(origin: .zero, size: size), for: .mediaBox)
            document.insert(page, at: document.pageCount)
        }
        let overlay = PageOverviewOverlayView(document: document, selectedIndex: 0, columns: 3)
        overlay.setFrameSize(NSSize(width: 1000, height: 700))
        let compact = overlay.paperSize(for: 0)
        #expect(abs(compact.width / compact.height - 612.0 / 792) < 0.001)
        overlay.setFrameSize(NSSize(width: 1400, height: 1000))
        let large = overlay.paperSize(for: 0)
        let landscape = overlay.paperSize(for: 1)
        #expect(large.height > compact.height + 250)
        #expect(large.height == 896)
        #expect(abs(landscape.width / landscape.height - 842.0 / 595) < 0.001)
        #expect(landscape.width <= (1400 - 48) * 0.78)
    }

    @Test
    func rapidRowNavigationRetainsDepartingPaperAndPointerSelectionUsesController() async throws {
        _ = NSApplication.shared
        let document = PDFDocument()
        for index in 0..<12 {
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            document.insert(page, at: index)
        }
        let overlay = PageOverviewOverlayView(document: document, selectedIndex: 0, columns: 3)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = overlay
        window.orderFront(nil)
        defer { overlay.dismiss(animated: false); window.contentView = nil; window.close() }
        let controller = PageOverviewController(overlay: overlay, originalIndex: 0,
                                              selectedIndex: 0, pageCount: 12, columns: 3)
        try await Task.sleep(for: .milliseconds(350))
        controller.move(.nextRow)
        controller.move(.nextRow)
        #expect(controller.selectedIndex == 6)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(overlay.layer?.sublayers?.contains { $0.name == "page-0" } == true)
        }
        overlay.onSelectPage?(5)
        #expect(controller.selectedIndex == 5)
        overlay.onSelectPage?(-1)
        #expect(controller.selectedIndex == 0)
        overlay.onSelectPage?(99)
        #expect(controller.selectedIndex == 11)
        let preservesFocus = overlay.subviews.compactMap { $0 as? NSButton }.allSatisfy { $0.refusesFirstResponder }
        #expect(preservesFocus)
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(500))
        let paperCount = overlay.layer?.sublayers?.filter { $0.name?.hasPrefix("page-") == true }.count
        #expect(paperCount == 2)
    }
}
