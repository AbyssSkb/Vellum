import SwiftUI

struct EmptyReaderLayout {
    let scale: CGFloat
    var inset: CGFloat { 8 * scale }
    var cornerRadius: CGFloat { 14 - inset }

    init(size: CGSize) {
        scale = min(max(min(size.width / 900, size.height / 650), 0.9), 1.2)
    }
}

struct ReaderStack: View {
    @EnvironmentObject private var appState: AppState
    let emptyScale: CGFloat

    var body: some View {
        ZStack {
            if appState.tabs.isEmpty {
                EmptyReader(scale: emptyScale)
            } else {
                ForEach(appState.tabs) { tab in
                    let isSelected = tab.id == appState.selectedTabID

                    if let document = tab.document {
                        PDFReader(
                            tabID: tab.id,
                            document: document,
                            snapshot: tab.snapshot,
                            isActive: isSelected
                        )
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                        .accessibilityHidden(!isSelected)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyReader: View {
    @Environment(\.appUILanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @State private var isOpenHovered = false
    let scale: CGFloat

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                Image(systemName: "doc.text")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(TokyoNight.mutedColor.opacity(0.8))
                    .accessibilityHidden(true)

                Button {
                    appState.openPanel(mode: AppPreferences.defaultPDFOpenMode())
                } label: {
                    HStack(spacing: 14) {
                        Text(language.text(.openPDF))
                            .font(.system(size: 12.5, weight: .medium))
                        Text("O")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(TokyoNight.mutedColor)
                            .frame(width: 18, height: 18)
                            .background(TokyoNight.foregroundColor.opacity(0.045),
                                        in: RoundedRectangle(cornerRadius: 4))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(TokyoNight.foregroundColor.opacity(0.92))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(isOpenHovered ? TokyoNight.panelElevatedColor : TokyoNight.backgroundColor,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isOpenHovered ? TokyoNight.blueColor.opacity(0.55)
                                          : TokyoNight.borderColor, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .onHover { isOpenHovered = $0 }
            }
            .geometryGroup()
            .scaleEffect(scale)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .animation(
                reduceMotion || appState.readerWindow?.inLiveResize == true ? nil : .smooth(duration: 0.18),
                value: geometry.size
            )
        }
        .background(TokyoNight.panelColor)
        .background(KeyboardCapture(appState: appState))
    }
}
