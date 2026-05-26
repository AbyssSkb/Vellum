import SwiftUI

struct ShortcutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(ShortcutCatalog.groups) { group in
                    ShortcutGroupCard(group: group)
                }
            }
            .padding(20)
        }
    }
}
