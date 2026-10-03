import SwiftUI

struct SidebarToggleButton: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var isHovered = false

    var body: some View {
        Button {
            appState.toggleOutlineSidebar()
        } label: {
            SidebarToggleGlyph(isOpen: appState.isOutlineVisible)
                .foregroundStyle(
                    appState.isOutlineVisible
                        ? TokyoNight.foregroundColor
                        : TokyoNight.mutedColor
                )
                .frame(width: 30, height: 30)
                .background(isHovered ? TokyoNight.panelElevatedColor : .clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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

struct SidebarToggleGlyph: View {
    let isOpen: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .stroke(lineWidth: 1.4)
                .frame(width: 16, height: 13)

            if isOpen {
                RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                    .fill()
                    .frame(width: 5, height: 9)
                    .offset(x: -4.2)

                Path { path in
                    path.move(to: CGPoint(x: 17.4, y: 11.1))
                    path.addLine(to: CGPoint(x: 14.7, y: 15))
                    path.addLine(to: CGPoint(x: 17.4, y: 18.9))
                }
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 13.3, y: 11.1))
                    path.addLine(to: CGPoint(x: 16, y: 15))
                    path.addLine(to: CGPoint(x: 13.3, y: 18.9))
                }
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
