import Testing
import SwiftUI
import CoreMedia
import Foundation
import Kadr
@testable import KadrUI

/// Pure-helper tests for `SpeedCurveEditor`. Math + array transforms are
/// `nonisolated public static` on the editor type so they're testable without
/// driving SwiftUI gestures. Body-construction smoke tests live alongside.
struct SpeedCurveEditorTests {

    // MARK: - Fixtures

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func videoClip(trim: ClosedRange<Double>? = 0...4) -> VideoClip {
        let url = URL(fileURLWithPath: "/dev/null")
        if let trim {
            return VideoClip(url: url).trimmed(to: trim)
        }
        return VideoClip(url: url)
    }

    private func keyframe(_ t: Double, _ value: Double) -> Kadr.Animation<Double>.Keyframe {
        .at(t, value: value)
    }

    // MARK: - clampMultiplier

    @Test func clampMultiplierBelowFloor() {
        #expect(SpeedCurveEditor.clampMultiplier(0.1) == SpeedCurveEditor.minMultiplier)
    }

    @Test func clampMultiplierAboveCeiling() {
        #expect(SpeedCurveEditor.clampMultiplier(10.0) == SpeedCurveEditor.maxMultiplier)
    }

    @Test func clampMultiplierInRangePassesThrough() {
        #expect(SpeedCurveEditor.clampMultiplier(1.5) == 1.5)
    }

    // MARK: - normalizedY / multiplier round-trip (log scale)

    @Test func normalizedYAtUnityIsHalf() {
        // 1.0× lands at the midline (log2(1.0) = 0 → (0 + 2) / 4 = 0.5).
        #expect(SpeedCurveEditor.normalizedY(forMultiplier: 1.0) == 0.5)
    }

    @Test func normalizedYAtFloorIsZero() {
        #expect(SpeedCurveEditor.normalizedY(forMultiplier: 0.25) == 0.0)
    }

    @Test func normalizedYAtCeilingIsOne() {
        #expect(SpeedCurveEditor.normalizedY(forMultiplier: 4.0) == 1.0)
    }

    @Test func multiplierRoundTrip() {
        // A 0.5× should be one quarter from the bottom on a log-2 scale.
        let half = SpeedCurveEditor.normalizedY(forMultiplier: 0.5)
        #expect(half == 0.25)
        let restored = SpeedCurveEditor.multiplier(forNormalizedY: 0.25)
        #expect(abs(restored - 0.5) < 0.0001)
    }

    @Test func multiplierClampsBelowZeroNormalizedY() {
        let m = SpeedCurveEditor.multiplier(forNormalizedY: -0.5)
        #expect(m == SpeedCurveEditor.minMultiplier)
    }

    @Test func multiplierClampsAboveOneNormalizedY() {
        let m = SpeedCurveEditor.multiplier(forNormalizedY: 1.5)
        #expect(m == SpeedCurveEditor.maxMultiplier)
    }

    // MARK: - editorDurationSeconds

    @Test func editorDurationUsesTrimRange() {
        let clip = videoClip(trim: 0...3)
        #expect(SpeedCurveEditor.editorDurationSeconds(for: clip) == 3.0)
    }

    @Test func editorDurationFallsBackToZeroWhenUntrimmed() {
        let clip = videoClip(trim: nil)
        // Untrimmed clip's `duration` is .zero (synchronous fallback per kadr docs).
        #expect(SpeedCurveEditor.editorDurationSeconds(for: clip) == 0)
    }

    // MARK: - point / locationToKeyframe round-trip

    @Test func pointForKeyframeAtOriginAndUnity() {
        let kf = keyframe(0, 1.0)
        let p = SpeedCurveEditor.point(
            for: kf,
            in: CGSize(width: 100, height: 80),
            durationSeconds: 4
        )
        #expect(p.x == 0)
        // y inverted: 1.0× is at half-height; canvas reports y from top, so
        // expect height - 0.5 * height = 40.
        #expect(p.y == 40)
    }

    @Test func locationToKeyframeMidCenterMapsToTwoSecondsAndUnity() {
        let (time, mult) = SpeedCurveEditor.locationToKeyframe(
            location: CGPoint(x: 50, y: 40),
            in: CGSize(width: 100, height: 80),
            durationSeconds: 4
        )
        #expect(abs(CMTimeGetSeconds(time) - 2.0) < 0.0001)
        #expect(abs(mult - 1.0) < 0.0001)
    }

    @Test func locationToKeyframeClampsOutsideX() {
        let (time, _) = SpeedCurveEditor.locationToKeyframe(
            location: CGPoint(x: 9999, y: 0),
            in: CGSize(width: 100, height: 80),
            durationSeconds: 4
        )
        #expect(CMTimeGetSeconds(time) == 4.0)
    }

    @Test func locationToKeyframeReturnsZeroForZeroDuration() {
        let (time, mult) = SpeedCurveEditor.locationToKeyframe(
            location: CGPoint(x: 50, y: 40),
            in: CGSize(width: 100, height: 80),
            durationSeconds: 0
        )
        #expect(time == .zero)
        #expect(mult == 1.0)
    }

    // MARK: - draggedKeyframe

    @Test func draggedKeyframeAppliesHorizontalTranslation() {
        let kf = keyframe(2.0, 1.0)
        let result = SpeedCurveEditor.draggedKeyframe(
            original: kf,
            translation: CGSize(width: 25, height: 0),
            size: CGSize(width: 100, height: 80),
            durationSeconds: 4
        )
        // 25 px / 100 px width * 4s = +1s.
        #expect(abs(CMTimeGetSeconds(result.time) - 3.0) < 0.0001)
        #expect(abs(result.value - 1.0) < 0.0001)
    }

