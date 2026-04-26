import Testing
import SwiftUI
import Kadr
import KadrUI

/// Smoke tests for `ThumbnailStrip`. Visual / async-load behavior is exercised manually
/// against a sample app and indirectly via Kadr's `PreviewAPITests` (which covers the
/// underlying `Video.thumbnail(at:)`). These tests lock in the public constructor
/// contract so a regression fails to compile rather than at runtime.
struct ThumbnailStripTests {

    @Test @MainActor func constructsWithDefaultCount() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 3.0)
        }
        _ = ThumbnailStrip(video).body
    }

    @Test @MainActor func constructsWithExplicitCount() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 3.0)
        }
        _ = ThumbnailStrip(video, count: 20).body
    }

    @Test @MainActor func constructsWithZeroCount() {
        // count: 0 is a permitted edge case — should not crash on construction.
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 3.0)
        }
        _ = ThumbnailStrip(video, count: 0).body
    }
}
