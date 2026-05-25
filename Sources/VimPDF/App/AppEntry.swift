@preconcurrency import AppKit
import SwiftUI

@main
struct VimPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("VimPDF", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appState.openPanel(mode: .currentTab)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(after: .newItem) {
                Button("Close Tab") {
                    appState.closeSelectedTab()
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandMenu("Navigate") {
                Button("Next Tab") {
                    appState.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command])

                Button("Previous Tab") {
                    appState.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command])
            }
        }

        Settings {
            AISettingsView()
        }
    }
}

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
            window.title == "VimPDF" && window.isVisible && !(window is NSPanel)
        }

        for window in mainWindows.dropFirst() {
            window.close()
        }
    }
}

@MainActor
final class OpenURLRelay {
    static let shared = OpenURLRelay()

    private var handler: (([URL]) -> Void)?
    private var pendingURLs: [URL] = []
    private var recentDeliveries: [URL: TimeInterval] = [:]

    func activate(_ handler: @escaping ([URL]) -> Void) {
        self.handler = handler

        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        handler(urls)
    }

    func open(_ urls: [URL]) {
        let fileURLs = uniqueFreshFileURLs(urls)
        guard !fileURLs.isEmpty else { return }

        if let handler {
            handler(fileURLs)
        } else {
            pendingURLs.append(contentsOf: fileURLs)
        }
    }

    private func uniqueFreshFileURLs(_ urls: [URL]) -> [URL] {
        let now = Date.timeIntervalSinceReferenceDate
        recentDeliveries = recentDeliveries.filter { now - $0.value < 1.0 }

        var seen = Set<URL>()
        return urls.compactMap { url in
            guard url.isFileURL else { return nil }

            let normalizedURL = url.standardizedFileURL
            guard seen.insert(normalizedURL).inserted else { return nil }

            if let lastDelivery = recentDeliveries[normalizedURL], now - lastDelivery < 0.5 {
                return nil
            }

            recentDeliveries[normalizedURL] = now
            return normalizedURL
        }
    }
}
