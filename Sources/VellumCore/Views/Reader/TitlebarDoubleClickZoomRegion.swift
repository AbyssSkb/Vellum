@preconcurrency import AppKit
import SwiftUI

struct TitlebarDoubleClickZoomRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> TitlebarDoubleClickZoomView {
        TitlebarDoubleClickZoomView()
    }

    func updateNSView(_ nsView: TitlebarDoubleClickZoomView, context: Context) {
        nsView.installMonitorIfNeeded()
    }
}

final class TitlebarDoubleClickZoomView: NSView {
    private var eventMonitor: Any?
    private weak var monitoredWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            removeMonitor()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func installMonitorIfNeeded() {
        guard window !== monitoredWindow else { return }
        removeMonitor()
        guard let window else { return }
        monitoredWindow = window

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseDown(event) ?? event
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        monitoredWindow = nil
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard event.clickCount == 2,
              let window,
              event.window === window,
              !isPointInStandardWindowButton(event.locationInWindow, window: window) else {
            return event
        }

        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return event }

        window.performZoom(nil)
        return nil
    }

    private func isPointInStandardWindowButton(_ point: NSPoint, window: NSWindow) -> Bool {
        [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ]
        .compactMap { $0 }
        .contains { button in
            let pointInButton = button.convert(point, from: nil)
            return button.bounds.insetBy(dx: -4, dy: -4).contains(pointInButton)
        }
    }
}
