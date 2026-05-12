import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Pure-logic tests for v0.10 Tier 2 ``OverlayHost/overlayMatchesSelection(id:single:set:)``,
/// plus body-construction smoke for the new selection bindings. Mirrors
/// v0.9.2's `ClipMatchesSelectionTests` shape — the rule is identical, the
/// scope just shifts from clip identities to layer identities.
struct OverlayMatchesSelectionTests {

    @Test func nilIDNeverMatches() {
        #expect(!OverlayHost.overlayMatchesSelection(
            id: nil, single: LayerID("a"), set: ["a"]
        ))
    }

    @Test func singleMatchAlone() {
        #expect(OverlayHost.overlayMatchesSelection(
            id: LayerID("a"), single: LayerID("a"), set: nil
        ))
    }

    @Test func setMatchAlone() {
        #expect(OverlayHost.overlayMatchesSelection(
            id: LayerID("a"), single: nil, set: [LayerID("a"), LayerID("b")]
        ))
    }

    @Test func neitherMatchReturnsFalse() {
        #expect(!OverlayHost.overlayMatchesSelection(
            id: LayerID("z"), single: LayerID("a"), set: [LayerID("b")]
        ))
    }

    @Test func bothNilReturnsFalse() {
        #expect(!OverlayHost.overlayMatchesSelection(
            id: LayerID("a"), single: nil, set: nil
        ))
    }

    @Test func unionReturnsTrueIfEitherMatches() {
        // Single matches; set doesn't.
        #expect(OverlayHost.overlayMatchesSelection(
            id: LayerID("a"), single: LayerID("a"), set: [LayerID("z")]
        ))
        // Set matches; single doesn't.
        #expect(OverlayHost.overlayMatchesSelection(
            id: LayerID("a"), single: LayerID("z"), set: [LayerID("a")]
        ))
        // Both match.
        #expect(OverlayHost.overlayMatchesSelection(
            id: LayerID("a"), single: LayerID("a"), set: [LayerID("a")]
        ))
    }

    @Test func emptySetIsNotAMatch() {
        #expect(!OverlayHost.overlayMatchesSelection(
            id: LayerID("a"), single: nil, set: []
        ))
    }
}

struct OverlayHostSelectionBindingsTests {

    private func sampleVideo() -> Video {
        Video {
            ImageClip(PlatformImage(), duration: 2.0)
        }
        .overlay(TextOverlay("hello").id(LayerID("title")))
        .overlay(StickerOverlay(PlatformImage()).id(LayerID("sticker-1")))
    }

    @Test @MainActor func constructsWithSelectedLayerIDBinding() {
        @State var single: LayerID? = nil
        _ = OverlayHost(sampleVideo(), selectedLayerID: $single).body
    }

    @Test @MainActor func constructsWithSelectedLayerIDsBinding() {
        @State var multi: Set<LayerID> = []
        _ = OverlayHost(sampleVideo(), selectedLayerIDs: $multi).body
    }

    @Test @MainActor func constructsWithBothBindings() {
        @State var single: LayerID? = nil
        @State var multi: Set<LayerID> = []
        _ = OverlayHost(
            sampleVideo(),
            selectedLayerID: $single,
            selectedLayerIDs: $multi
        ).body
    }

    @Test @MainActor func composesWithExistingOnLayerTap() {
        @State var single: LayerID? = nil
        _ = OverlayHost(sampleVideo(), selectedLayerID: $single)
            .onLayerTap { _ in }
            .body
    }

    @Test @MainActor func bindingTreatsPreselectedOverlayAsSelected() {
        // Set up an initial selection on the binding so the render path
        // exercises the .stroke(.white, lineWidth: 2) branch. Body smoke
        // verifies the conditional construction; visual fidelity is the
        // v0.10.1 snapshot harness's job.
        @State var single: LayerID? = LayerID("title")
        _ = OverlayHost(sampleVideo(), selectedLayerID: $single).body
    }

    @Test @MainActor func setBindingMatchesMultipleOverlays() {
        @State var multi: Set<LayerID> = [LayerID("title"), LayerID("sticker-1")]
        _ = OverlayHost(sampleVideo(), selectedLayerIDs: $multi).body
    }
}
