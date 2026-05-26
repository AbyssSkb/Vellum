import SwiftUI

struct AIConnectionStatusRow: View {
    let status: AIConnectionStatus
    let isBusy: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.tint)
            }

            Text(status.text)
                .foregroundStyle(status.isIdle ? .secondary : .primary)
                .textSelection(.enabled)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
