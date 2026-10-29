@preconcurrency import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import VellumCore

@MainActor
@Suite("Window chrome")
struct WindowChromeTests {
    @Test
    func outlineSidebarHasASquareTopLeftCorner() async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let appState = makeTestAppState(defaults: preferences.defaults)
        _ = appState.tabStore.openInNewTabs([
            PDFTab(url: URL(fileURLWithPath: "/tmp/outline-corner-test.pdf"), document: PDFDocument())
        ])
        appState.isOutlineVisible = true
        let host = NSHostingView(rootView: ContentView().environmentObject(appState))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await nextTestMainQueueTurn()
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scaleY = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        let top = try #require(bitmap.colorAt(x: 0, y: Int(48 * scaleY))?.usingColorSpace(.sRGB))
        let edge = try #require(bitmap.colorAt(x: 0, y: Int(65 * scaleY))?.usingColorSpace(.sRGB))
        #expect(abs(top.redComponent - edge.redComponent) < 0.02)
        #expect(abs(top.greenComponent - edge.greenComponent) < 0.02)
        #expect(abs(top.blueComponent - edge.blueComponent) < 0.02)
    }
    @Test(arguments: [false, true])
    func readerCornersRevealTheTitleBarBackground(hasDocument: Bool) async throws {
        _ = NSApplication.shared
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let appState = makeTestAppState(defaults: preferences.defaults)
        if hasDocument {
            _ = appState.tabStore.openInNewTabs([
                PDFTab(url: URL(fileURLWithPath: "/tmp/corner-test.pdf"), document: PDFDocument())
            ])
        }
        let host = NSHostingView(rootView: ContentView().environmentObject(appState))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await nextTestMainQueueTurn()
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        func pixel(x: CGFloat, fromTop: CGFloat) throws -> NSColor {
            try #require(bitmap.colorAt(x: Int(x * scaleX), y: Int(fromTop * scaleY))?.usingColorSpace(.sRGB))
        }
        for x in [CGFloat(4), host.bounds.width - 4] {
            let title = try pixel(x: x, fromTop: 40)
            let corner = try pixel(x: x, fromTop: 48)
            #expect(abs(title.redComponent - corner.redComponent) < 0.01)
            #expect(abs(title.greenComponent - corner.greenComponent) < 0.01)
            #expect(abs(title.blueComponent - corner.blueComponent) < 0.01)
        }
    }

    @Test
    func smallWindowResizesKeepTheEmptyReaderInsetContinuous() {
        let before = EmptyReaderLayout(size: CGSize(width: 1100, height: 690.5))
        let after = EmptyReaderLayout(size: CGSize(width: 1100, height: 690.75))
        #expect(after.inset > before.inset)
        #expect(after.inset - before.inset < 0.01)
    }

    @Test(arguments: [640.0, 1400.0])
    func tabTitlesShareTheTrafficLightCenterAtDifferentWindowSizes(width: Double) async throws {
        let fixture = try TopBarFixture(width: width)
        defer { fixture.close() }
        try await fixture.ready()

        for title in fixture.titles {
            let frame = title.textField.convert(title.textField.bounds, to: fixture.host)
            let centerFromTop = fixture.host.isFlipped
                ? frame.midY - fixture.host.bounds.minY : fixture.host.bounds.maxY - frame.midY
            #expect(abs(centerFromTop - 23) <= 0.5)
        }
    }

    @Test
    func compactTopBarKeepsItsControlsClickableAndItsFreeSpaceDraggable() async throws {
        let fixture = try TopBarFixture(width: 960)
        defer { fixture.close() }
        try await fixture.ready()

        let firstTab = try #require(fixture.appState.tabs.first)
        let firstTitle = try #require(fixture.titles.first { $0.title == firstTab.title })
        let titleFrame = firstTitle.convert(firstTitle.bounds, to: fixture.host)
        var receivedEvents: [String] = []
        let monitor = try #require(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
            MainActor.assumeIsolated {
                let content = fixture.window.contentView
                let hit = content.flatMap { $0.hitTest($0.convert(event.locationInWindow, from: nil)) }
                receivedEvents.append("type=\(event.type.rawValue) number=\(event.eventNumber) timestamp=\(event.timestamp) window=\(event.windowNumber) location=\(event.locationInWindow) hit=\(String(describing: hit))")
            }
            return event
        })
        defer { NSEvent.removeMonitor(monitor) }
        try fixture.mouse([.leftMouseDown, .leftMouseUp], at: NSPoint(x: titleFrame.midX, y: titleFrame.midY))
        do {
            try await waitForTestCondition("The first tab is selected by clicking its title", dispatchAppKitEvents: true) {
                fixture.appState.selectedTabID == firstTab.id
            }
        } catch {
            print("Top bar click: active=\(NSApp.isActive) key=\(fixture.window.isKeyWindow) main=\(fixture.window.isMainWindow) screen=\(String(describing: NSScreen.screens.first?.frame)) frame=\(fixture.window.frame) host=\(fixture.host.frame) title=\(titleFrame) responder=\(String(describing: fixture.window.firstResponder)) posted=\(fixture.postedMouseEvents) received=\(receivedEvents)")
            throw error
        }
        await nextTestMainQueueTurn()
        fixture.host.layoutSubtreeIfNeeded()
        let selectedTitle = try #require(fixture.titles.first { $0.title == firstTab.title })
        let selectedFrame = selectedTitle.convert(selectedTitle.bounds, to: fixture.host)
        try fixture.mouse([.leftMouseDown, .leftMouseUp], at: NSPoint(x: selectedFrame.maxX + 18, y: selectedFrame.midY))
        try await waitForTestCondition("The selected tab's close button remains clickable", dispatchAppKitEvents: true) {
            fixture.appState.tabs.count == 1
        }

        try fixture.mouse([.leftMouseDown, .leftMouseUp], at: fixture.topPoint(x: 109))
        try await waitForTestCondition("The directory button remains clickable", dispatchAppKitEvents: true) {
            fixture.appState.isOutlineVisible
        }
        for (index, color) in HighlightColor.allCases.enumerated() {
            let x = fixture.host.bounds.width - fixture.edgeInset - 150 + CGFloat(index) * 32
            try fixture.mouse([.leftMouseDown, .leftMouseUp], at: fixture.topPoint(x: x))
            try await waitForTestCondition("The compact \(color.rawValue) color button remains clickable", dispatchAppKitEvents: true) {
                fixture.appState.selectedHighlightColor == color
            }
        }

        try fixture.mouse([.leftMouseDown, .leftMouseDragged, .leftMouseUp],
                          at: fixture.topPoint(x: fixture.host.bounds.width - 195))
        #expect(fixture.window.dragCount == 1)
        let colorX = fixture.host.bounds.width - fixture.edgeInset - 22
        try fixture.mouse([.leftMouseDown, .leftMouseDragged, .leftMouseUp], at: fixture.topPoint(x: colorX))
        #expect(fixture.window.dragCount == 1)
    }

    @Test
    func trafficLightsKeepTheReaderPlacementWithAndWithoutOpenTabs() async throws {
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
        let preferences = try TestPreferences()
        defer { preferences.cleanup() }
        let appState = makeTestAppState(defaults: preferences.defaults)
        // Native resizing must work even when this background view does not relayout.
        let chrome = WindowChromeConfigurator.ChromeView(frame: .zero)
        chrome.appState = appState
        window.contentView?.addSubview(chrome)
        window.orderFront(nil)
        await nextTestMainQueueTurn()

        func checkPlacement(centerFromTop: CGFloat, leftInset: CGFloat) {
            for index in buttons.indices {
                let button = buttons[index]
                let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                #expect(abs(frameView.bounds.maxY - center.y - centerFromTop) < 0.001)
                #expect(abs(button.frame.minX - leftInset - CGFloat(index) * 20) < 0.001)
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
            await nextTestMainQueueTurn()
            for size in [NSSize(width: 640, height: 480), NSSize(width: 900, height: 650),
                         NSSize(width: 1100, height: 690.5), NSSize(width: 1400, height: 950)] {
                window.setFrame(NSRect(origin: .zero, size: size), display: true)
                await nextTestMainQueueTurn()
                checkPlacement(centerFromTop: 23, leftInset: 22)
                #expect(titlebar.frame.height == originalTitlebarHeight)
                #expect(container.frame.height == originalContainerHeight)

                let unchangedFrame = window.frame
                window.titleVisibility = .visible
                window.titleVisibility = .hidden
                #expect(window.frame == unchangedFrame)
                await nextTestMainQueueTurn()
                checkPlacement(centerFromTop: 23, leftInset: 22)
                #expect(titlebar.frame.height == originalTitlebarHeight)
                #expect(container.frame.height == originalContainerHeight)
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
        await nextTestMainQueueTurn()
        await nextTestMainQueueTurn()
        #expect(frameChanges.count == 0)
    }

    @MainActor
    private final class TopBarFixture {
        let preferences: TestPreferences
        let appState: AppState
        let window: DragRecordingWindow
        let host: NSHostingView<AnyView>
        let edgeInset: CGFloat
        var postedMouseEvents: [String] = []
        private let previousHighlight: Any?

        init(width: CGFloat) throws {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            preferences = try TestPreferences()
            appState = makeTestAppState(defaults: preferences.defaults)
            previousHighlight = UserDefaults.standard.object(forKey: AppPreferenceKeys.defaultHighlightColor)
            _ = appState.tabStore.openInNewTabs(["Alpha", "Beta"].map {
                PDFTab(url: URL(fileURLWithPath: "/tmp/\($0).pdf"), document: nil)
            })
            let size = NSSize(width: width, height: 480)
            let screen = try #require(NSScreen.screens.first)
            let inset = EmptyReaderLayout(size: size).inset
            edgeInset = inset
            window = DragRecordingWindow(contentRect: NSRect(x: screen.frame.minX, y: screen.frame.maxY - size.height,
                                                             width: size.width, height: size.height),
                                         styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            host = NSHostingView(rootView: AnyView(
                VStack(spacing: 0) {
                    TabStrip(edgeInset: inset)
                    VellumColors.panelColor
                }
                .overlay(alignment: .top) { TitlebarDragRegion(hasOpenTabs: true).frame(height: 46) }
                .environmentObject(appState)
                .environment(\.appUILanguage, .english)
            ))
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        var titles: [PDFOutlineTitleView] {
            func collect(_ view: NSView) -> [PDFOutlineTitleView] {
                if let title = view as? PDFOutlineTitleView { return [title] }
                return view.subviews.flatMap(collect)
            }
            return collect(host)
        }

        func ready() async throws {
            try await waitForTestCondition("The real top bar is mounted in a key window", dispatchAppKitEvents: true) {
                self.host.layoutSubtreeIfNeeded()
                return NSApp.isActive && self.window.isKeyWindow && self.titles.count == 2 && self.titles.allSatisfy { $0.bounds.width > 0 }
            }
        }

        func topPoint(x: CGFloat) -> NSPoint {
            NSPoint(x: x, y: host.isFlipped ? 23 : host.bounds.maxY - 23)
        }

        func mouse(_ types: [NSEvent.EventType], at point: NSPoint) throws {
            let location = host.convert(point, to: nil)
            for type in types {
                let event = try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
                postedMouseEvents.append("type=\(event.type.rawValue) number=\(event.eventNumber) timestamp=\(event.timestamp) window=\(event.windowNumber) location=\(event.locationInWindow)")
                NSApp.postEvent(event, atStart: false)
            }
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        }

        func close() {
            host.rootView = AnyView(EmptyView())
            window.contentView = nil
            window.close()
            UserDefaults.standard.set(previousHighlight, forKey: AppPreferenceKeys.defaultHighlightColor)
            preferences.cleanup()
        }
    }

    @MainActor
    private final class DragRecordingWindow: NSWindow {
        var dragCount = 0
        override var canBecomeKey: Bool { true }
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
        override func performDrag(with event: NSEvent) { dragCount += 1 }
    }
}

@MainActor
private final class ChromeFrameChanges: NSObject {
    var count = 0

    @objc func record(_ notification: Notification) {
        count += 1
    }
}
