import SwiftUI

struct TabStrip: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    let edgeInset: CGFloat
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
                                    .fill(VellumColors.borderColor.opacity(0.55))
                                    .frame(width: 0.5, height: 16)
                                    .offset(x: 0.5)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 46)
            .padding(.leading, appState.isOutlineVisible ? 122 : 0)
            .layoutPriority(1)

            HighlightToolbar()
                .padding(.trailing, edgeInset)
        }
        .frame(height: 46)
        .background(VellumColors.backgroundDeepColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.text(.filesAndTabs))
    }

    private func tabWidth(availableWidth: CGFloat, tabCount: Int) -> CGFloat {
        guard tabCount > 0 else { return 0 }

        return min(preferredTabWidth, max(0, availableWidth) / CGFloat(tabCount))
    }
}
