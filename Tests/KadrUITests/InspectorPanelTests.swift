import Testing
import SwiftUI
import Kadr
@testable import KadrUI

/// Tests for `InspectorPanel` — pure helpers (lookup, normalized projection, filter
/// scalar/range/label), and smoke tests on the View body.
struct InspectorPanelTests {

    // MARK: - clipFor(id:in:)

    @Test func clipForFindsTopLevelClip() {
        let id = ClipID("a")
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0).id(id)
            ImageClip(PlatformImage(), duration: 1.0)
        }
        let found = InspectorPanel.clipFor(id: id, in: video)
        #expect(found?.clipID == id)
    }

    @Test func clipForFindsClipInsideTrack() {
        let id = ClipID("inner")
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0)
            Track {
                ImageClip(PlatformImage(), duration: 1.0).id(id)
            }
        }
        let found = InspectorPanel.clipFor(id: id, in: video)
        #expect(found?.clipID == id)
    }

    @Test func clipForReturnsNilForUnknownID() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0).id(ClipID("known"))
        }
        let found = InspectorPanel.clipFor(id: ClipID("unknown"), in: video)
        #expect(found == nil)
    }

    // MARK: - normalizedXY(of:)

    @Test func normalizedXYPassesThroughNormalized() {
        let (x, y) = InspectorPanel.normalizedXY(of: .normalized(x: 0.3, y: 0.7))
        #expect(x == 0.3)
        #expect(y == 0.7)
    }

    @Test func normalizedXYDividesPercentBy100() {
        let (x, y) = InspectorPanel.normalizedXY(of: .percent(x: 25, y: 75))
        #expect(abs(x - 0.25) < 0.0001)
        #expect(abs(y - 0.75) < 0.0001)
    }

    @Test func normalizedXYFallsBackToCenterForPixels() {
        let (x, y) = InspectorPanel.normalizedXY(of: .pixels(x: 100, y: 200))
        #expect(x == 0.5)
        #expect(y == 0.5)
    }

    // MARK: - allAnchors / label(for: Anchor)

    @Test func allAnchorsHasNineCasesInOrder() {
        #expect(InspectorPanel.allAnchors.count == 9)
        #expect(InspectorPanel.allAnchors[0] == .topLeft)
        #expect(InspectorPanel.allAnchors[4] == .center)
        #expect(InspectorPanel.allAnchors[8] == .bottomRight)
    }

    @Test func anchorLabelsAreNonEmpty() {
        for anchor in InspectorPanel.allAnchors {
            #expect(!InspectorPanel.label(for: anchor).isEmpty)
        }
    }

    // MARK: - Filter scalar / range / label

    @Test func filterScalarExtractsValueForScalarFilters() {
        #expect(InspectorPanel.scalar(of: .brightness(0.3)) == 0.3)
        #expect(InspectorPanel.scalar(of: .contrast(1.5)) == 1.5)
        #expect(InspectorPanel.scalar(of: .saturation(0.8)) == 0.8)
        #expect(InspectorPanel.scalar(of: .exposure(-0.5)) == -0.5)
        #expect(InspectorPanel.scalar(of: .sepia(intensity: 0.6)) == 0.6)
        #expect(InspectorPanel.scalar(of: .gaussianBlur(radius: 12)) == 12)
        #expect(InspectorPanel.scalar(of: .vignette(intensity: 0.7)) == 0.7)
        #expect(InspectorPanel.scalar(of: .sharpen(amount: 0.9)) == 0.9)
        #expect(InspectorPanel.scalar(of: .zoomBlur(amount: 30)) == 30)
        #expect(InspectorPanel.scalar(of: .glow(intensity: 0.4)) == 0.4)
    }

    @Test func filterScalarReturnsNilForNonScalarFilters() {
        #expect(InspectorPanel.scalar(of: .mono) == nil)
    }

    @Test func filterRangeMatchesExpectedBoundsForKnownPresets() {
        #expect(InspectorPanel.range(of: .brightness(0))?.lowerBound == -1.0)
        #expect(InspectorPanel.range(of: .brightness(0))?.upperBound == 1.0)
        #expect(InspectorPanel.range(of: .gaussianBlur(radius: 0))?.upperBound == 50.0)
        #expect(InspectorPanel.range(of: .sepia(intensity: 0))?.lowerBound == 0.0)
        #expect(InspectorPanel.range(of: .mono) == nil)
    }

    @Test func filterLabelsAreNonEmpty() {
        let allFilters: [Filter] = [
            .brightness(0), .contrast(1), .saturation(1), .exposure(0),
            .sepia(intensity: 1), .mono,
            .gaussianBlur(radius: 10), .vignette(intensity: 1),
            .sharpen(amount: 0.4), .zoomBlur(amount: 20), .glow(intensity: 1),
        ]
        for filter in allFilters {
            #expect(!InspectorPanel.label(for: filter).isEmpty)
        }
    }

    // MARK: - View body smoke tests

    @MainActor
    @Test func bodyRendersForSelectedClip() {
        let id = ClipID("sel")
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0).id(id)
        }
        let selected: Binding<ClipID?> = .constant(id)
        let panel = InspectorPanel(video, selectedClipID: selected)
        _ = panel.body  // Should not crash.
    }

    @MainActor
    @Test func bodyRendersPlaceholderWhenNoSelection() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0).id(ClipID("a"))
        }
        let selected: Binding<ClipID?> = .constant(nil)
        let panel = InspectorPanel(video, selectedClipID: selected)
        _ = panel.body
    }

    @MainActor
    @Test func bodyRendersPlaceholderForUnknownClipID() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0).id(ClipID("known"))
        }
        let selected: Binding<ClipID?> = .constant(ClipID("unknown"))
        let panel = InspectorPanel(video, selectedClipID: selected)
        _ = panel.body
    }
}
