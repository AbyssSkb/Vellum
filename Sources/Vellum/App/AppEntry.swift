import SwiftUI
import VellumCore

@main
struct VellumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("Vellum", id: "main") {
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
