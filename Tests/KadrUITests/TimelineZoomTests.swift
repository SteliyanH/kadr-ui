import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Tests for v0.7 Tier 1 — `TimelineZoom` value type, clamping, fit-to-width math,
/// and `TimelineView` body construction with a non-nil zoom binding.
struct TimelineZoomTests {

    // MARK: - Initializer / clamping

    @Test func initClampsBelowFloor() {
        let zoom = TimelineZoom(pixelsPerSecond: 1.0)
        #expect(zoom.pixelsPerSecond == TimelineZoom.minPixelsPerSecond)
    }

    @Test func initClampsAboveCeiling() {
        let zoom = TimelineZoom(pixelsPerSecond: 9999)
        #expect(zoom.pixelsPerSecond == TimelineZoom.maxPixelsPerSecond)
    }

    @Test func initPassesThroughInRange() {
        let zoom = TimelineZoom(pixelsPerSecond: 64)
        #expect(zoom.pixelsPerSecond == 64)
    }

    // MARK: - fitToWidth

    @Test func fitToWidthDividesWidthByDuration() {
        let zoom = TimelineZoom.fitToWidth(360, totalSeconds: 30)
        #expect(zoom.pixelsPerSecond == 12) // 360 / 30
    }

    @Test func fitToWidthClampsForLongCompositions() {
        // 360 px / 1000 seconds = 0.36 px/s, well below the floor.
        let zoom = TimelineZoom.fitToWidth(360, totalSeconds: 1000)
        #expect(zoom.pixelsPerSecond == TimelineZoom.minPixelsPerSecond)
    }

    @Test func fitToWidthHandlesZeroDuration() {
        let zoom = TimelineZoom.fitToWidth(360, totalSeconds: 0)
        #expect(zoom.pixelsPerSecond == TimelineZoom.minPixelsPerSecond)
    }

    @Test func fitToWidthHandlesZeroWidth() {
        let zoom = TimelineZoom.fitToWidth(0, totalSeconds: 30)
        #expect(zoom.pixelsPerSecond == TimelineZoom.minPixelsPerSecond)
    }

    // MARK: - zoomed(by:)

    @Test func zoomedDoublesDensity() {
        let zoom = TimelineZoom(pixelsPerSecond: 50).zoomed(by: 2)
        #expect(zoom.pixelsPerSecond == 100)
    }

    @Test func zoomedClampsAtFloor() {
        let zoom = TimelineZoom(pixelsPerSecond: 16).zoomed(by: 0.001)
        #expect(zoom.pixelsPerSecond == TimelineZoom.minPixelsPerSecond)
    }

    @Test func zoomedClampsAtCeiling() {
        let zoom = TimelineZoom(pixelsPerSecond: 200).zoomed(by: 100)
        #expect(zoom.pixelsPerSecond == TimelineZoom.maxPixelsPerSecond)
    }

    // MARK: - Equatable

    @Test func zoomEqualityCompiles() {
        #expect(TimelineZoom(pixelsPerSecond: 50) == TimelineZoom(pixelsPerSecond: 50))
        #expect(TimelineZoom(pixelsPerSecond: 50) != TimelineZoom(pixelsPerSecond: 60))
    }

    // MARK: - clamp helper

    @Test func clampClampsBelowFloor() {
        #expect(TimelineZoom.clamp(0.5) == TimelineZoom.minPixelsPerSecond)
    }

    @Test func clampClampsAboveCeiling() {
        #expect(TimelineZoom.clamp(99999) == TimelineZoom.maxPixelsPerSecond)
    }

    @Test func clampPassesThroughMid() {
        #expect(TimelineZoom.clamp(123) == 123)
    }

    // MARK: - TimelineView body smoke

    @MainActor
    @Test func timelineViewConstructsWithZoomBinding() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        let zoom = Binding<TimelineZoom>.constant(TimelineZoom(pixelsPerSecond: 50))
        let view = TimelineView(video, zoom: zoom)
        _ = view.body
    }

    @MainActor
    @Test func timelineViewBackwardsCompatibleWithoutZoom() {
        // v0.6 call sites — no zoom param — must still compile and render.
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        let view = TimelineView(video)
        _ = view.body
    }
}
