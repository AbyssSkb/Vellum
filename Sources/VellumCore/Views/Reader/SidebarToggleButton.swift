import SwiftUI

struct SidebarToggleButton: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var isHovered = false

    var body: some View {
        Button {
            appState.toggleOutlineSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(
                    appState.isOutlineVisible
                        ? TokyoNight.blueColor
                        : TokyoNight.mutedColor
                )
                .frame(width: 30, height: 30)
                .background(isHovered ? TokyoNight.panelElevatedColor : appState.isOutlineVisible ? TokyoNight.selectionColor.opacity(0.45) : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(language.text(.toggleContents))
        .accessibilityLabel(language.text(.toggleContentsSidebar))
        .accessibilityValue(language.text(appState.isOutlineVisible ? .sidebarOpen : .sidebarClosed))
        .accessibilityHint(language.text(.toggleContentsHint))
        .onHover { isHovered = $0 }
    }
}
