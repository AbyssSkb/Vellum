import SwiftUI

struct TabStrip: View {
    @EnvironmentObject private var appState: AppState
    private let preferredTabWidth: CGFloat = 220
    private let tabSpacing: CGFloat = 2

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

                HStack(spacing: tabSpacing) {
                    ForEach(appState.tabs) { tab in
                        TabButton(
                            tab: tab,
                            isSelected: tab.id == appState.selectedTabID,
                            width: tabWidth
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: 34)
            .layoutPriority(1)

            HighlightToolbar()
                .padding(.trailing, 10)
        }
        .frame(height: 46)
        .background {
            ZStack {
                TokyoNight.backgroundDeepColor
                TitlebarDoubleClickZoomRegion()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tab Bar")
    }

    private func tabWidth(availableWidth: CGFloat, tabCount: Int) -> CGFloat {
        guard tabCount > 0 else { return 0 }

        let spacingWidth = tabSpacing * CGFloat(max(0, tabCount - 1))
        let preferredTotal = preferredTabWidth * CGFloat(tabCount) + spacingWidth
        guard preferredTotal > availableWidth else { return preferredTabWidth }

        let availableForTabs = max(0, availableWidth - spacingWidth)
        return availableForTabs / CGFloat(tabCount)
    }
}
