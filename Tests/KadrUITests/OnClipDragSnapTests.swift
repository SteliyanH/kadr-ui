import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Pure-logic tests for ``TimelineView/snapTransition(previous:current:)`` and
/// smoke for the ``TimelineView/onClipDragSnap(_:)`` modifier. The gesture-
/// driven emission path runs in `kadr-reels-studio` v0.4 Tier 3's manual QA;
/// the rule lives here.
struct OnClipDragSnapTests {

    // MARK: - snapTransition

    @Test func firstObservationLatchesWithoutFiring() {
        let (fire, newPrev) = TimelineView.snapTransition(previous: nil, current: 2)
        #expect(fire == false)
        #expect(newPrev == 2)
    }

    @Test func sameTargetIsSilent() {
        let (fire, newPrev) = TimelineView.snapTransition(previous: 3, current: 3)
        #expect(fire == false)
        #expect(newPrev == 3)
    }

    @Test func changeToDifferentTargetFires() {
        let (fire, newPrev) = TimelineView.snapTransition(previous: 2, current: 3)
        #expect(fire == true)
        #expect(newPrev == 3)
    }

    @Test func changeBackwardFires() {
        // Direction-symmetric — drag-left and drag-right both fire on each
        // boundary cross.
        let (fire, newPrev) = TimelineView.snapTransition(previous: 5, current: 4)
        #expect(fire == true)
        #expect(newPrev == 4)
    }

    /// Walk a typical drag: latch → cross → cross-back → settle. The helper
    /// composes correctly under a sequence of calls (no hidden state).
    @Test func dragSequenceFiresOncePerCrossing() {
        var fires = 0
        var prev: Int? = nil
        let observations = [3, 3, 4, 4, 3, 3]  // first 3 latches; 3→4 fires; 4→3 fires
        for current in observations {
            let (fire, newPrev) = TimelineView.snapTransition(previous: prev, current: current)
            if fire { fires += 1 }
            prev = newPrev
        }
        #expect(fires == 2)
    }

    // MARK: - Modifier smoke

    private func sampleVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 2.0)
            ImageClip(img, duration: 3.0)
        }
    }

    @Test @MainActor func constructsWithModifierAttached() {
        _ = TimelineView(sampleVideo(), onReorder: { _ in })
            .onClipDragSnap {}
            .body
    }

    @Test @MainActor func composesWithFullCallbackSet() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        @State var zoom = TimelineZoom(pixelsPerSecond: 50)
        _ = TimelineView(
            sampleVideo(),
            currentTime: $t,
            zoom: $zoom,
            onReorder: { _ in },
            onTrackReorder: { _ in }
        )
        .fixedCenterPlayhead()
        .onZoomSnap { _ in }
        .onClipDragSnap {}
        .body
    }
}
