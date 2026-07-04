@preconcurrency import AppKit
import SwiftUI

struct TitlebarDragRegion: NSViewRepresentable {
    let hasOpenTabs: Bool

    func makeNSView(context: Context) -> TitlebarDragView {
        TitlebarDragView()
    }

    func updateNSView(_ nsView: TitlebarDragView, context: Context) {
        nsView.hasOpenTabs = hasOpenTabs
    }
}

final class TitlebarDragView: NSView {
    var hasOpenTabs = false
    private var eventMonitor: Any?
    private var pendingDragEvent: NSEvent?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        allowedTouchTypes = [.direct, .indirect]
        installMonitor()
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

    private func installMonitor() {
        removeMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        pendingDragEvent = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }

        switch event.type {
        case .leftMouseDown:
            pendingDragEvent = isEventInDraggableTitlebar(event, window: window) ? event : nil
            if event.clickCount == 2, pendingDragEvent != nil {
                window.performZoom(nil)
                pendingDragEvent = nil
                return nil
            }
            return event
        case .leftMouseDragged:
            guard let pendingDragEvent else { return event }
            self.pendingDragEvent = nil
            window.performDrag(with: pendingDragEvent)
            return nil
        case .leftMouseUp:
            pendingDragEvent = nil
            return event
        default:
            return event
        }
    }

    private func isEventInDraggableTitlebar(_ event: NSEvent, window: NSWindow) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point) && isPointDraggable(point, window: window)
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

    private func isPointDraggable(_ point: NSPoint, window: NSWindow) -> Bool {
        let pointInWindow = convert(point, to: nil)
        guard !isPointInStandardWindowButton(pointInWindow, window: window) else { return false }

        guard hasOpenTabs else { return true }
        return !isPointInInteractiveTitlebarControl(point)
    }

    private func isPointInInteractiveTitlebarControl(_ point: NSPoint) -> Bool {
        let sidebarToggleRect = NSRect(x: 94, y: 8, width: 34, height: 34)
        let highlightToolbarRect = NSRect(x: bounds.maxX - 210, y: 4, width: 202, height: 40)

        return sidebarToggleRect.contains(point)
            || highlightToolbarRect.contains(point)
    }
}
