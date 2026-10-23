import AppKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
struct ToastTests {
    @Test(arguments: [false, true])
    func toastRendersAboveSwiftUIContent(fullSizeContent: Bool) async throws {
        let window = makeWindow()
        defer { window.close() }
        if fullSizeContent { window.styleMask.insert(.fullSizeContentView) }
        let host = NSHostingView(rootView: Color.white)
        window.contentView = host
        window.orderFront(nil)
        #expect(host.bounds.width > 100 && host.bounds.height > 100)
        VellumToast.show("No links in view", in: window)
        try await Task.sleep(for: .milliseconds(250))
        let toast = try #require(currentToast(in: window))
        #expect(toast.frame.width > 100)
        #expect(toast.alphaValue > 0.9)
        #expect(toast.layer?.cornerRadius == toast.bounds.height / 2)
        #expect(host.bounds.contains(host.convert(toast.bounds, from: toast)))
        let frameView = try #require(host.superview)
        let bitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        let point = frameView.convert(NSPoint(x: 4, y: toast.bounds.midY), from: toast)
        let x = Int(point.x * CGFloat(bitmap.pixelsWide) / frameView.bounds.width)
        let y = Int((frameView.bounds.height - point.y) * CGFloat(bitmap.pixelsHigh) / frameView.bounds.height)
        let pixel = try #require(bitmap.colorAt(x: x, y: y))
        let rgb = try #require(pixel.usingColorSpace(.sRGB))
        #expect(rgb.redComponent < 0.4 && rgb.greenComponent < 0.4 && rgb.blueComponent < 0.4)
        let corner = frameView.convert(NSPoint(x: 4, y: 4), from: toast)
        let cornerPixel = try #require(bitmap.colorAt(
            x: Int(corner.x * CGFloat(bitmap.pixelsWide) / frameView.bounds.width),
            y: Int((frameView.bounds.height - corner.y) * CGFloat(bitmap.pixelsHigh) / frameView.bounds.height)
        )?.usingColorSpace(.sRGB))
        #expect(cornerPixel.redComponent > 0.8 && cornerPixel.greenComponent > 0.8 && cornerPixel.blueComponent > 0.8)

        window.setContentSize(NSSize(width: 320, height: 480))
        frameView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let resizedFrame = host.convert(toast.bounds, from: toast)
        #expect(host.bounds.width == 320)
        #expect(resizedFrame.width > 100 && resizedFrame.width <= 288)
        #expect(host.bounds.contains(resizedFrame))
        #expect(abs(resizedFrame.midX - host.bounds.midX) < 0.5)
        #expect(toast.layer?.cornerRadius == toast.bounds.height / 2)
    }

    @Test
    func messagesStayInTheirWindowAndLeaveKeyboardFocusAlone() throws {
        let first = makeWindow()
        let second = makeWindow()
        defer { first.close(); second.close() }
        let field = NSTextField(string: "typing")
        first.contentView?.addSubview(field)
        first.makeFirstResponder(field)
        let responder = first.firstResponder

        VellumToast.show("No links", in: first)

        let toast = try #require(currentToast(in: first))
        #expect(currentToast(in: second) == nil)
        #expect(first.firstResponder === responder)
        #expect(toast.hitTest(toast.frame.origin) == nil)
        #expect(!toast.acceptsFirstResponder)
        #expect(toast.frame.width > 50 && toast.frame.height >= 40)
        #expect(toast.frame.width <= 500)
        let contentView = try #require(first.contentView)
        #expect(toast.frame.maxY > contentView.bounds.midY)
    }

    @Test
    func replacementCancelsOldExpiryAndNewMessageExpires() async throws {
        let window = makeWindow()
        defer { window.close() }
        VellumToast.show("first", in: window)
        let first = try #require(currentToast(in: window))
        first.scheduleDismiss(after: 0.01)
        VellumToast.show("second", in: window)
        let second = try #require(currentToast(in: window))
        #expect(first.superview == nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(currentToast(in: window) === second)

        second.scheduleDismiss(after: 0.01)
        try await Task.sleep(for: .milliseconds(300))
        #expect(currentToast(in: window) == nil)
    }

    @Test
    func detailActionDismissesAndRunsOnceWithoutTruncatingItsButton() throws {
        let window = makeWindow(width: 320)
        defer { window.close() }
        var actions = 0
        VellumToast.show(String(repeating: "A useful error message. ", count: 20), kind: .error,
                         in: window, actionTitle: "Details") { actions += 1 }
        let toast = try #require(currentToast(in: window))
        let button = try #require(toast.subviews.compactMap { $0 as? NSButton }.first)
        let icon = try #require(toast.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(toast.layer?.cornerRadius == toast.bounds.height / 2)
        #expect(abs(icon.frame.midY - toast.bounds.midY) < 0.5)
        #expect(toast.frame.width > 100)
        #expect(toast.frame.width <= 288)
        #expect(toast.bounds.contains(button.frame))
        #expect(button.frame.width >= button.intrinsicContentSize.width)
        button.performClick(nil)
        button.performClick(nil)
        #expect(actions == 1)
        #expect(toast.superview == nil)
    }

    private func currentToast(in window: NSWindow) -> ToastView? {
        window.contentView?.superview?.subviews.compactMap { $0 as? ToastView }.first
    }

    private func makeWindow(width: CGFloat = 800) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                              styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}
