import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Smoke tests for the v0.9 ``TimelineView/fixedCenterPlayhead(_:)`` modifier.
/// Real centering is visual — exercised manually via the example app and via
/// `kadr-reels-studio` v0.4 Tier 2's manual QA pass. These tests cover the
/// public modifier contract: body construction across each combination of
/// `currentTime` / `zoom` / modifier-flipped state, plus the round-trip
/// through `fixedCenterPlayhead(false)`.
struct FixedCenterPlayheadTests {

    private func sampleVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 4.0)
            ImageClip(img, duration: 4.0)
        }
    }

    // MARK: - Modifier flips on / off

    @Test @MainActor func constructsWithModifierEnabled() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        @State var zoom = TimelineZoom(pixelsPerSecond: 50)
        _ = TimelineView(sampleVideo(), currentTime: $t, zoom: $zoom)
            .fixedCenterPlayhead()
            .body
    }

    @Test @MainActor func constructsWithModifierExplicitlyDisabled() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        @State var zoom = TimelineZoom(pixelsPerSecond: 50)
        _ = TimelineView(sampleVideo(), currentTime: $t, zoom: $zoom)
            .fixedCenterPlayhead(false)
            .body
    }

    // MARK: - No-op safety

    /// Without `currentTime`, the playhead never renders — the modifier has
    /// nothing to anchor. Construction must still succeed.
    @Test @MainActor func constructsWhenCurrentTimeIsNil() {
        @State var zoom = TimelineZoom(pixelsPerSecond: 50)
        _ = TimelineView(sampleVideo(), zoom: $zoom)
            .fixedCenterPlayhead()
            .body
    }

    /// Without `zoom`, there's no scroll view — the timeline lays out
    /// fit-to-width. Modifier must no-op silently.
    @Test @MainActor func constructsWhenZoomIsNil() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        _ = TimelineView(sampleVideo(), currentTime: $t)
            .fixedCenterPlayhead()
            .body
    }

    /// Modifier on a timeline with neither `currentTime` nor `zoom`. Should
    /// remain inert.
    @Test @MainActor func constructsWithNoBindings() {
        _ = TimelineView(sampleVideo())
            .fixedCenterPlayhead()
            .body
    }

    // MARK: - Round-trip

    /// Modifier returns a value type — applying twice with different values
    /// keeps only the latest setting. Body construction must succeed in
    /// both directions.
    @Test @MainActor func togglesIdempotently() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        @State var zoom = TimelineZoom(pixelsPerSecond: 50)
        let timeline = TimelineView(sampleVideo(), currentTime: $t, zoom: $zoom)
        _ = timeline.fixedCenterPlayhead(true).fixedCenterPlayhead(false).body
        _ = timeline.fixedCenterPlayhead(false).fixedCenterPlayhead(true).body
    }

    // MARK: - Composed with other modifiers

    /// Verify it composes alongside `selectedClipID` + the trim / reorder
    /// callback set — the most common reels-studio configuration.
    @Test @MainActor func composesWithFullCallbackSet() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        @State var zoom = TimelineZoom(pixelsPerSecond: 50)
        @State var selected: ClipID? = nil
        _ = TimelineView(
            sampleVideo(),
            currentTime: $t,
            selectedClipID: $selected,
            zoom: $zoom,
            onReorder: { _ in },
            onTrim: { _ in }
        )
        .fixedCenterPlayhead()
        .body
    }
}
