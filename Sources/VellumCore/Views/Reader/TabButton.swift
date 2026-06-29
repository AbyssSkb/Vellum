import SwiftUI

struct TabButton: View {
    @EnvironmentObject private var appState: AppState
    let tab: PDFTab
    let isSelected: Bool
    let width: CGFloat
    @State private var isHovered = false
    @State private var isCloseHovered = false

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
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(TokyoNight.foregroundColor.opacity(isCloseHovered ? 0.95 : 0.68))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(isCloseHovered ? TokyoNight.redColor.opacity(0.22) : Color.clear)
                        )
                        .overlay {
                            Circle()
                                .stroke(isCloseHovered ? TokyoNight.redColor.opacity(0.48) : Color.clear, lineWidth: 1)
                        }
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close Tab")
                .accessibilityLabel("Close \(tab.title)")
                .onHover { isCloseHovered = $0 }
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
        .background(
            isSelected
                ? TokyoNight.panelElevatedColor
                : TokyoNight.panelColor.opacity(isHovered ? 0.76 : 0.58)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected
                        ? TokyoNight.blueColor.opacity(isHovered ? 0.52 : 0.38)
                        : TokyoNight.borderColor.opacity(isHovered ? 0.46 : 0.32),
                    lineWidth: 1
                )
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
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.1), value: isCloseHovered)
    }
}
