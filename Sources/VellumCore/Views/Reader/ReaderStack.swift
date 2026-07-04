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

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(TokyoNight.mutedColor)
                .accessibilityHidden(true)

            Text(language.text(.openPDF))
                .font(.title2.weight(.semibold))
                .foregroundStyle(TokyoNight.foregroundColor)

            Button {
                appState.openPanel(mode: DefaultOpenModePreference.saved().pdfOpenMode)
            } label: {
                Label(language.text(.chooseFile), systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command])
            .tint(TokyoNight.blueColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TokyoNight.backgroundColor)
        .background(KeyboardCapture(appState: appState))
    }
}
