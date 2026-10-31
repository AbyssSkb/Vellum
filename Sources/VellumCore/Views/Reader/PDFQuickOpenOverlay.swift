import SwiftUI

struct PDFQuickOpenOverlay: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appUILanguage) private var language
    @ObservedObject var search: PDFQuickOpenSearch
    @State private var selectedURL: URL?

    private var selection: URL? { selectedURL ?? search.results.first }

    private var message: String? {
        switch search.failure {
        case .fzfMissing: return language.text(.fzfRequired)
        case .indexUnavailable: return language.text(.pdfIndexUnavailable)
        case .matchingFailed(let reason): return language.text(.pdfSearchFailed(reason))
        case nil:
            if search.hasFolderAccessFailure { return language.text(.pdfFolderAccessUnavailable) }
            if search.isLoading { return language.text(.loadingPDFFiles) }
            return search.results.isEmpty && !search.isSearching ? language.text(.noMatchingPDFFiles) : nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VellumColors.backgroundDeepColor.opacity(0.48)
                    .contentShape(Rectangle())
                    .onTapGesture { appState.hidePDFQuickOpen() }

                VStack(spacing: 0) {
                    header
                    VellumDivider(axis: .horizontal)
                    resultsList
                        .frame(height: max(72, min(404, geometry.size.height - 196)))
                }
                .frame(maxWidth: 680)
                .background(VellumColors.panelColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(VellumColors.borderColor, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.26), radius: 18, y: 8)
                .padding(.horizontal, 28)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, min(76, geometry.size.height * 0.12))
            }
        }
        .onChange(of: search.query) { _, _ in selectedURL = nil }
        .onChange(of: search.results) { _, urls in
            if let selectedURL, urls.contains(selectedURL) { return }
            selectedURL = urls.first
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(VellumColors.mutedColor)
                .accessibilityHidden(true)
            ListSearchField(
                text: $search.query,
                placeholder: language.text(.searchPDFFiles),
                font: .systemFont(ofSize: 15, weight: .regular),
                canFocus: { [weak appState] in appState?.isPDFQuickOpenPresented == true },
                onMoveUp: { moveSelection(-1) },
                onMoveDown: { moveSelection(1) },
                onCommit: { if let selection { open(selection) } },
                onCancel: { appState.hidePDFQuickOpen() }
            )
            .frame(height: 32)
            Text("\(search.results.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(VellumColors.mutedColor)
                .frame(width: 40, alignment: .trailing)
            ListCloseButton { appState.hidePDFQuickOpen() }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(VellumColors.backgroundColor)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if let message {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(search.failure != nil || search.hasFolderAccessFailure
                                             ? VellumColors.redColor : VellumColors.mutedColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(.horizontal, 12)
                    }
                    ForEach(search.results, id: \.self) { url in
                        Button { open(url) } label: {
                            PDFQuickOpenRow(url: url, isSelected: url == selection)
                        }
                        .buttonStyle(.plain)
                        .id(url)
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, url in
                if let url { proxy.scrollTo(url, anchor: .center) }
            }
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !search.results.isEmpty else { return }
        let index = selection.flatMap { search.results.firstIndex(of: $0) } ?? 0
        selectedURL = search.results[min(max(0, index + delta), search.results.count - 1)]
    }

    private func open(_ url: URL) {
        guard !search.isSearching else { return }
        appState.openPDFQuickOpenResult(url)
    }
}

private struct PDFQuickOpenRow: View {
    let url: URL
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(VellumColors.mutedColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(VellumColors.foregroundColor)
                    .lineLimit(1)
                Text(url.deletingLastPathComponent().path)
                    .font(.system(size: 11))
                    .foregroundStyle(VellumColors.mutedColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(isSelected ? VellumColors.selectionColor.opacity(0.6)
                    : isHovered ? VellumColors.panelElevatedColor.opacity(0.4) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(url.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityValue(url.deletingLastPathComponent().path)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
