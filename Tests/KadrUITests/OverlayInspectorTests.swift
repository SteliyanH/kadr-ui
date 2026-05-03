import Testing
import SwiftUI
import CoreMedia
import Foundation
import Kadr
@testable import KadrUI

/// Pure-helper + body-smoke tests for `OverlayInspectorPanel` and
/// `OverlayKeyframeEditor`.
struct OverlayInspectorTests {

    // MARK: - Fixtures

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func videoWith(overlay: any Overlay, clipDuration: Double = 5.0) -> Video {
        Video {
            ImageClip(PlatformImage(), duration: clipDuration)
        }
        .overlay(overlay)
    }

    // MARK: - overlayFor lookup

    @Test func overlayForReturnsOverlayWithMatchingID() {
        let text = TextOverlay("Hi").id("greeting")
        let video = videoWith(overlay: text)
        let found = InspectorPanel.overlayFor(id: "greeting", in: video)
        #expect(found?.layerID == "greeting")
    }

    @Test func overlayForReturnsNilForUnknownID() {
        let text = TextOverlay("Hi").id("greeting")
        let video = videoWith(overlay: text)
        #expect(InspectorPanel.overlayFor(id: "missing", in: video) == nil)
    }

    @Test func overlayForReturnsFirstMatch() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        .overlay(TextOverlay("a").id("dup"))
        .overlay(TextOverlay("b").id("dup"))

