import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// v0.14 — the playback-control surface on ``VideoPreview``.
///
/// Real playback is not exercisable here: it needs a decodable asset and a
/// running player, and this package's CI runs on virtualised runners that have
/// neither. What these cover is the contract that surrounds it — every
/// combination of the new bindings constructs, defaults leave the pre-0.14
/// behaviour untouched, and the opt-in flags are genuinely opt-in.
///
/// The behaviour that cannot be asserted here (position write-back, loop
/// restart, `isPlaying` clearing at the end) is exercised by the consuming app
/// and by the nightly hardware run.
struct VideoPreviewPlaybackTests {

    private func sampleVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 2.0)
            ImageClip(img, duration: 2.0)
        }
    }

    // MARK: - Defaults are the pre-0.14 shape

    @Test @MainActor func constructsWithNoPlaybackArgumentsAtAll() {
        // The v0.13 call site must still compile and behave: no bindings, no
        // loop, no observer attached.
        _ = VideoPreview(sampleVideo()).body
    }

    @Test @MainActor func loopsDefaultsToFalse() {
        // Looping is a session preference the caller owns. If this ever
        // defaulted true, every existing preview would silently start
        // restarting itself.
        let preview = VideoPreview(sampleVideo())
        #expect(preview.loopsForTesting == false)
    }

    // MARK: - Each binding, alone and together

    @Test @MainActor func constructsWithIsPlayingOnly() {
        var playing = false
        _ = VideoPreview(sampleVideo(), isPlaying: Binding(get: { playing }, set: { playing = $0 })).body
    }

    @Test @MainActor func constructsWithCurrentTimeOnly() {
        var time = CMTime.zero
        _ = VideoPreview(sampleVideo(), currentTime: Binding(get: { time }, set: { time = $0 })).body
    }

    @Test @MainActor func constructsWithBothBindingsAndLooping() {
        var playing = true
        var time = CMTime(seconds: 1, preferredTimescale: 600)
        _ = VideoPreview(
            sampleVideo(),
            isPlaying: Binding(get: { playing }, set: { playing = $0 }),
            currentTime: Binding(get: { time }, set: { time = $0 }),
            loops: true
        ).body
    }

    @Test @MainActor func playbackAndSamplingCoexist() {
        // The transport band and the eyedropper are separate features that will
        // be on the same preview in a consuming editor.
        var playing = false
        _ = VideoPreview(
            sampleVideo(),
            isPlaying: Binding(get: { playing }, set: { playing = $0 }),
            loops: true,
            onSampleColor: { _ in }
        ).body
    }

    @Test @MainActor func loopingIsCarriedOntoTheView() {
        #expect(VideoPreview(sampleVideo(), loops: true).loopsForTesting == true)
    }
}
