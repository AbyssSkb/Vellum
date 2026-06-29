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
            window.isMovableByWindowBackground = true
            window.setContentBorderThickness(0, for: .minY)
            window.setContentBorderThickness(0, for: .maxY)
            window.backgroundColor = TokyoNight.background
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.backgroundColor = TokyoNight.background.cgColor
            window.contentView?.layer?.masksToBounds = true
            window.contentView?.layer?.cornerRadius = 10
            window.contentView?.superview?.wantsLayer = true
            window.contentView?.superview?.layer?.backgroundColor = TokyoNight.background.cgColor
            window.standardWindowButton(.zoomButton)?.isEnabled = false
        }
    }
}
