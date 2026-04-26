import Testing
import SwiftUI
import Kadr
import KadrUI

/// Smoke tests for the gesture modifiers on `OverlayHost`. Actual gesture firing requires
/// a SwiftUI hosting environment and is exercised manually via the example app — these
/// tests cover the public modifier-chain contract only.
struct OverlayGestureTests {

    private func sampleVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 1.0)
        }
        .overlay(TextOverlay("Hello").id("title"))
        .overlay(ImageOverlay(img).id("logo"))
    }

    @Test @MainActor func onLayerTapReturnsAttachedHost() {
        let host = OverlayHost(sampleVideo())
            .onLayerTap { _ in /* noop */ }
        // Verify the modified host's body still resolves — a regression that breaks the
        // gesture-attaching path fails here at compile or runtime.
        _ = host.body
    }

    @Test @MainActor func onLayerDragOnChangedOnly() {
        let host = OverlayHost(sampleVideo())
            .onLayerDrag(onChanged: { _, _ in })
        _ = host.body
    }

    @Test @MainActor func onLayerDragOnEndedOnly() {
        let host = OverlayHost(sampleVideo())
            .onLayerDrag(onEnded: { _, _ in })
        _ = host.body
    }

    @Test @MainActor func onLayerDragBothPhases() {
        let host = OverlayHost(sampleVideo())
            .onLayerDrag(
                onChanged: { _, _ in },
                onEnded: { _, _ in }
            )
        _ = host.body
    }

    @Test @MainActor func tapAndDragChain() {
        // Both modifiers should compose: returning a fully-modified host with both
        // handlers set, body still resolves.
        let host = OverlayHost(sampleVideo())
            .onLayerTap { _ in }
            .onLayerDrag(onChanged: { _, _ in }, onEnded: { _, _ in })
        _ = host.body
    }

    @Test @MainActor func gesturesIgnoreOverlaysWithoutLayerID() {
        // Overlays without a LayerID don't participate in gestures. Construct a video
        // with an unidentified overlay and confirm the host still renders.
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        .overlay(TextOverlay("anonymous"))   // no .id(...)

        let host = OverlayHost(video)
            .onLayerTap { _ in }
        _ = host.body
    }
}
