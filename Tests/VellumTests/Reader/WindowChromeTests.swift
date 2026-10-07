@preconcurrency import AppKit
import Testing
@testable import VellumCore

@MainActor
@Suite("Window chrome")
struct WindowChromeTests {
    @Test
    func trafficLightsStayInsideTheEmptyPanelAndRestoreTheReaderTitlebar() async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let buttons = try [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .map { try #require(window.standardWindowButton($0)) }
        let titlebar = try #require(buttons.first?.superview)
        let container = try #require(titlebar.superview)
        let frameView = try #require(container.superview)
        let originalTitlebarHeight = titlebar.frame.height
        let originalContainerHeight = container.frame.height
        let defaults = try #require(UserDefaults(suiteName: "WindowChromeTests.\(UUID().uuidString)"))
        let appState = AppState(
            sessionDefaults: defaults,
            keyboardController: KeyboardController(installsKeyMonitor: false, installsOpenURLObserver: false)
        )
        // Native resizing must work even when this background view does not relayout.
        let chrome = WindowChromeConfigurator.ChromeView(frame: .zero)
        chrome.appState = appState
        window.contentView?.addSubview(chrome)
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(30))

        func checkPlacement(centerFromTop: CGFloat, leftInset: CGFloat) {
            for index in buttons.indices {
                let button = buttons[index]
                let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                #expect(frameView.bounds.maxY - center.y == centerFromTop)
                #expect(button.frame.minX == leftInset + CGFloat(index) * 20)
                #expect(frameView.hitTest(center) === button)
            }
        }

        for hasTabs in [false, true, false, true] {
            if hasTabs {
                _ = appState.tabStore.openInNewTabs([
                    PDFTab(url: URL(fileURLWithPath: "/tmp/chrome-test.pdf"), document: nil)
                ])
            } else {
                _ = appState.tabStore.closeSelectedTab()
            }
            chrome.configureWindow()
            try await Task.sleep(for: .milliseconds(30))
            for size in [NSSize(width: 640, height: 480), NSSize(width: 900, height: 650), NSSize(width: 1400, height: 950)] {
                window.setFrame(NSRect(origin: .zero, size: size), display: true)
                try await Task.sleep(for: .milliseconds(30))
                let layout = EmptyReaderLayout(size: size)
                checkPlacement(centerFromTop: hasTabs ? 23 : layout.inset + 23,
                               leftInset: hasTabs ? 22 : layout.inset + 16)
                #expect(titlebar.frame.height == (hasTabs ? originalTitlebarHeight : 46))
                #expect(container.frame.height == (hasTabs ? originalContainerHeight : 46))

                let unchangedFrame = window.frame
                window.titleVisibility = .visible
                window.titleVisibility = .hidden
                #expect(window.frame == unchangedFrame)
                #expect(buttons[0].frame.minX == 7)
                try await Task.sleep(for: .milliseconds(30))
                checkPlacement(centerFromTop: hasTabs ? 23 : layout.inset + 23,
                               leftInset: hasTabs ? 22 : layout.inset + 16)
                #expect(titlebar.frame.height == (hasTabs ? originalTitlebarHeight : 46))
                #expect(container.frame.height == (hasTabs ? originalContainerHeight : 46))
            }
        }

        let frameChanges = ChromeFrameChanges()
        for view in [titlebar, container] + buttons {
            view.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                frameChanges, selector: #selector(ChromeFrameChanges.record),
                name: NSView.frameDidChangeNotification, object: view
            )
        }
        defer { NotificationCenter.default.removeObserver(frameChanges) }
        for _ in 0..<6 {
            titlebar.needsLayout = true
            titlebar.layoutSubtreeIfNeeded()
            container.needsLayout = true
            container.layoutSubtreeIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(frameChanges.count == 0)
    }
}

@MainActor
private final class ChromeFrameChanges: NSObject {
    var count = 0

    @objc func record(_ notification: Notification) {
        count += 1
    }
}
