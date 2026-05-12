import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Pure-logic tests for ``TimelineView/clipMatchesSelection(id:single:set:)``
/// plus body-construction smoke for the new init parameter and the
/// ``TimelineView/onLongPressClip(_:)`` modifier. The gesture-driven
/// emission path runs in `kadr-reels-studio` v0.4 Tier 5's manual QA; the
/// rule lives here.
struct ClipMatchesSelectionTests {

    @Test func nilIDNeverMatches() {
        #expect(!TimelineView.clipMatchesSelection(id: nil, single: ClipID("a"), set: ["a"]))
    }

    @Test func singleMatchAlone() {
        #expect(TimelineView.clipMatchesSelection(
            id: ClipID("a"), single: ClipID("a"), set: nil
        ))
    }

    @Test func setMatchAlone() {
        #expect(TimelineView.clipMatchesSelection(
            id: ClipID("a"), single: nil, set: [ClipID("a"), ClipID("b")]
        ))
    }

    @Test func neitherMatchReturnsFalse() {
        #expect(!TimelineView.clipMatchesSelection(
            id: ClipID("z"), single: ClipID("a"), set: [ClipID("b")]
        ))
    }

    @Test func bothNilReturnsFalse() {
        #expect(!TimelineView.clipMatchesSelection(id: ClipID("a"), single: nil, set: nil))
    }

    @Test func unionReturnsTrueIfEitherMatches() {
        // Single matches; set doesn't.
        #expect(TimelineView.clipMatchesSelection(
            id: ClipID("a"), single: ClipID("a"), set: [ClipID("z")]
        ))
        // Set matches; single doesn't.
        #expect(TimelineView.clipMatchesSelection(
            id: ClipID("a"), single: ClipID("z"), set: [ClipID("a")]
        ))
        // Both match — still true.
        #expect(TimelineView.clipMatchesSelection(
            id: ClipID("a"), single: ClipID("a"), set: [ClipID("a")]
        ))
    }

    @Test func emptySetIsNotAMatch() {
        #expect(!TimelineView.clipMatchesSelection(id: ClipID("a"), single: nil, set: []))
    }
}

struct MultiSelectAndLongPressModifierTests {

    private func sampleVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 2.0)
            ImageClip(img, duration: 3.0)
        }
    }

    @Test @MainActor func constructsWithSelectedClipIDsBinding() {
        @State var ids: Set<ClipID> = []
        _ = TimelineView(sampleVideo(), selectedClipIDs: $ids).body
    }

    @Test @MainActor func constructsWithBothSingleAndSetBindings() {
        @State var single: ClipID? = nil
        @State var ids: Set<ClipID> = []
        _ = TimelineView(
            sampleVideo(),
            selectedClipID: $single,
            selectedClipIDs: $ids
        ).body
    }

    @Test @MainActor func constructsWithLongPressModifier() {
        _ = TimelineView(sampleVideo())
            .onLongPressClip { _ in }
            .body
    }

    @Test @MainActor func composesWithFullV09CallbackSet() {
        @State var time = CMTime(seconds: 1, preferredTimescale: 600)
        @State var zoom = TimelineZoom(pixelsPerSecond: 50)
        @State var single: ClipID? = nil
        @State var multi: Set<ClipID> = []
        _ = TimelineView(
            sampleVideo(),
            currentTime: $time,
            selectedClipID: $single,
            selectedClipIDs: $multi,
            zoom: $zoom,
            onReorder: { _ in }
        )
        .fixedCenterPlayhead()
        .onZoomSnap { _ in }
        .onClipDragSnap {}
        .onLongPressClip { _ in }
        .body
    }
}
