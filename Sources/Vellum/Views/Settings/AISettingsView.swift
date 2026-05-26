import SwiftUI

struct AISettingsView: View {
    var body: some View {
        TabView {
            AISettingsDetailView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            ShortcutSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 620, height: 520)
    }
}
