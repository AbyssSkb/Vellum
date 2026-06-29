@preconcurrency import AppKit
import SwiftUI

struct TitlebarDragRegion: NSViewRepresentable {
    let hasOpenDocuments: Bool

    func makeNSView(context: Context) -> TitlebarDragView {
        TitlebarDragView()
    }

    func updateNSView(_ nsView: TitlebarDragView, context: Context) {
        nsView.hasOpenDocuments = hasOpenDocuments
    }
}

final class TitlebarDragView: NSView {
    var hasOpenDocuments = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        allowedTouchTypes = [.direct, .indirect]
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point),
              let window,
              isPointDraggable(point, window: window) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            window.performZoom(nil)
        } else {
            window.performDrag(with: event)
        }
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

        if hasOpenDocuments {
            return point.x < 84
        }

        return true
    }
}
