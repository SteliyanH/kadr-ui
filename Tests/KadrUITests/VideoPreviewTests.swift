import Testing
import SwiftUI
import Kadr
import KadrUI

/// Smoke tests for `VideoPreview`. SwiftUI views can't be meaningfully unit-tested without
/// a hosting environment (the AVPlayer load side-effect runs in `.task`), so these tests
/// only exercise constructor contracts. Visual / playback behavior is verified by manual
/// runs of the example app and by Kadr's own `PreviewAPITests` covering the underlying
/// `Video.makePlayerItem()`.
struct VideoPreviewTests {

    @Test @MainActor func constructsFromAnyVideo() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        let preview = VideoPreview(video)
        // Verify the view value can be created and has a non-trivial body type.
        // A regression that breaks the public init signature fails here.
        _ = preview.body
    }

    @Test @MainActor func constructsWithFailureCallback() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        let preview = VideoPreview(video) { _ in
            // intentionally empty
        }
        _ = preview.body
    }
}
