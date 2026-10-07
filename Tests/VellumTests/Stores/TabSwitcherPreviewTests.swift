@preconcurrency import AppKit
@preconcurrency import PDFKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Tab switcher previews")
struct TabSwitcherPreviewTests {
    @Test
    func previewsUseEachDocumentsLastReadingPageAndClampItsIndex() async throws {
        let first = PDFTab(url: nil, document: try document(colors: [.red, .green]),
                           snapshot: snapshot(pageIndex: 1))
        let second = PDFTab(url: nil, document: try document(colors: [.red, .blue]),
                            snapshot: snapshot(pageIndex: 99))
        let store = TabSwitcherPreviewStore()
        store.update(tabs: [first, second], maximumPixelSize: NSSize(width: 120, height: 160))
        try await wait { store.images.count == 2 }
        let firstColor = try color(of: #require(store.images[first.id]))
        let secondColor = try color(of: #require(store.images[second.id]))
        #expect(firstColor.greenComponent > 0.9)
        #expect(firstColor.greenComponent > firstColor.redComponent + 0.3)
        #expect(secondColor.blueComponent > 0.9)
        #expect(secondColor.redComponent < 0.1)
    }

    @Test
    func replacementPagesAndLargerViewsRefreshWhileAdequatePreviewsAreReused() async throws {
        var tab = PDFTab(url: nil, document: try document(colors: [.red, .green]))
        let store = TabSwitcherPreviewStore()
        let size = NSSize(width: 120, height: 160)
        store.update(tabs: [tab], maximumPixelSize: size)
        try await wait { store.images[tab.id] != nil }
        let original = try #require(store.images[tab.id])
        for pixels in [size, NSSize(width: 60, height: 80)] {
            store.update(tabs: [tab], maximumPixelSize: pixels)
            #expect(store.images[tab.id] === original)
        }

        tab.snapshot = snapshot(pageIndex: 1)
        store.update(tabs: [tab], maximumPixelSize: size)
        #expect(store.images[tab.id] == nil)
        try await wait { store.images[tab.id] != nil }
        #expect(try color(of: #require(store.images[tab.id])).greenComponent > 0.9)

        tab.document = try document(colors: [.blue])
        store.update(tabs: [tab], maximumPixelSize: size)
        #expect(store.images[tab.id] == nil)
        try await wait { store.images[tab.id] != nil }
        let replacement = try #require(store.images[tab.id])
        #expect(try color(of: replacement).blueComponent > 0.9)
        store.update(tabs: [tab], maximumPixelSize: NSSize(width: 240, height: 320))
        #expect(store.images[tab.id] === replacement)
        try await wait { store.images[tab.id] !== replacement }
        #expect(store.images[tab.id]?.representations.first?.pixelsWide == 240)

        store.update(tabs: [], maximumPixelSize: size)
        #expect(store.images.isEmpty)
        store.update(tabs: [tab], maximumPixelSize: size)
        store.cancel()
        try await Task.sleep(for: .milliseconds(80))
        #expect(store.images.isEmpty)
    }

    private func snapshot(pageIndex: Int) -> ReaderSnapshot {
        var value = ReaderSnapshot.initial
        value.pageIndex = pageIndex
        return value
    }

    private func wait(until loaded: () -> Bool) async throws {
        for _ in 0..<150 {
            if loaded() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(loaded(), "The preview did not finish rendering")
    }

    private func color(of image: NSImage) throws -> NSColor {
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        return try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
    }

    private func document(colors: [NSColor]) throws -> PDFDocument {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 120, height: 160)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for color in colors {
            context.beginPDFPage(nil)
            context.setFillColor(color.cgColor)
            context.fill(mediaBox)
            context.endPDFPage()
        }
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }
}
