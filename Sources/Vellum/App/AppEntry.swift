import SwiftUI
import VellumCore

@main
struct VellumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppUILanguage.systemDefault().rawValue
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("Vellum", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(language.text(.checkForUpdatesMenu)) {
                    appDelegate.checkForUpdates()
                }
            }

            CommandGroup(replacing: .appTermination) {
                Button(language.text(.quitVellum)) {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }

            CommandGroup(replacing: .appSettings) {
                Button(language.text(.settingsMenu)) {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(replacing: .newItem) {
                Button(language.text(.openMenu)) {
                    appState.openPanel(mode: DefaultOpenModePreference.saved().pdfOpenMode)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(after: .newItem) {
                Button(language.text(.closeTab)) {
                    appState.closeSelectedTab()
                }
                .keyboardShortcut("w", modifiers: [.command])
            }

            CommandMenu(language.text(.navigate)) {
                Button(language.text(.nextTab)) {
                    appState.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command])

                Button(language.text(.previousTab)) {
                    appState.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command])
            }
        }
    }

    private var language: AppUILanguage {
        AppUILanguage.saved(rawValue: appLanguage)
    }
}
