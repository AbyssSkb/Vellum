import SwiftUI

struct TabButton: View {
    @EnvironmentObject private var appState: AppState
    let tab: PDFTab
    let isSelected: Bool
    let width: CGFloat

    var body: some View {
        HStack(spacing: width < 70 ? 4 : 7) {
            ClippedTabTitle(title: tab.title, isSelected: isSelected)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

            if isSelected, width >= 90 {
                Button {
                    appState.closeSelectedTab()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(TokyoNight.foregroundColor.opacity(0.68))
                        .frame(width: 16, height: 16)
                        .background(TokyoNight.panelColor.opacity(0.85))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close Tab")
                .accessibilityLabel("Close \(tab.title)")
            }
        }
        .padding(.leading, width < 70 ? 6 : 12)
        .padding(.trailing, isSelected && width >= 90 ? 8 : (width < 70 ? 6 : 12))
        .frame(width: width, height: 32)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            if !isSelected {
                appState.selectTab(tab.id)
            }
        }
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction {
            appState.selectTab(tab.id)
        }
        .background(isSelected ? TokyoNight.panelElevatedColor : TokyoNight.panelColor.opacity(0.58))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? TokyoNight.blueColor.opacity(0.38) : TokyoNight.borderColor.opacity(0.32), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(TokyoNight.blueColor.opacity(0.9))
                    .frame(height: 2)
                    .padding(.horizontal, 10)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
