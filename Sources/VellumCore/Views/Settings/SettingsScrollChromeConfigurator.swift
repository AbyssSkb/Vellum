@preconcurrency import AppKit
import SwiftUI

struct SettingsScrollChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView {
        ChromeView()
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.configureScrollView()
    }

    final class ChromeView: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureScrollView()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureScrollView()
        }

        func configureScrollView() {
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.nearestScrollView() else { return }
                scrollView.drawsBackground = false
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.scrollerStyle = .overlay
                scrollView.verticalScrollElasticity = .allowed
            }
        }

        private func nearestScrollView() -> NSScrollView? {
            var view: NSView? = superview
            while let candidate = view {
                if let scrollView = candidate as? NSScrollView {
                    return scrollView
                }
                view = candidate.superview
            }
            return nil
        }
    }
}
