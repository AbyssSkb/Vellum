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
                .font(.system(size: 12.5))
                .foregroundStyle(status.isIdle ? TokyoNight.mutedColor : TokyoNight.foregroundColor)
                .textSelection(.enabled)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TokyoNight.backgroundDeepColor.opacity(0.62), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(TokyoNight.borderColor.opacity(0.5), lineWidth: 1)
        }
    }
}
