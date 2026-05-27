import Foundation
import Testing
@testable import VellumCore

@Suite("Animation geometry")
struct AnimationGeometryTests {
    @Test
    func clampedDeltaTimeUsesMinimumAndMaximumBounds() {
        #expect(AnimationGeometry.clampedDeltaTime(from: 10, to: 10.001, minimum: 0.01, maximum: 0.1) == 0.01)
        #expect(AnimationGeometry.clampedDeltaTime(from: 10, to: 10.2, minimum: 0.01, maximum: 0.1) == 0.1)
        #expect(abs(AnimationGeometry.clampedDeltaTime(from: 10, to: 10.05, minimum: 0.01, maximum: 0.1) - 0.05) < 0.000001)
    }

    @Test
    func exponentialProgressApproachesTargetWithoutOvershooting() {
        let progress = AnimationGeometry.exponentialProgress(deltaTime: 0.055, timeConstant: 0.055)

        #expect(progress > 0.63)
        #expect(progress < 0.64)
        #expect(AnimationGeometry.exponentialProgress(deltaTime: 0.1, timeConstant: 0) == 1)
    }

    @Test
    func nextValueInterpolatesByProgress() {
        #expect(AnimationGeometry.nextValue(current: 10, target: 20, progress: 0.25) == 12.5)
        #expect(AnimationGeometry.nextValue(current: 20, target: 10, progress: 0.5) == 15)
    }

    @Test
    func nearTargetUsesStrictThreshold() {
        #expect(AnimationGeometry.isNearTarget(current: 10, target: 10.4, threshold: 0.45))
        #expect(!AnimationGeometry.isNearTarget(current: 10, target: 10.46, threshold: 0.45))
    }
}
