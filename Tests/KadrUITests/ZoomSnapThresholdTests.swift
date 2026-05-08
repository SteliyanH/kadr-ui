import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Pure-logic tests for ``ZoomSnapThreshold/crossings(prev:current:in:)`` and
/// smoke for the ``TimelineView/onZoomSnap(_:)`` modifier. The gesture-driven
/// emission path is exercised manually via `kadr-reels-studio` v0.4 Tier 3's
/// haptic wiring; the math is here.
struct ZoomSnapThresholdTests {

    // Custom thresholds keep these tests independent of the standard list's
    // tuning — drift in `.standard` over time won't cascade through.
    private let thresholds: [ZoomSnapThreshold] = [
        .init(pixelsPerSecond: 10, label: "10"),
        .init(pixelsPerSecond: 50, label: "50"),
        .init(pixelsPerSecond: 100, label: "100"),
    ]

    // MARK: - Inside one bracket → no fire

    @Test func staysInsideBracketEmitsNothing() {
        let result = ZoomSnapThreshold.crossings(prev: 60, current: 70, in: thresholds)
        #expect(result.isEmpty)
    }

    @Test func equalPrevAndCurrentEmitsNothing() {
        let result = ZoomSnapThreshold.crossings(prev: 50, current: 50, in: thresholds)
        #expect(result.isEmpty)
    }

    // MARK: - Single crossing

    @Test func crossOneThresholdUpward() {
        let result = ZoomSnapThreshold.crossings(prev: 40, current: 60, in: thresholds)
        #expect(result.map(\.pixelsPerSecond) == [50])
    }

    @Test func crossOneThresholdDownward() {
        let result = ZoomSnapThreshold.crossings(prev: 60, current: 40, in: thresholds)
        #expect(result.map(\.pixelsPerSecond) == [50])
    }

    // MARK: - Multi-crossing on rapid zoom

    @Test func rapidZoomUpwardEmitsAllCrossed() {
        let result = ZoomSnapThreshold.crossings(prev: 5, current: 200, in: thresholds)
        #expect(result.map(\.pixelsPerSecond) == [10, 50, 100])
    }

    @Test func rapidZoomDownwardEmitsAllCrossedInInputOrder() {
        // Downward zoom — same set, but the input list order is preserved
        // (we don't re-sort by direction). Consumers can read direction from
        // prev / current themselves if they care.
        let result = ZoomSnapThreshold.crossings(prev: 200, current: 5, in: thresholds)
        #expect(result.map(\.pixelsPerSecond) == [10, 50, 100])
    }

    // MARK: - Endpoint equality doesn't count

    @Test func landingExactlyOnThresholdDoesNotCount() {
        let result = ZoomSnapThreshold.crossings(prev: 30, current: 50, in: thresholds)
        #expect(result.isEmpty)
    }

    @Test func startingExactlyOnThresholdDoesNotCount() {
        let result = ZoomSnapThreshold.crossings(prev: 50, current: 70, in: thresholds)
        #expect(result.isEmpty)
    }

    // MARK: - Standard list shape

    @Test func standardListIsAscendingByPixelsPerSecond() {
        let densities = ZoomSnapThreshold.standard.map(\.pixelsPerSecond)
        #expect(densities == densities.sorted())
    }

    @Test func standardListLabelsMatchExpectedSet() {
        let labels = Set(ZoomSnapThreshold.standard.map(\.label))
        #expect(labels == Set(["30s", "5s", "1s", "1f"]))
    }
}

// MARK: - TimelineView modifier smoke

struct OnZoomSnapModifierTests {

    private func sampleVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 4.0)
        }
    }

    @Test @MainActor func constructsWithModifierAttached() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        @State var zoom = TimelineZoom(pixelsPerSecond: 50)
        _ = TimelineView(sampleVideo(), currentTime: $t, zoom: $zoom)
            .onZoomSnap { _ in }
            .body
    }

    @Test @MainActor func composesWithFixedCenterPlayhead() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        @State var zoom = TimelineZoom(pixelsPerSecond: 50)
        _ = TimelineView(sampleVideo(), currentTime: $t, zoom: $zoom)
            .fixedCenterPlayhead()
            .onZoomSnap { _ in }
            .body
    }

    @Test @MainActor func constructsWhenZoomNotBound() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        // Without zoom there's no MagnificationGesture; the modifier should
        // still attach without crashing — it just never fires.
        _ = TimelineView(sampleVideo(), currentTime: $t)
            .onZoomSnap { _ in }
            .body
    }
}
