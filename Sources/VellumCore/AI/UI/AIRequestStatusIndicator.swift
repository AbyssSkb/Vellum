import SwiftUI

enum AIRequestVisualStatus: Equatable {
    case idle
    case streaming
    case completed
    case failed
}

struct AIRequestStatusIndicator: View {
    let status: AIRequestVisualStatus

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
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                Circle()
                    .trim(from: 0.18, to: 0.82)
                    .stroke(
                        TokyoNight.cyanColor,
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotationAngle(at: timeline.date)))
                    .frame(width: 12, height: 12)
            }
        }
    }

    private func rotationAngle(at date: Date) -> Double {
        let cycle = 0.76
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return phase / cycle * 360
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
