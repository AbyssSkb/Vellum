import SwiftUI

struct AIConnectionStatusRow: View {
    @Environment(\.appUILanguage) private var language
    let status: AIConnectionStatus
    let isBusy: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(language.text(.loading))
            } else {
                Image(systemName: status.systemImage)
                    .foregroundStyle(Color(nsColor: status.color))
                    .accessibilityHidden(true)
            }

            Text(status.text(language: language))
                .font(.system(size: 12.5, weight: status.isIdle ? .regular : .medium))
                .foregroundStyle(status.isIdle ? TokyoNight.mutedColor : TokyoNight.foregroundColor)
                .textSelection(.enabled)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