        let found = InspectorPanel.overlayFor(id: "dup", in: video) as? TextOverlay
        #expect(found?.text == "a")
    }

    // MARK: - textAnimationKind round-trip

    @Test func textAnimationKindNilProducesNone() {
        #expect(InspectorPanel.textAnimationKind(for: nil) == .none)
    }

    @Test func textAnimationKindFadeIn() {
        let kind = InspectorPanel.textAnimationKind(for: FadeIn(duration: 0.5))
        #expect(kind == .fadeIn(durationSeconds: 0.5))
    }

    @Test func textAnimationKindSlideInPreservesDirection() {
        let kind = InspectorPanel.textAnimationKind(
            for: SlideIn(from: .fromTop, duration: 0.75)
        )
        #expect(kind == .slideIn(direction: .fromTop, durationSeconds: 0.75))
    }

    @Test func textAnimationKindScaleUp() {
        let kind = InspectorPanel.textAnimationKind(for: ScaleUp(duration: 0.5))
        #expect(kind == .scaleUp(durationSeconds: 0.5))
    }

    // textAnimation builds back round-trip
    @Test func textAnimationBuildsFadeIn() {
        let anim = InspectorPanel.textAnimation(forKind: .fadeIn(durationSeconds: 0.5))
        let fade = anim as? FadeIn
        #expect(fade != nil)
        #expect(CMTimeGetSeconds(fade?.duration ?? .zero) == 0.5)
    }

    @Test func textAnimationBuildsSlideIn() {
        let anim = InspectorPanel.textAnimation(
            forKind: .slideIn(direction: .fromBottom, durationSeconds: 0.4)
        )
        let slide = anim as? SlideIn
        #expect(slide != nil)
        if case .fromBottom = slide?.direction { } else {
            Issue.record("Expected .fromBottom")
        }
    }

    @Test func textAnimationNoneAndCustomReturnNil() {
        #expect(InspectorPanel.textAnimation(forKind: .none) == nil)
        #expect(InspectorPanel.textAnimation(forKind: .custom) == nil)
    }

    // MARK: - animation picker presets

    @Test func animationPresetsListIsExpected() {
        let labels = OverlayInspectorPanel.animationPresets.map(\.label)
        #expect(labels.contains("None"))
        #expect(labels.contains("Fade In (0.5s)"))
        #expect(labels.contains("Scale Up (0.5s)"))
    }

    @Test func animationPickerIndexNoneIsZero() {
        #expect(OverlayInspectorPanel.animationPickerIndex(for: .none) == 0)
    }

    @Test func animationPickerIndexCustomDefaultsToZero() {
        // Custom round-trips to "None" in the picker — consumer can clear it
        // by re-selecting None, but the picker can't re-author a custom anim.
        #expect(OverlayInspectorPanel.animationPickerIndex(for: .custom) == 0)
    }

    @Test func animationPickerIndexSlideInDirections() {
        let left = OverlayInspectorPanel.animationPickerIndex(
            for: .slideIn(direction: .fromLeft, durationSeconds: 0.5)
        )
        let right = OverlayInspectorPanel.animationPickerIndex(
            for: .slideIn(direction: .fromRight, durationSeconds: 0.5)
        )
        #expect(left != right)
    }

    // MARK: - OverlayKeyframeEditor.propertyOptions

    @Test func propertyOptionsForImageOverlayHasPositionAndSize() {
        let img = ImageOverlay(PlatformImage()).id("img")
        let props = OverlayKeyframeEditor.propertyOptions(for: img)
        #expect(props == [.position, .size])
    }

    @Test func propertyOptionsForStickerHasPositionAndSize() {
        let sticker = StickerOverlay(PlatformImage()).id("sticker")
        let props = OverlayKeyframeEditor.propertyOptions(for: sticker)
        #expect(props == [.position, .size])
    }

    @Test func propertyOptionsForTextOverlayIsEmpty() {
        // TextOverlay isn't keyframe-animatable in kadr v0.10 — text overlays
        // use the enum-driven TextAnimation surface instead.
        let text = TextOverlay("hi").id("text")
        let props = OverlayKeyframeEditor.propertyOptions(for: text)
        #expect(props.isEmpty)
    }

    // MARK: - keyframesForProperty

    @Test func keyframesForPositionReadsFromAnimation() {
        let pos = Kadr.Animation<Position>.keyframes([
            .at(0.0, value: .topLeft),
            .at(2.0, value: .bottomRight)
        ])
        let img = ImageOverlay(PlatformImage())
            .id("img")
            .position(.center, animation: pos)
        let times = OverlayKeyframeEditor.keyframesForProperty(.position, on: img)
        #expect(times.count == 2)
        #expect(abs(CMTimeGetSeconds(times[0])) < 0.0001)
        #expect(abs(CMTimeGetSeconds(times[1]) - 2.0) < 0.0001)
    }

    @Test func keyframesForSizeReturnsEmptyWhenNoAnimation() {
        let img = ImageOverlay(PlatformImage()).id("img")
        let times = OverlayKeyframeEditor.keyframesForProperty(.size, on: img)
        #expect(times.isEmpty)
    }

    // MARK: - labels

    @Test func propertyLabelsAreHumanReadable() {
        #expect(OverlayKeyframeEditor.label(for: .position) == "Position")
        #expect(OverlayKeyframeEditor.label(for: .size) == "Size")
    }

    // MARK: - OverlayInspectorPanel body smoke

    @MainActor
    @Test func inspectorBodyEmptyForUnknownID() {
        let video = videoWith(overlay: TextOverlay("hi").id("x"))
        let view = OverlayInspectorPanel(video, selectedOverlayID: .constant("missing"))
        _ = view.body
    }

    @MainActor
    @Test func inspectorBodyConstructsForTextOverlay() {
        let video = videoWith(overlay: TextOverlay("Hello").id("text"))
        let view = OverlayInspectorPanel(
            video,
            selectedOverlayID: .constant("text"),
            onText: { _, _ in }
        )
        _ = view.body
    }

    @MainActor
    @Test func inspectorBodyConstructsForStickerOverlay() {
        let video = videoWith(overlay: StickerOverlay(PlatformImage()).id("sticker"))
        let view = OverlayInspectorPanel(
            video,
            selectedOverlayID: .constant("sticker"),
            onRotation: { _, _ in }
        )
        _ = view.body
    }

    @MainActor
    @Test func inspectorBodyConstructsForImageOverlay() {
        let video = videoWith(overlay: ImageOverlay(PlatformImage()).id("img"))
        let view = OverlayInspectorPanel(video, selectedOverlayID: .constant("img"))
        _ = view.body
    }

    // MARK: - OverlayKeyframeEditor body smoke

    @MainActor
    @Test func keyframeEditorBodyEmptyForUnknownID() {
        let video = videoWith(overlay: ImageOverlay(PlatformImage()).id("img"))
        let view = OverlayKeyframeEditor(
            video,
            selectedOverlayID: .constant("missing"),
            currentTime: .constant(.zero)
        )
        _ = view.body
    }

    @MainActor
    @Test func keyframeEditorBodyConstructsForImageOverlay() {
        let video = videoWith(overlay: ImageOverlay(PlatformImage()).id("img"))
        let view = OverlayKeyframeEditor(
            video,
            selectedOverlayID: .constant("img"),
            currentTime: .constant(cmt(1.0)),
            onAdd: { _, _, _ in },
            onRemove: { _, _, _ in },
            onRetime: { _, _, _, _ in }
        )
        _ = view.body
    }

    @MainActor
    @Test func keyframeEditorBodyConstructsForTextOverlayWithEmptyRows() {
        // Selecting a TextOverlay yields zero rows. Body still constructs.
        let video = videoWith(overlay: TextOverlay("hi").id("text"))
        let view = OverlayKeyframeEditor(
            video,
            selectedOverlayID: .constant("text"),
            currentTime: .constant(.zero)
        )
        _ = view.body
    }
}
