import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// The surface added so a host can drive playback without reverse-engineering
/// this view: a public composition fingerprint, a frame-scale seek threshold,
/// and a loop flag that is actually live.
///
/// Like ``VideoPreviewPlaybackTests``, real playback is not exercisable on a
/// virtualised runner. Everything asserted here is pure — which is precisely
/// why these parts were worth making public: they are the parts a consumer can
/// reason about without a player.
struct VideoPreviewIdentityAndSeekTests {

    private func video(clips: Int, seconds: Double = 2.0) -> Video {
        let img = PlatformImage()
        return Video {
            for _ in 0..<clips { ImageClip(img, duration: seconds) }
        }
    }

    // MARK: - The fingerprint consumers were copying by hand

    @Test func identityIsStableForTheSameComposition() {
        let a = VideoPreview.compositionIdentity(of: video(clips: 2))
        let b = VideoPreview.compositionIdentity(of: video(clips: 2))
        #expect(a == b, "Same shape must produce the same fingerprint, or every render would rebuild the player.")
    }

    @Test func identityChangesWhenClipCountChanges() {
        #expect(VideoPreview.compositionIdentity(of: video(clips: 2))
             != VideoPreview.compositionIdentity(of: video(clips: 3)))
    }

    @Test func identityChangesWhenDurationChanges() {
        #expect(VideoPreview.compositionIdentity(of: video(clips: 2, seconds: 2.0))
             != VideoPreview.compositionIdentity(of: video(clips: 2, seconds: 3.0)))
    }

    @Test func reloadTokenParticipatesInIdentity() {
        let v = video(clips: 2)
        #expect(VideoPreview.compositionIdentity(of: v, reloadToken: "a")
             != VideoPreview.compositionIdentity(of: v, reloadToken: "b"))
        #expect(VideoPreview.compositionIdentity(of: v, reloadToken: nil)
             == VideoPreview.compositionIdentity(of: v))
    }

    @Test func identityExposesTheInputsItIsBuiltFrom() {
        // A consumer that needs to log or diff why a rebuild happened should not
        // have to guess which input moved.
        let id = VideoPreview.compositionIdentity(of: video(clips: 3))
        #expect(id.clipCount == 3)
        #expect(id.overlayCount == 0)
        #expect(id.audioTrackCount == 0)
        #expect(id.durationSeconds > 0)
    }

    // MARK: - Frame-stepping has to clear the seek threshold

    @Test(arguments: [24.0, 25.0, 30.0, 60.0, 120.0])
    func oneFrameIsALargerMoveThanTheSeekThreshold(fps: Double) {
        let oneFrame = 1.0 / fps
        #expect(oneFrame > VideoPreview.seekEpsilon,
                "A single frame at \(fps)fps must register as a deliberate seek. The previous 0.05s threshold swallowed it at every rate up to 20fps, so frame-stepping did nothing.")
    }

    @Test func thresholdIsTighterThanTheValueItReplaced() {
        #expect(VideoPreview.seekEpsilon < 0.05)
        #expect(VideoPreview.seekEpsilon > 0, "Zero would let float noise trigger seeks.")
    }

    // MARK: - The loop flag the observer reads

    @Test func loopBoxReflectsLaterWrites() {
        // Models what the periodic observer does: it holds this box rather than
        // a copy of the flag, so a toggle after the player was built is visible.
        let box = VideoPreview.LoopBox()
        #expect(box.loops == false)
        box.loops = true
        #expect(box.loops == true)
    }

    // MARK: - Opting out of AVKit's transport

    @Test @MainActor func constructsWithPlaybackControlsHidden() {
        _ = VideoPreview(video(clips: 1), showsPlaybackControls: false)
    }

    @Test @MainActor func playbackControlsAreShownByDefault() {
        let preview = VideoPreview(video(clips: 1))
        #expect(preview.showsPlaybackControlsForTesting == true,
                "Default must stay the pre-existing behaviour.")
    }
}
