import Testing
import SwiftUI
import CoreMedia
import Kadr
import KadrUI

/// Smoke tests for `TimelineView`. SwiftUI rendering / async metadata loading is
/// exercised manually via the example app — these tests cover the public constructor
/// contract.
struct TimelineViewTests {

    private func sampleVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 2.0)
            Kadr.Transition.dissolve(duration: 0.5)
            ImageClip(img, duration: 3.0)
        }
        .audio(url: URL(fileURLWithPath: "/tmp/music.m4a"))
    }

    @Test @MainActor func constructsWithoutPlayhead() {
        _ = TimelineView(sampleVideo()).body
    }

    @Test @MainActor func constructsWithPlayhead() {
        @State var t = CMTime(seconds: 1.0, preferredTimescale: 600)
        _ = TimelineView(sampleVideo(), currentTime: $t).body
    }

    @Test @MainActor func constructsForVideoWithoutAudioTracks() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0)
        }
        _ = TimelineView(video).body
    }

    // MARK: - Selection

    @Test @MainActor func constructsWithSelectionBinding() {
        @State var selected: ClipID? = nil
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0).id("intro")
            ImageClip(img, duration: 2.0).id("body")
        }
        _ = TimelineView(video, selectedClipID: $selected).body
    }

    @Test @MainActor func constructsWithBothPlayheadAndSelection() {
        @State var time = CMTime(seconds: 1.0, preferredTimescale: 600)
        @State var selected: ClipID? = "body"
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0).id("intro")
            ImageClip(img, duration: 2.0).id("body")
        }
        _ = TimelineView(video, currentTime: $time, selectedClipID: $selected).body
    }

    @Test @MainActor func constructsWithMixedIdentifiedAndUnidentifiedClips() {
        // Selection should still work when only some clips have IDs. Unidentified
        // clips and Transitions don't participate in tap-to-select; they should
        // render normally with no crash.
        @State var selected: ClipID? = nil
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 1.0).id("intro")
            Kadr.Transition.dissolve(duration: 0.5)
            ImageClip(img, duration: 2.0)   // no .id(...)
        }
        _ = TimelineView(video, selectedClipID: $selected).body
    }
}
