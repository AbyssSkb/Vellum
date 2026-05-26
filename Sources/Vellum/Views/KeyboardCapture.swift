@preconcurrency import AppKit
import SwiftUI

struct KeyboardCapture: NSViewRepresentable {
    weak var appState: AppState?

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.appState = appState
        DispatchQueue.main.async {
            view.focus()
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.appState = appState
        DispatchQueue.main.async {
            nsView.focus()
        }
    }
}

final class KeyCaptureView: NSView {
    weak var appState: AppState?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focus()
    }

    func focus() {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if appState?.handleKeyEvent(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if appState?.handleKeyEvent(event) == true {
            return
        }
        super.keyUp(with: event)
    }
}
