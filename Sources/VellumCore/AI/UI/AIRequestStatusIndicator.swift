import SwiftUI

enum AIRequestVisualStatus: Equatable {
    case idle
    case streaming
    case completed
    case failed
}

struct AIRequestStatusIndicator: View {
    let status: AIRequestVisualStatus
    @State private var isSpinning = false

    var body: some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case .streaming:
                spinningRing
            case .completed:
                symbol("checkmark", color: TokyoNight.cyanColor)
            case .failed:
                symbol("exclamationmark", color: TokyoNight.redColor)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.14), value: status)
    }

    private var base: some View {
        Circle()
            .fill(TokyoNight.backgroundDeepColor.opacity(0.88))
            .overlay {
                Circle()
                    .stroke(TokyoNight.borderColor.opacity(0.52), lineWidth: 1)
            }
            .frame(width: 18, height: 18)
    }

    private var spinningRing: some View {
        ZStack {
            base
            Circle()
                .trim(from: 0.18, to: 0.82)
                .stroke(
                    TokyoNight.cyanColor,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .frame(width: 12, height: 12)
                .onAppear {
                    isSpinning = true
                }
                .animation(
                    .linear(duration: 0.76).repeatForever(autoreverses: false),
                    value: isSpinning
                )
        }
    }

    private func symbol(_ name: String, color: Color) -> some View {
        ZStack {
            base
            Image(systemName: name)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
        }
    }
}
