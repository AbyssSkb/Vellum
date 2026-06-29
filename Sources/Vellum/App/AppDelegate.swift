@preconcurrency import AppKit
import VellumCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updateChecker = GitHubUpdateChecker()
    private var settingsWindowController: SettingsWindowController?
    private var checkForUpdatesObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        checkForUpdatesObserver = NotificationCenter.default.addObserver(
            forName: VellumAppNotification.checkForUpdatesRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForUpdates()
            }
        }
        if AppPreferences.automaticallyChecksForUpdates() {
            updateChecker.checkAutomaticallySoon()
        }
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

    @objc func checkForUpdates() {
        updateChecker.checkForUpdates(.manual)
    }

    func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }

    private func closeDuplicateMainWindows() {
        let mainWindows = NSApp.windows.filter { window in
            window.title == "Vellum" && window.isVisible && !(window is NSPanel)
        }

        for window in mainWindows.dropFirst() {
            window.close()
        }
    }

    deinit {
        if let checkForUpdatesObserver {
            NotificationCenter.default.removeObserver(checkForUpdatesObserver)
        }
    }
}
