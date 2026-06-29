@preconcurrency import AppKit
import SwiftUI

struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView {
        ChromeView()
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.configureWindow()
    }

    final class ChromeView: WindowChromeConfigurator.ChromeView {
        override func configureWindow() {
            super.configureWindow()
            guard let window else { return }

            window.styleMask.remove(.resizable)
            window.setContentBorderThickness(0, for: .minY)
            window.setContentBorderThickness(0, for: .maxY)
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.masksToBounds = true
            window.contentView?.layer?.cornerRadius = 10
            window.standardWindowButton(.zoomButton)?.isEnabled = false
        }
    }
}
