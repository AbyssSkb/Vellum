@preconcurrency import AppKit
import VellumCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        DispatchQueue.main.async {
            self.closeDuplicateMainWindows()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        OpenURLRelay.shared.open(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        OpenURLRelay.shared.open([URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        OpenURLRelay.shared.open(filenames.map(URL.init(fileURLWithPath:)))
        sender.reply(toOpenOrPrint: .success)
    }

    private func closeDuplicateMainWindows() {
        let mainWindows = NSApp.windows.filter { window in
            window.title == "Vellum" && window.isVisible && !(window is NSPanel)
        }

        for window in mainWindows.dropFirst() {
            window.close()
        }
    }
}
