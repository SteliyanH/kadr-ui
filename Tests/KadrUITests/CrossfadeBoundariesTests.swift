import Testing
import CoreMedia
import Foundation
import Kadr
@testable import KadrUI

/// Pure unit tests for `TimelineView.crossfadeBoundaries(in:)`. The helper detects
/// overlapping `AudioTrack` pairs where at least one carries a non-zero
/// `crossfadeDuration` and returns the midpoint of each overlap region.
struct CrossfadeBoundariesTests {

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func track(
        startSec: Double,
        durationSec: Double,
        crossfade: Double? = nil
    ) -> AudioTrack {
        var t = AudioTrack(url: URL(fileURLWithPath: "/dev/null"))
            .at(time: startSec)
            .duration(cmt(durationSec))
        if let cf = crossfade {
            t = t.crossfade(cmt(cf))
        }
        return t
    }

    private func video(with tracks: [AudioTrack]) -> Video {
        var v = Video { ImageClip(PlatformImage(), duration: 1.0) }
        for t in tracks {
            v = v.audio { t }
        }
        return v
    }

    @Test func returnsEmptyForNoAudioTracks() {
        let v = Video { ImageClip(PlatformImage(), duration: 1.0) }
        #expect(TimelineView.crossfadeBoundaries(in: v).isEmpty)
    }

    @Test func returnsEmptyForSingleAudioTrack() {
        let v = video(with: [track(startSec: 0, durationSec: 5, crossfade: 0.5)])
        #expect(TimelineView.crossfadeBoundaries(in: v).isEmpty)
    }

    @Test func returnsEmptyForNonOverlappingPair() {
        let v = video(with: [
            track(startSec: 0, durationSec: 2, crossfade: 0.5),
            track(startSec: 3, durationSec: 2, crossfade: 0.5),
        ])
        #expect(TimelineView.crossfadeBoundaries(in: v).isEmpty)
    }

    @Test func returnsEmptyWhenOverlapButNoCrossfade() {
        let v = video(with: [
            track(startSec: 0, durationSec: 4),
            track(startSec: 3, durationSec: 4),
        ])
        #expect(TimelineView.crossfadeBoundaries(in: v).isEmpty)
    }

    @Test func emitsMidpointForOverlapWithCrossfade() {
        // a: [0, 4]; b: [3, 7]; overlap [3, 4]; midpoint 3.5
        let v = video(with: [
            track(startSec: 0, durationSec: 4, crossfade: 0.5),
            track(startSec: 3, durationSec: 4, crossfade: 0.5),
        ])
        let bounds = TimelineView.crossfadeBoundaries(in: v)
        #expect(bounds.count == 1)
        #expect(abs(CMTimeGetSeconds(bounds[0]) - 3.5) < 0.0001)
    }

    @Test func emitsMidpointWhenOnlyOneSideHasCrossfade() {
        let v = video(with: [
            track(startSec: 0, durationSec: 4),
            track(startSec: 3, durationSec: 4, crossfade: 0.5),
        ])
        let bounds = TimelineView.crossfadeBoundaries(in: v)
        #expect(bounds.count == 1)
        #expect(abs(CMTimeGetSeconds(bounds[0]) - 3.5) < 0.0001)
    }

    @Test func skipsTracksWithoutExplicitDuration() {
        let raw = AudioTrack(url: URL(fileURLWithPath: "/dev/null")).at(time: 0)
        let v = video(with: [
            raw,
            track(startSec: 1, durationSec: 4, crossfade: 0.5),
        ])
        #expect(TimelineView.crossfadeBoundaries(in: v).isEmpty)
    }

    @Test func handlesMultipleOverlappingPairs() {
        let v = video(with: [
            track(startSec: 0, durationSec: 4, crossfade: 0.5),
            track(startSec: 3, durationSec: 4, crossfade: 0.5),
            track(startSec: 6, durationSec: 4, crossfade: 0.5),
        ])
        let bounds = TimelineView.crossfadeBoundaries(in: v).map { CMTimeGetSeconds($0) }.sorted()
        #expect(bounds.count == 2)
        #expect(abs(bounds[0] - 3.5) < 0.0001)
        #expect(abs(bounds[1] - 6.5) < 0.0001)
    }
}
