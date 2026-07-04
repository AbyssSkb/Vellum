import SwiftUI

struct OutlineSidebar: View {
    @Environment(\.appUILanguage) private var language
    @EnvironmentObject private var appState: AppState
    let tab: PDFTab?

    var body: some View {
        VStack(spacing: 0) {
            if let document = tab?.document {
                let items = PDFOutlineBuilder.items(for: document)
                OutlineSidebarHeader()
                TokyoNightDivider(axis: .horizontal)

                if items.isEmpty {
                    OutlinePlaceholder(text: language.text(.noContents))
                } else {
                    PDFOutlineView(
                        items: items,
                        focusGeneration: appState.outlineFocusGeneration,
                        appState: appState
                    )
                }
            } else {
                OutlineSidebarHeader()
                TokyoNightDivider(axis: .horizontal)
                OutlinePlaceholder(text: language.text(.noDocument))
            }
        }
        .background {
            ZStack {
                SidebarVisualEffectBackground()
                TokyoNight.backgroundDeepColor.opacity(0.46)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(TokyoNight.borderColor.opacity(0.28))
                .frame(width: 1)
        }
    }
}

struct OutlineSidebarHeader: View {
    @Environment(\.appUILanguage) private var language

    var body: some View {
        HStack(spacing: 8) {
            Text(language.text(.contents))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(TokyoNight.foregroundColor)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TokyoNight.backgroundDeepColor.opacity(0.34))
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
