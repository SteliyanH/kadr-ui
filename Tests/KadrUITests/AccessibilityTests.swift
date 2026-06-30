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

    // MARK: - Tier 2: editors with control points

    func testKeyframeEditorWithMarkersBuilds() throws {
        let id = ClipID("a")
        let anim = Animation<Double>.keyframes([.at(0.0, value: 0.0), .at(1.0, value: 1.0)])
        let video = Video {
            ImageClip(PlatformImage(), duration: 2.0).id(id).opacity(0.0, animation: anim)
        }
        let editor = KeyframeEditor(
            video,
            selectedClipID: .constant(id),
            currentTime: .constant(.zero),
            onAdd: { _, _, _ in },
            onRemove: { _, _, _ in },
            onRetime: { _, _, _, _ in }
        )
        XCTAssertNoThrow(try editor.inspect())
    }

    func testSpeedCurveEditorWithMarkersBuilds() throws {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        let curve = Animation<Double>.keyframes([.at(0.0, value: 1.0), .at(1.0, value: 2.0)])
        let clip = VideoClip(url: url).trimmed(to: 0.0...2.0).speed(.curved(curve))
        let view = SpeedCurveEditor(clip: clip, onUpdate: { _ in })
        XCTAssertNoThrow(try view.inspect())
    }

    // MARK: - Tier 3: inspector panels + caption editor

    func testInspectorPanelWithSlidersBuilds() throws {
        let id = ClipID("sel")
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0).id(id)
        }
        let panel = InspectorPanel(video, selectedClipID: .constant(id))
        XCTAssertNoThrow(try panel.inspect())
    }

    func testOverlayInspectorWithControlsBuilds() throws {
        let view = OverlayInspectorPanel(sampleOverlayVideo(), selectedOverlayID: .constant(LayerID("title")))
        XCTAssertNoThrow(try view.inspect())
    }

    func testCaptionEditorWithCuesAndPlayheadBuilds() throws {
        let cue = Caption(
            text: "Hello",
            timeRange: CMTimeRange(
                start: CMTime(seconds: 0.5, preferredTimescale: 600),
                duration: CMTime(seconds: 1.0, preferredTimescale: 600)
            )
        )
        let view = CaptionEditor(
            captions: [cue],
            compositionDuration: CMTime(seconds: 10, preferredTimescale: 600),
            currentTime: .constant(CMTime(seconds: 1, preferredTimescale: 600)),
            onUpdate: { _ in }
        )
        XCTAssertNoThrow(try view.inspect())
    }

    // MARK: - Tier 4: cross-cutting (zoom action + media views)

    func testAccessibleZoomMultipliesAndClamps() {
        // Normal step.
        XCTAssertEqual(TimelineView.accessibleZoom(from: 50, factor: 1.5), 75, accuracy: 0.001)
        // Clamps at the max (400).
        XCTAssertEqual(TimelineView.accessibleZoom(from: 300, factor: 1.5), 400, accuracy: 0.001)
        // Clamps at the min (8).
        XCTAssertEqual(TimelineView.accessibleZoom(from: 10, factor: 1 / 1.5), 8, accuracy: 0.001)
    }

    func testVideoPreviewBuildsWithStateLabels() throws {
        let view = VideoPreview(sampleVideo())
        XCTAssertNoThrow(try view.inspect())
    }

    func testThumbnailStripBuildsAsSummaryElement() throws {
        let view = ThumbnailStrip(sampleVideo(), count: 4)
        XCTAssertNoThrow(try view.inspect())
    }

    // MARK: - Adjustable-action step constants

    func testAccessibilityStepConstantsAreSane() {
        XCTAssertEqual(KeyframeEditor.retimeAccessibilityStep, 0.1, accuracy: 0.0001)
        XCTAssertEqual(SpeedCurveEditor.multiplierAccessibilityStep, 0.25, accuracy: 0.0001)
        XCTAssertEqual(TimelineView.zoomAccessibilityFactor, 1.5, accuracy: 0.0001)
    }
}
