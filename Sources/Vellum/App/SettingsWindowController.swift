@preconcurrency import AppKit
import SwiftUI
import VellumCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let contentSize = NSSize(width: 820, height: 680)

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = Self.contentSize
        window.contentMaxSize = Self.contentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        let hostingView = NSHostingView(rootView: AISettingsView())
        hostingView.frame = NSRect(origin: .zero, size: Self.contentSize)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.setContentSize(Self.contentSize)

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
