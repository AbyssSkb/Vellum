import SwiftUI

struct ReaderStack: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            if appState.tabs.isEmpty {
                EmptyReader()
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
    @EnvironmentObject private var appState: AppState
    @State private var isOpenHovered = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(TokyoNight.mutedColor.opacity(0.8))
                .accessibilityHidden(true)

            Button {
                appState.openPanel(mode: AppPreferences.defaultPDFOpenMode())
            } label: {
                HStack(spacing: 24) {
                    Text(language.text(.openPDF))
                        .font(.system(size: 13, weight: .medium))
                    Text("⌘O")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(TokyoNight.backgroundDeepColor.opacity(0.6))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(TokyoNight.backgroundDeepColor)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(TokyoNight.foregroundColor.opacity(isOpenHovered ? 1 : 0.92),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(TokyoNight.blueColor.opacity(isOpenHovered ? 0.9 : 0.25), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: [.command])
            .onHover { isOpenHovered = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TokyoNight.panelColor)
        .background(KeyboardCapture(appState: appState))
    }
}
