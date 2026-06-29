@preconcurrency import AppKit
import SwiftUI

struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    private static let contentSize = NSSize(width: 820, height: 680)

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
            window.contentMinSize = SettingsWindowChromeConfigurator.contentSize
            window.contentMaxSize = SettingsWindowChromeConfigurator.contentSize
            if abs(window.contentView?.frame.width ?? 0 - SettingsWindowChromeConfigurator.contentSize.width) > 0.5
                || abs(window.contentView?.frame.height ?? 0 - SettingsWindowChromeConfigurator.contentSize.height) > 0.5 {
                window.setContentSize(SettingsWindowChromeConfigurator.contentSize)
            }
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
