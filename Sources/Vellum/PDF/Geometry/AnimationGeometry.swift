import Foundation

enum AnimationGeometry {
    static func clampedDeltaTime(
        from lastTick: TimeInterval,
        to currentTick: TimeInterval,
        minimum: TimeInterval,
        maximum: TimeInterval
    ) -> TimeInterval {
        min(max(currentTick - lastTick, minimum), maximum)
    }

    static func exponentialProgress(deltaTime: TimeInterval, timeConstant: TimeInterval) -> CGFloat {
        guard timeConstant > 0 else { return 1 }
        return 1 - CGFloat(exp(-deltaTime / timeConstant))
    }

    static func nextValue(current: CGFloat, target: CGFloat, progress: CGFloat) -> CGFloat {
        current + (target - current) * progress
    }

    static func isNearTarget(current: CGFloat, target: CGFloat, threshold: CGFloat) -> Bool {
        abs(target - current) < threshold
    }
}
