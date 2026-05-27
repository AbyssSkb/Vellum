import SwiftUI

public struct AISettingsView: View {
    public init() {}

    public var body: some View {
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