    @Test func draggedKeyframeAppliesVerticalTranslation() {
        let kf = keyframe(0, 1.0)
        // Drag upward (negative y) by quarter-height → from log y=0.5 to log y=0.75
        // → 2× in multiplier-space (half a log-2 step).
        let result = SpeedCurveEditor.draggedKeyframe(
            original: kf,
            translation: CGSize(width: 0, height: -20),
            size: CGSize(width: 100, height: 80),
            durationSeconds: 4
        )
        #expect(abs(result.value - 2.0) < 0.0001)
    }

    @Test func draggedKeyframeClampsToBounds() {
        let kf = keyframe(2.0, 1.0)
        let result = SpeedCurveEditor.draggedKeyframe(
            original: kf,
            translation: CGSize(width: -9999, height: -9999),
            size: CGSize(width: 100, height: 80),
            durationSeconds: 4
        )
        #expect(CMTimeGetSeconds(result.time) == 0)
        #expect(result.value == SpeedCurveEditor.maxMultiplier)
    }

    // MARK: - keyframesByAdding

    @Test func addingKeyframeIntoEmptyArray() {
        let kf = keyframe(1.0, 0.5)
        let result = SpeedCurveEditor.keyframesByAdding(kf, to: [])
        #expect(result.count == 1)
        #expect(result[0].value == 0.5)
    }

    @Test func addingKeyframeSortsByTime() {
        let existing = [keyframe(0.0, 1.0), keyframe(2.0, 1.0)]
        let result = SpeedCurveEditor.keyframesByAdding(keyframe(1.0, 0.5), to: existing)
        #expect(result.map { CMTimeGetSeconds($0.time) } == [0.0, 1.0, 2.0])
    }

    @Test func addingKeyframeAtSameTimeReplacesExisting() {
        let existing = [keyframe(1.0, 1.0)]
        let result = SpeedCurveEditor.keyframesByAdding(keyframe(1.0, 0.5), to: existing)
        #expect(result.count == 1)
        #expect(result[0].value == 0.5)
    }

    @Test func addingKeyframeClampsValue() {
        let result = SpeedCurveEditor.keyframesByAdding(keyframe(0, 99.0), to: [])
        #expect(result[0].value == SpeedCurveEditor.maxMultiplier)
    }

    // MARK: - keyframesByRemoving / keyframesByReplacing

    @Test func removingExistingKeyframe() {
        let existing = [keyframe(0, 1.0), keyframe(1.0, 0.5), keyframe(2.0, 1.0)]
        let result = SpeedCurveEditor.keyframesByRemoving(at: cmt(1.0), from: existing)
        #expect(result.map { CMTimeGetSeconds($0.time) } == [0.0, 2.0])
    }

    @Test func removingMissingKeyframeIsNoOp() {
        let existing = [keyframe(0, 1.0)]
        let result = SpeedCurveEditor.keyframesByRemoving(at: cmt(5.0), from: existing)
        #expect(result.count == 1)
    }

    @Test func replacingKeyframePreservesSortOrder() {
        let existing = [keyframe(0, 1.0), keyframe(1.0, 0.5), keyframe(2.0, 1.0)]
        let replacement = keyframe(3.0, 2.0)
        let result = SpeedCurveEditor.keyframesByReplacing(
            at: cmt(1.0),
            with: replacement,
            in: existing
        )
        #expect(result.map { CMTimeGetSeconds($0.time) } == [0.0, 2.0, 3.0])
        #expect(result.last?.value == 2.0)
    }

    @Test func replacingDropsCollidingKeyframe() {
        // Drag (1.0) onto (2.0) — the colliding 2.0 should be evicted, the
        // dragged marker wins.
        let existing = [keyframe(1.0, 0.5), keyframe(2.0, 1.0)]
        let replacement = keyframe(2.0, 0.25)
        let result = SpeedCurveEditor.keyframesByReplacing(
            at: cmt(1.0),
            with: replacement,
            in: existing
        )
        #expect(result.count == 1)
        #expect(result[0].value == 0.25)
    }

    // MARK: - Timing presets

    @Test func timingPresetsContainsOnlyNamedFour() {
        let labels = SpeedCurveEditor.timingPresets.map(\.0)
        #expect(labels == ["Linear", "Ease In", "Ease Out", "Ease In Out"])
    }

    @Test func timingLabelHandlesAllCases() {
        #expect(SpeedCurveEditor.timingLabel(for: .linear) == "Linear")
        #expect(SpeedCurveEditor.timingLabel(for: .easeIn) == "Ease In")
        #expect(SpeedCurveEditor.timingLabel(for: .easeOut) == "Ease Out")
        #expect(SpeedCurveEditor.timingLabel(for: .easeInOut) == "Ease In Out")
        #expect(SpeedCurveEditor.timingLabel(for: .cubicBezier(.zero, .zero)) == "Cubic Bézier")
    }

    // MARK: - Body smoke

    @MainActor
    @Test func bodyConstructsWithUntrimmedClip() {
        let clip = videoClip(trim: nil)
        let view = SpeedCurveEditor(clip: clip, onUpdate: { _ in })
        _ = view.body
    }

    @MainActor
    @Test func bodyConstructsWithCurveAndPlayhead() {
        let curve = Kadr.Animation<Double>.keyframes([
            .at(0.0, value: 1.0),
            .at(1.5, value: 0.5),
            .at(3.0, value: 1.0)
        ], timing: .easeInOut)
        let clip = videoClip().speed(curve: curve)
        let time = Binding<CMTime>.constant(cmt(1.0))
        let view = SpeedCurveEditor(clip: clip, currentTime: time, onUpdate: { _ in })
        _ = view.body
    }
}
