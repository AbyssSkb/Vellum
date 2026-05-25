@preconcurrency import AppKit
import SwiftUI

struct TabStrip: View {
    @EnvironmentObject private var appState: AppState
    private let preferredTabWidth: CGFloat = 220
    private let tabSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(width: 84)

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
        .background(TokyoNight.backgroundDeepColor)
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

struct SidebarToggleButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var isHovered = false

    var body: some View {
        Button {
            appState.toggleOutlineSidebar()
        } label: {
            SidebarToggleGlyph(isOpen: appState.isOutlineVisible)
                .foregroundStyle(TokyoNight.foregroundColor.opacity(isHovered ? 0.92 : 0.68))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Toggle Contents")
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

struct HighlightToolbar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 7) {
            ForEach(HighlightColor.allCases) { color in
                let isSelected = appState.selectedHighlightColor == color

                Button {
                    appState.selectHighlightColor(color)
                } label: {
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(TokyoNight.foregroundColor.opacity(0.14))
                                .frame(width: 31, height: 31)
                            Circle()
                                .stroke(TokyoNight.foregroundColor, lineWidth: 2.5)
                                .frame(width: 27, height: 27)
                        }

                        Circle()
                            .fill(color.swatchColor)
                            .frame(width: isSelected ? 20 : 12, height: isSelected ? 20 : 12)
                            .overlay(
                                Circle()
                                    .stroke(
                                        isSelected ? TokyoNight.backgroundDeepColor.opacity(0.9) : TokyoNight.borderColor.opacity(0.55),
                                        lineWidth: isSelected ? 1.5 : 1
                                    )
                            )
                    }
                    .frame(width: 32, height: 32)
                    .animation(.easeInOut(duration: 0.12), value: isSelected)
                }
                .buttonStyle(.plain)
                .help(color.helpText)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(TokyoNight.panelElevatedColor.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

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
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ClippedTabTitle: NSViewRepresentable {
    let title: String
    let isSelected: Bool

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(labelWithString: title)
        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 1
        textField.alignment = .left
        textField.isSelectable = false
        textField.allowsDefaultTighteningForTruncation = false
        textField.backgroundColor = .clear
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        textField.stringValue = title
        textField.font = .systemFont(ofSize: 12.5, weight: isSelected ? .semibold : .regular)
        textField.textColor = isSelected
            ? TokyoNight.foreground
            : TokyoNight.foreground.withAlphaComponent(0.76)
        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 1
        textField.alignment = .left
    }
}
