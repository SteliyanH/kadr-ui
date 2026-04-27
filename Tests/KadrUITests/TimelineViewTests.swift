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
}
