import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Smoke tests for `TimelineView`. SwiftUI rendering / async metadata loading is
/// exercised manually via the example app — these tests cover the public constructor
/// contract.
struct TimelineViewTests {

    private func sampleVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 2.0)
            Kadr.Transition.dissolve(duration: 0.5)
            ImageClip(img, duration: 3.0)
        }
        .audio(url: URL(fileURLWithPath: "/tmp/music.m4a"))
    }

    @Test @MainActor func constructsWithoutPlayhead() {
        _ = TimelineView(sampleVideo()).body
    }

    @Test @MainActor func constructsWithPlayhead() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        _ = TimelineView(sampleVideo(), currentTime: $t).body
    }

    @Test @MainActor func constructsWithLaneSizingParams() {
        _ = TimelineView(sampleVideo(), laneHeight: 80, laneSpacing: 8).body
    }

    @Test @MainActor func constructsWithAudioLanesHidden() {
        _ = TimelineView(sampleVideo(), showAudioLanes: false).body
    }

    @Test @MainActor func constructsWithAudioWaveformsEnabled() {
        let img = PlatformImage()
        let v = Video {
            ImageClip(img, duration: 5.0)
        }
        .audio(url: URL(fileURLWithPath: "/tmp/m.m4a"))
        _ = TimelineView(v, showAudioWaveforms: true).body
    }

    @Test @MainActor func constructsWithLaneLabelsShown() {
        let img = PlatformImage()
        let v = Video {
            ImageClip(img, duration: 10.0)
            Track(at: 1.0) { ImageClip(img, duration: 2.0) }
        }
        _ = TimelineView(v, showLaneLabels: true).body
    }

    @Test @MainActor func constructsMultiTrackWithAudioLanesHidden() {
        let img = PlatformImage()
        let v = Video {
            ImageClip(img, duration: 10.0).id("main")
            Track(at: 1.0) { ImageClip(img, duration: 2.0).id("ta") }
        }
        .audio(url: URL(fileURLWithPath: "/tmp/m.m4a"))
        _ = TimelineView(v, showAudioLanes: false).body
    }

    @Test @MainActor func constructsMultiTrackWithReorderAndTrim() {
        // v0.5.1 — reorder + trim callbacks are now wired into the multi-lane render's
        // chain lane. Smoke test only; chain-aware reorder math is unit-tested in
        // TimelineLanesTests.applyChainReorder*.
        let img = PlatformImage()
        let v = Video {
            ImageClip(img, duration: 5.0).id("a")
            Kadr.Transition.fade(duration: 0.3)
            ImageClip(img, duration: 5.0).id("b")
            Track(at: 1.0) { ImageClip(img, duration: 2.0).id("ta") }
            ImageClip(img, duration: 2.0).at(time: 2.0).id("pip")
        }
        _ = TimelineView(
            v,
            onReorder: { _, _, _ in },
            onTrim: { _, _, _ in }
        ).body
    }

    @Test @MainActor func constructsForMultiTrackVideo() {
        // Video with .at(time:) and a Track {} block — exercises the multi-lane code path.
        let img = PlatformImage()
        let v = Video {
            ImageClip(img, duration: 10.0).id("main")
            ImageClip(img, duration: 2.0).at(time: 1.0).id("pip")
            Track(at: 4.0) {
                ImageClip(img, duration: 2.0).id("ta")
                ImageClip(img, duration: 2.0).id("tb")
            }
        }
        _ = TimelineView(v).body
    }

    @Test func chainOnlyVideoTakesSingleLanePath() {
        // Visual regression sentinel — assignLanes returns exactly one lane for a
        // chain-only Video, which is what the body checks to keep v0.4.x behavior.
        let img = PlatformImage()
        let v = Video {
            ImageClip(img, duration: 1.0)
            Kadr.Transition.fade(duration: 0.3)
            ImageClip(img, duration: 2.0)
        }
        let lanes = TimelineView.assignLanes(for: v, includeAudio: false)
        #expect(lanes.count == 1)
    }

    @Test @MainActor func constructsForVideoWithoutAudioTracks() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        _ = TimelineView(video).body
    }

    // MARK: - Selection

    @Test @MainActor func constructsWithSelectionBinding() {
        @State var selected: ClipID? = nil
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0).id("intro")
            ImageClip(img, duration: 2.0).id("body")
        }
        _ = TimelineView(video, selectedClipID: $selected).body
    }

    @Test @MainActor func constructsWithBothPlayheadAndSelection() {
        @State var time = CMTime(seconds: 1.0, preferredTimescale: 600)
        @State var selected: ClipID? = "body"
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0).id("intro")
            ImageClip(img, duration: 2.0).id("body")
        }
        _ = TimelineView(video, currentTime: $time, selectedClipID: $selected).body
    }

    @Test @MainActor func constructsWithMixedIdentifiedAndUnidentifiedClips() {
        // Selection should still work when only some clips have IDs. Unidentified
        // clips and Transitions don't participate in tap-to-select; they should
        // render normally with no crash.
        @State var selected: ClipID? = nil
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0).id("intro")
            Kadr.Transition.dissolve(duration: 0.5)
            ImageClip(img, duration: 2.0)   // no .id(...)
        }
        _ = TimelineView(video, selectedClipID: $selected).body
    }

    // MARK: - Reorder

    @Test @MainActor func constructsWithReorderCallback() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0).id("a")
            ImageClip(img, duration: 2.0).id("b")
        }
        _ = TimelineView(video, onReorder: { _, _, _ in }).body
    }

    @Test @MainActor func constructsWithTrackReorderCallback() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 5.0).id("main")
            Track(at: 1.0, name: "B-roll") {
                ImageClip(img, duration: 1.0).id("a")
                ImageClip(img, duration: 2.0).id("b")
            }
        }
        _ = TimelineView(video, onTrackReorder: { _, _, _, _ in }).body
    }

    @Test @MainActor func constructsWithTrackTrimCallback() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 5.0).id("main")
            Track(at: 1.0) {
                ImageClip(img, duration: 1.0).id("a")
            }
        }
        _ = TimelineView(video, onTrackTrim: { _, _, _, _ in }).body
    }

    // MARK: - Reorder math: computeTargetIndex

    @Test func computeTargetIndexNoMovementReturnsSource() {
        // Three clips of equal width. Drag = 0 means the finger stays at the source
        // clip's center, so target should be the source.
        let widths: [CGFloat] = [100, 100, 100]
        let target = TimelineView.computeTargetIndex(source: 1, dragX: 0, slotWidths: widths)
        #expect(target == 1)
    }

    @Test func computeTargetIndexDragRightCrossesIntoNextSlot() {
        let widths: [CGFloat] = [100, 100, 100]
        // Source at index 0 (center 50). Drag +210 puts finger at x=260, past slot 2's mid (250).
        let target = TimelineView.computeTargetIndex(source: 0, dragX: 210, slotWidths: widths)
        #expect(target == 2)
    }

    @Test func computeTargetIndexDragLeftCrossesIntoPreviousSlot() {
        let widths: [CGFloat] = [100, 100, 100]
        // Source at index 2 (center 250). Drag -150 puts finger at x=100, before slot 1's mid (150).
        let target = TimelineView.computeTargetIndex(source: 2, dragX: -150, slotWidths: widths)
        #expect(target == 1)
    }

    @Test func computeTargetIndexClampsToLastSlot() {
        let widths: [CGFloat] = [100, 100, 100]
        // Drag way past the right edge — should clamp to the last index.
        let target = TimelineView.computeTargetIndex(source: 0, dragX: 10_000, slotWidths: widths)
        #expect(target == 2)
    }

    // MARK: - Reorder math: applyReorder

    private func reorderableClips() -> [any Clip] {
        let img = PlatformImage()
        return [
            ImageClip(img, duration: 1.0).id("a"),
            ImageClip(img, duration: 1.0).id("b"),
            ImageClip(img, duration: 1.0).id("c"),
        ]
    }

    @Test func applyReorderMovesAToEnd() {
        let result = TimelineView.applyReorder(
            clips: reorderableClips(),
            from: 0,
            to: 2
        )
        let ids = result?.newClips.map { $0.clipID?.rawValue }
        #expect(ids == ["b", "c", "a"])
    }

    @Test func applyReorderMovesCToStart() {
        let result = TimelineView.applyReorder(
            clips: reorderableClips(),
            from: 2,
            to: 0
        )
        let ids = result?.newClips.map { $0.clipID?.rawValue }
        #expect(ids == ["c", "a", "b"])
    }

    @Test func applyReorderNoOpReturnsNil() {
        let result = TimelineView.applyReorder(
            clips: reorderableClips(),
            from: 1,
            to: 1
        )
        #expect(result == nil)
    }

    @Test func applyReorderTransitionTravelsWithPrecedingClip() {
        // Layout: A, transition, B, C. Move A (with its transition) past B.
        let img = PlatformImage()
        let clips: [any Clip] = [
            ImageClip(img, duration: 1.0).id("a"),
            Kadr.Transition.dissolve(duration: 0.5),
            ImageClip(img, duration: 1.0).id("b"),
            ImageClip(img, duration: 1.0).id("c"),
        ]
        let result = TimelineView.applyReorder(clips: clips, from: 0, to: 2)
        // Expected: B, A, transition, C — A's transition stays glued to A.
        let labels: [String] = result!.newClips.map {
            if let id = $0.clipID?.rawValue { return id }
            if $0 is Kadr.Transition { return "T" }
            return "?"
        }
        #expect(labels == ["b", "a", "T", "c"])
    }

    @Test func applyReorderRefusesDropInsideOwnGroup() {
        // Source group is A + transition (indices 0..1). Dropping at index 1 (inside
        // the group) is a no-op.
        let img = PlatformImage()
        let clips: [any Clip] = [
            ImageClip(img, duration: 1.0).id("a"),
            Kadr.Transition.dissolve(duration: 0.5),
            ImageClip(img, duration: 1.0).id("b"),
        ]
        let result = TimelineView.applyReorder(clips: clips, from: 0, to: 1)
        #expect(result == nil)
    }

    // MARK: - Trim

    @Test @MainActor func constructsWithTrimCallback() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 2.0).id("a")
        }
        _ = TimelineView(video, onTrim: { _, _, _ in }).body
    }

    // MARK: - Trim math: computeTrimDeltas

    @Test func trimLeadingPositiveTrims() {
        // Drag leading handle right by 50px @ 100px/s = 0.5s trimmed off the front.
        let (leading, trailing) = TimelineView.computeTrimDeltas(
            edge: .leading, pixelDelta: 50, pxPerSecond: 100
        )
        #expect(CMTimeGetSeconds(leading) == 0.5)
        #expect(trailing == .zero)
    }

    @Test func trimLeadingNegativeExtends() {
        // Drag leading handle left by 30px @ 100px/s = -0.3s (extending the front).
        let (leading, trailing) = TimelineView.computeTrimDeltas(
            edge: .leading, pixelDelta: -30, pxPerSecond: 100
        )
        #expect(CMTimeGetSeconds(leading) == -0.3)
        #expect(trailing == .zero)
    }

    @Test func trimTrailingPositiveTrims() {
        // Drag trailing handle LEFT by 40px @ 100px/s = 0.4s trimmed off the back.
        // Sign convention: negative pixelDelta on trailing = positive trim.
        let (leading, trailing) = TimelineView.computeTrimDeltas(
            edge: .trailing, pixelDelta: -40, pxPerSecond: 100
        )
        #expect(leading == .zero)
        #expect(CMTimeGetSeconds(trailing) == 0.4)
    }

    @Test func trimTrailingNegativeExtends() {
        // Drag trailing handle right by 60px @ 100px/s = -0.6s (extending the back).
        let (leading, trailing) = TimelineView.computeTrimDeltas(
            edge: .trailing, pixelDelta: 60, pxPerSecond: 100
        )
        #expect(leading == .zero)
        #expect(CMTimeGetSeconds(trailing) == -0.6)
    }

    @Test func trimZeroPixelsZeroDeltas() {
        let (leading, trailing) = TimelineView.computeTrimDeltas(
            edge: .leading, pixelDelta: 0, pxPerSecond: 100
        )
        #expect(leading == .zero)
        #expect(trailing == .zero)
    }

    @Test func trimZeroPxPerSecondReturnsZero() {
        // Defensive: avoid divide-by-zero when the composition has zero duration.
        let (leading, trailing) = TimelineView.computeTrimDeltas(
            edge: .leading, pixelDelta: 100, pxPerSecond: 0
        )
        #expect(leading == .zero)
        #expect(trailing == .zero)
    }

    // MARK: - Live trim metrics (v0.4.2)

    @Test func liveTrimLeadingShrinksWithOffset() {
        // Drag leading right by 30px from a 100px-wide clip:
        // width 100 - 30 = 70, offset 30 (right edge stays anchored visually).
        let (w, off) = TimelineView.liveTrimMetrics(edge: .leading, baseWidth: 100, pixelDelta: 30)
        #expect(w == 70)
        #expect(off == 30)
    }

    @Test func liveTrimLeadingExtendsWithNegativeOffset() {
        // Drag leading left by 20px (extending the front):
        // width 100 - (-20) = 120, offset -20 (visually shifts left).
        let (w, off) = TimelineView.liveTrimMetrics(edge: .leading, baseWidth: 100, pixelDelta: -20)
        #expect(w == 120)
        #expect(off == -20)
    }

    @Test func liveTrimTrailingShrinksNoOffset() {
        // Drag trailing left by 25px (trim from back):
        // width 100 + (-25) = 75, no offset.
        let (w, off) = TimelineView.liveTrimMetrics(edge: .trailing, baseWidth: 100, pixelDelta: -25)
        #expect(w == 75)
        #expect(off == 0)
    }

    @Test func liveTrimTrailingExtendsNoOffset() {
        // Drag trailing right by 40px (extend back):
        // width 100 + 40 = 140, no offset.
        let (w, off) = TimelineView.liveTrimMetrics(edge: .trailing, baseWidth: 100, pixelDelta: 40)
        #expect(w == 140)
        #expect(off == 0)
    }

    @Test func liveTrimZeroDeltaIsIdentity() {
        let (wL, offL) = TimelineView.liveTrimMetrics(edge: .leading,  baseWidth: 100, pixelDelta: 0)
        let (wT, offT) = TimelineView.liveTrimMetrics(edge: .trailing, baseWidth: 100, pixelDelta: 0)
        #expect(wL == 100 && offL == 0)
        #expect(wT == 100 && offT == 0)
    }

    // MARK: - Scrub time conversion (v0.4.2)

    @Test func scrubTimeAtOriginIsZero() {
        let t = TimelineView.scrubTime(x: 0, pxPerSecond: 100, totalSeconds: 5)
        #expect(t == 0)
    }

    @Test func scrubTimeAtMidpoint() {
        // 250px @ 100px/s = 2.5s
        let t = TimelineView.scrubTime(x: 250, pxPerSecond: 100, totalSeconds: 5)
        #expect(t == 2.5)
    }

    @Test func scrubTimeClampsToTotalSeconds() {
        // 1000px @ 100px/s = 10s, clamped to totalSeconds (5).
        let t = TimelineView.scrubTime(x: 1000, pxPerSecond: 100, totalSeconds: 5)
        #expect(t == 5)
    }

    @Test func scrubTimeClampsToZeroForNegativeX() {
        let t = TimelineView.scrubTime(x: -50, pxPerSecond: 100, totalSeconds: 5)
        #expect(t == 0)
    }

    @Test func scrubTimeReturnsZeroForZeroPxPerSecond() {
        // Defensive: empty composition / zero render width → no division.
        let t = TimelineView.scrubTime(x: 250, pxPerSecond: 0, totalSeconds: 5)
        #expect(t == 0)
    }

    // MARK: - Live reorder shift offsets (v0.4.3)

    @Test func reorderShiftSourceGroupItselfIsZero() {
        let widths: [CGFloat] = [100, 100, 100, 100]
        let off = TimelineView.reorderShiftOffset(
            index: 1, source: 1, groupSize: 1, target: 3, slotWidths: widths
        )
        #expect(off == 0)
    }

    @Test func reorderShiftMovingRightShiftsIntermediateLeft() {
        let widths: [CGFloat] = [100, 100, 100, 100]
        // Source=0, target=2: clip 1 and clip 2 should shift left by groupWidth (100).
        let off1 = TimelineView.reorderShiftOffset(index: 1, source: 0, groupSize: 1, target: 2, slotWidths: widths)
        let off2 = TimelineView.reorderShiftOffset(index: 2, source: 0, groupSize: 1, target: 2, slotWidths: widths)
        let off3 = TimelineView.reorderShiftOffset(index: 3, source: 0, groupSize: 1, target: 2, slotWidths: widths)
        #expect(off1 == -100)
        #expect(off2 == -100)
        #expect(off3 == 0)   // past target; doesn't shift
    }

    @Test func reorderShiftMovingLeftShiftsIntermediateRight() {
        let widths: [CGFloat] = [100, 100, 100, 100]
        // Source=3, target=1: clips 1 and 2 shift right by groupWidth (100).
        let off0 = TimelineView.reorderShiftOffset(index: 0, source: 3, groupSize: 1, target: 1, slotWidths: widths)
        let off1 = TimelineView.reorderShiftOffset(index: 1, source: 3, groupSize: 1, target: 1, slotWidths: widths)
        let off2 = TimelineView.reorderShiftOffset(index: 2, source: 3, groupSize: 1, target: 1, slotWidths: widths)
        #expect(off0 == 0)    // before target; doesn't shift
        #expect(off1 == 100)
        #expect(off2 == 100)
    }

    @Test func reorderShiftNoMovementZero() {
        let widths: [CGFloat] = [100, 100, 100, 100]
        for i in 0..<4 {
            let off = TimelineView.reorderShiftOffset(index: i, source: 1, groupSize: 1, target: 1, slotWidths: widths)
            #expect(off == 0)
        }
    }

    @Test func reorderShiftWithGroupSizeTwo() {
        let widths: [CGFloat] = [100, 100, 100, 100]
        // Source group spans indices 0..1, each 100px wide → groupWidth=200.
        // Moving to target=3, clips 2 and 3 shift left by 200.
        let off2 = TimelineView.reorderShiftOffset(index: 2, source: 0, groupSize: 2, target: 3, slotWidths: widths)
        let off3 = TimelineView.reorderShiftOffset(index: 3, source: 0, groupSize: 2, target: 3, slotWidths: widths)
        #expect(off2 == -200)
        #expect(off3 == -200)
    }

    @Test func reorderShiftSourceGroupTrailingTransitionIsZero() {
        let widths: [CGFloat] = [100, 100, 100, 100]
        let offSource = TimelineView.reorderShiftOffset(index: 0, source: 0, groupSize: 2, target: 3, slotWidths: widths)
        let offTransition = TimelineView.reorderShiftOffset(index: 1, source: 0, groupSize: 2, target: 3, slotWidths: widths)
        #expect(offSource == 0)
        #expect(offTransition == 0)
    }

    @Test @MainActor func scrubStripRendersWhenCurrentTimeBound() {
        // Smoke: presence of the scrub strip is gated on currentTime != nil. With it
        // bound, body should still resolve.
        @State var t = CMTime(seconds: 0, preferredTimescale: 600)
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        _ = TimelineView(video, currentTime: $t).body
    }
}
