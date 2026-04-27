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
}
