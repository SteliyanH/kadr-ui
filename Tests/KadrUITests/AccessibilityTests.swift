import XCTest
import SwiftUI
import CoreMedia
import Kadr
import ViewInspector
@testable import KadrUI

/// Accessibility tests for v0.11 Tier 1 — timeline + overlay canvas.
///
/// **Scope.** Two layers, mirroring `GestureWiringTests`:
/// 1. Pure-seam tests on the VoiceOver label / value derivations (static helpers),
///    which is where the spoken-string logic lives.
/// 2. `inspect()` smoke tests that the views still build with the accessibility
///    modifiers attached.
///
/// **What this can't do.** ViewInspector can't confirm VoiceOver actually *speaks*
/// these or that adjustable actions fire end-to-end — that stays with the manual
/// VoiceOver pass in the release checklist. These guard against the strings drifting
/// and against a refactor dropping the modifiers (build break).
@MainActor
final class AccessibilityTests: XCTestCase {

    private func sampleVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 2.0).id(ClipID("a"))
            ImageClip(img, duration: 2.0).id(ClipID("b"))
        }
    }

    private func sampleOverlayVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 2.0)
        }
        .overlay(TextOverlay("Hello").id(LayerID("title")))
    }

    // MARK: - Clip label / value derivation

    func testClipAccessibilityLabelByKind() {
        let img = PlatformImage()
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        XCTAssertEqual(TimelineView.clipAccessibilityLabel(for: VideoClip(url: url), index: 0), "Video clip 1")
        XCTAssertEqual(TimelineView.clipAccessibilityLabel(for: ImageClip(img, duration: 1), index: 1), "Image clip 2")
    }

    func testTransitionAccessibilityLabel() {
        let t = Kadr.Transition.dissolve(duration: 0.5)
        XCTAssertEqual(TimelineView.clipAccessibilityLabel(for: t, index: 2), "Transition 3")
    }

    func testClipAccessibilityValueIncludesSelectionState() {
        XCTAssertEqual(TimelineView.clipAccessibilityValue(seconds: 3.0, isSelected: false), "3.0 seconds")
        XCTAssertEqual(TimelineView.clipAccessibilityValue(seconds: 3.0, isSelected: true), "3.0 seconds, selected")
    }

    // MARK: - Overlay label derivation

    func testOverlayAccessibilityLabelByKind() {
        let img = PlatformImage()
        XCTAssertEqual(OverlayHost.overlayAccessibilityLabel(for: TextOverlay("Hi")), "Text overlay: Hi")
        XCTAssertEqual(OverlayHost.overlayAccessibilityLabel(for: ImageOverlay(img)), "Image overlay")
        XCTAssertEqual(OverlayHost.overlayAccessibilityLabel(for: StickerOverlay(img)), "Sticker overlay")
    }

    func testEmptyTextOverlayFallsBackToKindLabel() {
        XCTAssertEqual(OverlayHost.overlayAccessibilityLabel(for: TextOverlay("   ")), "Text overlay")
    }

    // MARK: - Views build with accessibility modifiers attached

    func testTimelineViewWithAccessibleClipsBuilds() throws {
        @State var time = CMTime(seconds: 1, preferredTimescale: 600)
        @State var selected: ClipID? = nil
        let view = TimelineView(
            sampleVideo(),
            currentTime: $time,
            selectedClipID: $selected,
            onTrim: { _ in }
        )
        XCTAssertNoThrow(try view.inspect())
    }

    func testOverlayHostWithAccessibleOverlaysBuilds() throws {
        @State var selected: LayerID? = nil
        let view = OverlayHost(sampleOverlayVideo(), selectedLayerID: $selected)
            .onLayerTap { _ in }
        XCTAssertNoThrow(try view.inspect())
    }
}
