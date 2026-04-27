import Testing
import SwiftUI
import Kadr
import KadrUI

/// Smoke tests for `OverlayHost`. SwiftUI `body` exercise locks in the public
/// constructor contract — visual rendering is verified manually via the example app.
struct OverlayHostTests {

    private func sampleVideo(withOverlays: Bool) -> Video {
        let img = PlatformImage()
        var v = Video {
            ImageClip(img, duration: 1.0)
        }
        if withOverlays {
            v = v
                .overlay(TextOverlay("Hello").id("title"))
                .overlay(ImageOverlay(img).id("logo"))
        }
        return v
    }

    @Test @MainActor func constructsWithoutOverlays() {
        _ = OverlayHost(sampleVideo(withOverlays: false)).body
    }

    @Test @MainActor func constructsWithOverlays() {
        _ = OverlayHost(sampleVideo(withOverlays: true)).body
    }

    @Test @MainActor func constructsWithContentModeAndCurrentTime() {
        let video = sampleVideo(withOverlays: true)
        _ = OverlayHost(video, contentMode: .fit).body
        _ = OverlayHost(video, contentMode: .fill).body
        _ = OverlayHost(video, contentMode: .stretch).body
        _ = OverlayHost(video, currentTime: .zero).body
        _ = OverlayHost(video, contentMode: .fit, currentTime: .zero).body
    }

    @Test @MainActor func constructsWithCustomRenderer() {
        let video = sampleVideo(withOverlays: true)
        let host = OverlayHost(video) { overlay in
            // Custom renderer that returns a coloured rect for text overlays only,
            // falls through to default for everything else.
            if overlay is TextOverlay {
                return AnyView(Color.red)
            }
            return nil
        }
        _ = host.body
    }
}
