import SwiftUI

struct TabStrip: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    private let preferredTabWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(width: 84)
                .accessibilityHidden(true)

            SidebarToggleButton()

            GeometryReader { geometry in
                let tabWidth = tabWidth(
                    availableWidth: geometry.size.width,
                    tabCount: appState.tabs.count
                )

                HStack(spacing: 0) {
                    ForEach(Array(appState.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabButton(
                            tab: tab,
                            isSelected: tab.id == appState.selectedTabID,
                            width: tabWidth
                        )
                        .overlay(alignment: .trailing) {
                            if tab.id != appState.selectedTabID,
                               index + 1 < appState.tabs.count,
                               appState.tabs[index + 1].id != appState.selectedTabID {
                                Rectangle()
                                    .fill(TokyoNight.borderColor.opacity(0.7))
                                    .frame(width: 1, height: 22)
                                    .offset(x: 0.5)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: 46)
            .padding(.leading, appState.isOutlineVisible ? 122 : 0)
            .layoutPriority(1)

            HighlightToolbar()
                .padding(.trailing, 10)
        }
        .frame(height: 46)
        .background(TokyoNight.backgroundDeepColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.text(.filesAndTabs))
    }

    private func tabWidth(availableWidth: CGFloat, tabCount: Int) -> CGFloat {
        guard tabCount > 0 else { return 0 }

        return min(preferredTabWidth, max(0, availableWidth) / CGFloat(tabCount))
    }
}
