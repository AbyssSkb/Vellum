import SwiftUI

struct OutlineSidebar: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    let tab: PDFTab?

    var body: some View {
        VStack(spacing: 0) {
            if let tab, let document = tab.document {
                let items = PDFOutlineBuilder.items(for: document, language: language)
                OutlineSidebarHeader(pageCount: document.pageCount)
                TokyoNightDivider(axis: .horizontal)
                    .opacity(0.5)

                ZStack {
                    PDFOutlineView(
                        items: items,
                        tabID: tab.id,
                        documentID: ObjectIdentifier(document),
                        focusGeneration: appState.outlineFocusGeneration,
                        appState: appState,
                        language: language
                    )
                    if items.isEmpty {
                        OutlinePlaceholder(text: language.text(.noContents))
                            .allowsHitTesting(false)
                    }
                }
            } else {
                OutlineSidebarHeader()
                TokyoNightDivider(axis: .horizontal)
                    .opacity(0.5)
                OutlinePlaceholder(text: language.text(.noDocument))
            }
        }
        .background {
            ZStack {
                SidebarVisualEffectBackground()
                TokyoNight.backgroundDeepColor.opacity(0.97)
            }
        }
    }
}

struct OutlineSidebarHeader: View {
    @Environment(\.appUILanguage) private var language
    var pageCount: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(TokyoNight.mutedColor)
                .accessibilityHidden(true)

            Text(language.text(.contents))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(TokyoNight.foregroundColor.opacity(0.8))

            Spacer(minLength: 8)
            if pageCount > 0 {
                Text(language.text(.outlinePageCount(pageCount)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(TokyoNight.mutedColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(TokyoNight.panelElevatedColor.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

struct OutlinePlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(TokyoNight.mutedColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
