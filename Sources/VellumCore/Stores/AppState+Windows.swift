@preconcurrency import AppKit

extension AppState {
    public func closeCurrentWindow() {
        guard let keyWindow = NSApp.keyWindow else { return }
        if keyWindow === readerWindow {
            closeSelectedTab()
        } else {
            keyWindow.performClose(nil)
        }
    }
}
