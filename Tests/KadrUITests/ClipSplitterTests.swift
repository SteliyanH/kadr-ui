import Testing
import Foundation
import CoreMedia
import Kadr
@testable import KadrUI

/// Tests for `ClipSplitter`.
struct ClipSplitterTests {

    private func video(_ id: String, seconds: Double) -> VideoClip {
        VideoClip(url: URL(fileURLWithPath: "/tmp/\(id).mov"))
            .trimmed(to: 0...seconds)
            .id(ClipID(id))
    }

    private func at(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    /// `Result`'s success type here is `[any Clip]`, which cannot be `Equatable`,
    /// so the whole `Result` isn't either. Compare the failure instead.
    private func failure(
        _ result: Result<[any Clip], ClipSplitter.Failure>
    ) -> ClipSplitter.Failure? {
        if case let .failure(reason) = result { return reason }
        return nil
    }

    // MARK: - Success

    @Test("A clip splits into two halves whose durations sum to the original")
    func durationsAreConserved() throws {
        let clips: [any Clip] = [video("a", seconds: 10)]
        let result = try ClipSplitter.split(clips: clips, id: ClipID("a"), at: at(4)).get()
        #expect(result.count == 2)
        #expect(result[0].duration.seconds == 4)
        #expect(result[1].duration.seconds == 6)
        #expect(CMTimeAdd(result[0].duration, result[1].duration) == clips[0].duration)
    }

    @Test("The split point is measured in composition time, not clip time")
    func splitPointIsCompositionRelative() throws {
        let clips: [any Clip] = [video("a", seconds: 5), video("b", seconds: 10)]
        // 8s into the composition is 3s into the second clip.
        let result = try ClipSplitter.split(clips: clips, id: ClipID("b"), at: at(8)).get()
        #expect(result.count == 3)
        #expect(result[1].duration.seconds == 3)
        #expect(result[2].duration.seconds == 7)
    }

    @Test("The right half reads from where the left half stopped")
    func sourceRangesAreContiguous() throws {
        let clip = VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov"))
            .trimmed(to: 2...12)
            .id(ClipID("a"))
        let result = try ClipSplitter.split(clips: [clip], id: ClipID("a"), at: at(4)).get()
        let left = result[0] as! VideoClip
        let right = result[1] as! VideoClip
        #expect(left.trimRange?.start.seconds == 2)
        #expect(left.trimRange?.duration.seconds == 4)
        #expect(right.trimRange?.start.seconds == 6)   // 2 + 4
        #expect(right.trimRange?.duration.seconds == 6)
    }

    @Test("The left half keeps the original id; the right half gets a fresh one")
    func identityIsResolved() throws {
        let result = try ClipSplitter.split(clips: [video("a", seconds: 10)], id: ClipID("a"), at: at(5)).get()
        #expect(result[0].clipID == ClipID("a"))
        #expect(result[1].clipID != ClipID("a"))
        #expect(result[1].clipID != nil)
    }

    @Test("Filters and their identities survive into both halves")
    func filtersSurvive() throws {
        let clip = video("a", seconds: 10)
            .filter(.sepia(intensity: 0.4))
            .filter(.vignette(intensity: 0.8))
        let originalIDs = clip.filterIDs
        let result = try ClipSplitter.split(clips: [clip], id: ClipID("a"), at: at(5)).get()
        for half in result {
            let half = half as! VideoClip
            #expect(half.filters.count == 2)
            #expect(half.filterIDs == originalIDs)
        }
    }

    @Test("An image clip splits by duration")
    func imageClipSplits() throws {
        let clip = ImageClip(PlatformImage(), duration: 6.0).id(ClipID("img"))
        let result = try ClipSplitter.split(clips: [clip], id: ClipID("img"), at: at(2)).get()
        #expect(result[0].duration.seconds == 2)
        #expect(result[1].duration.seconds == 4)
    }

    @Test("Splitting a title keeps its text, style and background")
    func titleContentSurvives() throws {
        let style = TextStyle(fontSize: 42, color: .white, weight: .bold)
        let title = TitleSequence("Chapter", duration: 8.0, style: style, background: .black)
            .id(ClipID("t"))
        let result = try ClipSplitter.split(clips: [title], id: ClipID("t"), at: at(3)).get()
        for half in result {
            let half = half as! TitleSequence
            #expect(half.text == "Chapter")
            #expect(half.style.fontSize == 42)
        }
        #expect(result[0].duration.seconds == 3)
        #expect(result[1].duration.seconds == 5)
    }

    @Test("Splitting an animated title keeps both keyframe tracks")
    func titleAnimationsSurvive() throws {
        // The reference app's version of this reapplied only `transform` and
        // `opacity`, so splitting an animated title silently dropped both
        // animations. This is that regression, pinned.
        let title = TitleSequence("Animated", duration: 8.0)
            .id(ClipID("t"))
            .transform(Transform(scale: 1.0), animation: .keyframes([
                .at(0.0, value: Transform(scale: 1.0)),
                .at(2.0, value: Transform(scale: 1.4)),
            ]))
            .opacity(1.0, animation: .keyframes([
                .at(0.0, value: 0.0), .at(1.0, value: 1.0),
            ]))
        let result = try ClipSplitter.split(clips: [title], id: ClipID("t"), at: at(4)).get()
        for half in result {
            let half = half as! TitleSequence
            #expect(half.transformAnimation != nil, "transform animation was dropped by the split")
            #expect(half.opacityAnimation != nil, "opacity animation was dropped by the split")
        }
    }

    @Test("A title's start time survives the split")
    func titleStartTimeSurvives() throws {
        let title = TitleSequence("T", duration: 6.0).id(ClipID("t")).at(time: 1.5)
        let result = try ClipSplitter.split(clips: [title], id: ClipID("t"), at: at(3)).get()
        #expect((result[0] as! TitleSequence).startTime?.seconds == 1.5)
    }

    // MARK: - Refusals

    @Test("Splitting exactly on an edge is refused rather than making a zero-length half")
    func edgeSplitsAreRefused() {
        let clips: [any Clip] = [video("a", seconds: 10)]
        for time in [at(0), at(10)] {
            #expect(failure(ClipSplitter.split(clips: clips, id: ClipID("a"), at: time)) == .timeOutOfRange)
        }
    }

    @Test("A time outside the clip is refused")
    func outOfRangeIsRefused() {
        let clips: [any Clip] = [video("a", seconds: 10)]
        #expect(failure(ClipSplitter.split(clips: clips, id: ClipID("a"), at: at(11))) == .timeOutOfRange)
    }

    @Test("An unknown id reports notFound, not a crash")
    func unknownIDIsRefused() {
        let clips: [any Clip] = [video("a", seconds: 10)]
        #expect(failure(ClipSplitter.split(clips: clips, id: ClipID("nope"), at: at(5))) == .clipNotFound)
    }

    @Test("A clip inside a track is distinguished from a missing one")
    func nestedClipIsDistinguished() {
        let clips: [any Clip] = [
            Track { VideoClip(url: URL(fileURLWithPath: "/tmp/i.mov")).trimmed(to: 0...5).id(ClipID("inner")) }
        ]
        #expect(failure(ClipSplitter.split(clips: clips, id: ClipID("inner"), at: at(2))) == .clipInsideTrack)
    }

    @Test("A retimed clip is refused rather than cut in the wrong place")
    func retimedClipIsRefused() {
        let clip = video("a", seconds: 10).speed(.flat(2.0))
        #expect(failure(ClipSplitter.split(clips: [clip], id: ClipID("a"), at: at(2))) == .unsupportedSpeedRate)
    }

    @Test("Every failure carries a sentence worth showing someone")
    func failuresAreLegible() {
        for failure in [ClipSplitter.Failure.clipNotFound, .clipInsideTrack, .notSplittable,
                        .timeOutOfRange, .unsupportedSpeedRate] {
            #expect(!failure.message.isEmpty)
            #expect(failure.message.hasSuffix("."))
        }
    }

    // MARK: - Lookup

    @Test("topLevelLocation reports the running composition offset")
    func locationReportsOffset() {
        let clips: [any Clip] = [video("a", seconds: 4), video("b", seconds: 3), video("c", seconds: 5)]
        #expect(ClipSplitter.topLevelLocation(for: ClipID("c"), in: clips)?.startTime.seconds == 7)
        #expect(ClipSplitter.topLevelLocation(for: ClipID("c"), in: clips)?.index == 2)
    }

    @Test("contains finds a clip nested inside a track")
    func containsIsRecursive() {
        let track = Track { ImageClip(PlatformImage(), duration: 1.0).id(ClipID("deep")) }
        #expect(ClipSplitter.contains(ClipID("deep"), in: track))
        #expect(!ClipSplitter.contains(ClipID("absent"), in: track))
    }
}
