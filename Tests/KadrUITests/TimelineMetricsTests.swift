import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// The layout numbers a host has to agree with, and the per-kind lane heights
/// that a single `laneHeight` could not express.
///
/// These exist because a consuming app was carrying private copies of all four
/// measurements — `scrubStripHeight`, the default lane height, the chain audio
/// strip and the lane gap — and re-implementing the height arithmetic beside
/// them. Copies drift; this is the version that cannot.
struct TimelineMetricsTests {

    // MARK: - The constants are the ones actually laid out with

    @Test func metricsAreTheValuesTheViewUses() {
        #expect(TimelineView.Metrics.scrubStripHeight == 14)
        #expect(TimelineView.Metrics.defaultLaneHeight == 40)
        #expect(TimelineView.Metrics.chainAudioLaneHeight == 12)
        #expect(TimelineView.Metrics.defaultLaneSpacing == 4)
    }

    // MARK: - Content height, so nobody re-derives it

    @Test func contentHeightCountsLanesStripAndGaps() {
        // 2 lanes at 40, a 14pt strip, 3 rows so 2 gaps at 4.
        let h = TimelineView.contentHeight(laneCount: 2)
        let expected: CGFloat = 40 + 40 + 14 + 8
        #expect(h == expected)
    }

    @Test func contentHeightWithoutScrubStripDropsItAndItsGap() {
        let withStrip = TimelineView.contentHeight(laneCount: 2)
        let without = TimelineView.contentHeight(laneCount: 2, includesScrubStrip: false)
        #expect(without == withStrip - TimelineView.Metrics.scrubStripHeight - TimelineView.Metrics.defaultLaneSpacing)
    }

    @Test func contentHeightHonoursPerKindHeights() {
        let heights = TimelineView.LaneHeights(video: 44, overlay: 18, audio: 22)
        // 2 video lanes at 44 + 1 audio lane at 22, strip, 4 rows so 3 gaps.
        let h = TimelineView.contentHeight(
            laneCount: 3,
            laneHeights: heights,
            audioLaneCount: 1
        )
        let expected: CGFloat = 44 + 44 + 22 + 14 + 12
        #expect(h == expected)
    }

    @Test func noLanesIsJustTheStrip() {
        #expect(TimelineView.contentHeight(laneCount: 0) == TimelineView.Metrics.scrubStripHeight)
        #expect(TimelineView.contentHeight(laneCount: 0, includesScrubStrip: false) == 0)
    }

    // MARK: - Per-kind lane heights

    @Test func uniformReproducesTheOldSingleHeightBehaviour() {
        let u = TimelineView.LaneHeights.uniform(40)
        #expect(u.video == 40 && u.overlay == 40 && u.audio == 40)
    }

    @Test func audioLanesCanBeShorterThanVideoLanes() {
        // The case that could not be expressed before: the design asks for
        // video 44, overlay 18, audio 22.
        let h = TimelineView.LaneHeights(video: 44, overlay: 18, audio: 22)
        #expect(h.height(for: .audio(index: 0, label: nil)) == 22)
        #expect(h.height(for: .implicitChain) == 44)
        #expect(h.height(for: .track(index: 0, startTime: .zero, label: nil)) == 44)
        #expect(h.height(for: .freeFloaters(packIndex: 0)) == 18)
    }

    @Test @MainActor func laneHeightsDefaultToUniformOfLaneHeight() {
        // Passing only `laneHeight:` must behave exactly as before.
        let img = PlatformImage()
        let video = Video { ImageClip(img, duration: 1.0) }
        let view = TimelineView(video, laneHeight: 56)
        #expect(view.laneHeightsForTesting == .uniform(56))
    }
}
