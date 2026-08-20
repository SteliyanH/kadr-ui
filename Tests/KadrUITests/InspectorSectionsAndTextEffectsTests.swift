import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Section selection, and the text effects kadr shipped in v0.12 that this
/// package never surfaced.
struct InspectorSectionsAndTextEffectsTests {

    // MARK: - Sections

    @Test func everySectionThePanelDrawsIsSelectable() {
        #expect(InspectorPanel.Section.allCases.count == 3)
        #expect(InspectorPanel.Section.allCases.map(\.rawValue) == ["transform", "opacity", "filters"])
    }

    @Test func sectionTitlesMatchTheHeadingsThePanelDraws() {
        // The point of exposing these: a host's segmented control and the panel
        // cannot disagree about what a section is called.
        #expect(InspectorPanel.Section.transform.title == "Transform")
        #expect(InspectorPanel.Section.opacity.title == "Opacity")
        #expect(InspectorPanel.Section.filters.title == "Filters")
    }

    @Test @MainActor func panelConstructsWithoutASectionBinding() {
        let img = PlatformImage()
        let video = Video { ImageClip(img, duration: 1) }
        _ = InspectorPanel(video, selectedClipID: .constant(nil))
    }

    @Test @MainActor func panelConstructsWithASectionBinding() {
        let img = PlatformImage()
        let video = Video { ImageClip(img, duration: 1) }
        _ = InspectorPanel(video, selectedClipID: .constant(nil), selectedSection: .constant(.filters))
    }

    // MARK: - Shadow rebuilding

    @Test func aShadowWithNoBlurAndNoOffsetIsNoShadow() {
        // Otherwise a caller storing the value cannot tell "off" from
        // "on but invisible".
        #expect(OverlayInspectorPanel.shadow(from: nil, blur: 0) == nil)
        #expect(OverlayInspectorPanel.shadow(from: nil, offsetX: 0) == nil)
    }

    @Test func anyVisibleComponentKeepsTheShadow() {
        #expect(OverlayInspectorPanel.shadow(from: nil, blur: 4) != nil)
        #expect(OverlayInspectorPanel.shadow(from: nil, offsetX: 2) != nil)
        #expect(OverlayInspectorPanel.shadow(from: nil, offsetY: -2) != nil)
    }

    @Test func editingOneFieldPreservesTheOthers() {
        let start = TextShadow(offset: CGSize(width: 3, height: 4), blur: 5)
        let moved = OverlayInspectorPanel.shadow(from: start, offsetX: 9)
        #expect(moved?.offset.width == 9)
        #expect(moved?.offset.height == 4, "Changing X must not reset Y.")
        #expect(moved?.blur == 5, "Changing offset must not reset blur.")
    }

    @Test func negativeBlurIsClampedRatherThanPassedOn() {
        let s = OverlayInspectorPanel.shadow(from: TextShadow(offset: .zero, blur: 6), blur: -3)
        // Negative blur with no offset is not a visible shadow.
        #expect(s == nil)
        let withOffset = OverlayInspectorPanel.shadow(
            from: TextShadow(offset: CGSize(width: 2, height: 0), blur: 6), blur: -3
        )
        #expect(withOffset?.blur == 0, "Blur must never go negative.")
    }

    @Test func offsetsSurviveRoundTripInBothDirections() {
        let s = OverlayInspectorPanel.shadow(from: nil, offsetY: -7)
        #expect(s?.offset.height == -7, "Negative Y is a legitimate shadow direction.")
    }
}
