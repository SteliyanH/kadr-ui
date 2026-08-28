import Foundation
import CoreMedia
import Kadr

/// Cut a clip in two at a point in time.
///
/// Splitting is the one editing operation every timeline UI needs and no
/// package offered: each consumer rebuilt the same arithmetic, and the same
/// edge cases, against kadr's immutable clip types. This is that arithmetic,
/// pure and tested, with no SwiftUI in it — call it from wherever your editor
/// keeps its state.
///
/// ```swift
/// switch ClipSplitter.split(clips: video.clips, id: selected, at: playhead) {
/// case .success(let clips): rebuild(with: clips)
/// case .failure(let reason): toast(reason.message)
/// }
/// ```
///
/// **What it will not do.** A clip inside a ``Kadr/Track``, a
/// ``Kadr/Transition``, and a clip with a non-1× speed rate are all refused
/// rather than approximated — see ``ClipSplitter/Failure``. Splitting a retimed
/// clip means solving for source time through the speed curve, and getting that
/// subtly wrong produces a cut that looks right and exports wrong.
///
/// Added in v0.19.
public enum ClipSplitter {

    /// Why a split could not be performed.
    public enum Failure: String, Error, Sendable, Equatable, Hashable {
        /// No clip with that id exists in the composition.
        case clipNotFound
        /// The clip is inside a ``Kadr/Track``. Splitting within a track would
        /// change the track's internal timing, which the caller has to decide
        /// about.
        case clipInsideTrack
        /// The clip is a ``Kadr/Transition``, which has no content to cut.
        case notSplittable
        /// The time falls outside the clip, or exactly on one of its edges —
        /// where a split would produce a zero-length half.
        case timeOutOfRange
        /// The clip has a speed rate other than 1×. Composition time and source
        /// time diverge, and guessing the mapping produces a wrong cut.
        case unsupportedSpeedRate

        /// A sentence to show the user.
        public var message: String {
            switch self {
            case .clipNotFound:         return "That clip is no longer in the timeline."
            case .clipInsideTrack:      return "Clips inside a track can't be split."
            case .notSplittable:        return "Transitions can't be split."
            case .timeOutOfRange:       return "Move the playhead inside the clip to split it."
            case .unsupportedSpeedRate: return "Clips with changed speed can't be split yet."
            }
        }
    }

    /// Split the top-level clip identified by `id` at composition time `time`.
    ///
    /// - Returns: the full clip list with the target replaced by its two halves,
    ///   or the reason it could not be done.
    public static func split(
        clips: [any Clip],
        id: ClipID,
        at time: CMTime
    ) -> Result<[any Clip], Failure> {
        guard let location = topLevelLocation(for: id, in: clips) else {
            let nested = clips.contains { contains(id, in: $0) }
            return .failure(nested ? .clipInsideTrack : .clipNotFound)
        }
        let clip = clips[location.index]
        let offset = CMTimeSubtract(time, location.startTime)

        // A split exactly on an edge would make a zero-length half, which is
        // not a cut — it is a no-op that leaves a phantom clip behind.
        guard offset > .zero, offset < clip.duration else {
            return .failure(.timeOutOfRange)
        }

        guard let halves = halves(of: clip, at: offset) else {
            if let video = clip as? VideoClip, video.speedRate != 1.0 {
                return .failure(.unsupportedSpeedRate)
            }
            return .failure(.notSplittable)
        }

        var result = clips
        result.replaceSubrange(location.index...location.index, with: [halves.0, halves.1])
        return .success(result)
    }

    // MARK: - Halves

    static func halves(of clip: any Clip, at offset: CMTime) -> ((any Clip), (any Clip))? {
        switch clip {
        case let video as VideoClip:
            guard video.speedRate == 1.0 else { return nil }
            return splitVideo(video, at: offset)
        case let image as ImageClip:
            return splitImage(image, at: offset)
        case let title as TitleSequence:
            return splitTitle(title, at: offset)
        default:
            return nil
        }
    }

    static func splitVideo(_ video: VideoClip, at offset: CMTime) -> (VideoClip, VideoClip) {
        // The slice of the file this clip plays. Composition time and source
        // time coincide because a non-1× rate was already refused.
        let source = video.trimRange ?? CMTimeRange(start: .zero, duration: video.duration)
        let left = video.trimmed(to: CMTimeRange(start: source.start, duration: offset))
        let right = video
            .trimmed(to: CMTimeRange(
                start: CMTimeAdd(source.start, offset),
                duration: CMTimeSubtract(source.duration, offset)
            ))
            .id(ClipID(UUID().uuidString))
        // `trimmed(to:)` is a whole-value copy, so filters, filter identities,
        // transforms and opacity all travel to both halves untouched.
        return (left, right)
    }

    static func splitImage(_ image: ImageClip, at offset: CMTime) -> (ImageClip, ImageClip) {
        let left = image.duration(offset)
        let right = image
            .duration(CMTimeSubtract(image.duration, offset))
            .id(ClipID(UUID().uuidString))
        return (left, right)
    }

    static func splitTitle(_ title: TitleSequence, at offset: CMTime) -> (TitleSequence, TitleSequence) {
        // TitleSequence has no duration modifier, so each half is rebuilt
        // through the initialiser — which means every other property has to be
        // reapplied by hand. That is exactly the shape of code that loses a
        // field silently, so `reapply` is exhaustive over the type's modifiers
        // and `TitleSplitPreservesEverythingTests` holds it to that.
        func make(_ duration: CMTime, freshID: Bool) -> TitleSequence {
            reapply(
                from: title,
                to: TitleSequence(
                    title.text,
                    duration: duration,
                    style: title.style,
                    background: title.backgroundColor
                ),
                freshID: freshID
            )
        }
        return (make(offset, freshID: false),
                make(CMTimeSubtract(title.duration, offset), freshID: true))
    }

    /// Carry every modifier from `source` onto `target`.
    ///
    /// Animations included: an earlier version of this in the reference app
    /// reapplied only `transform` and `opacity`, so splitting an animated title
    /// silently dropped both keyframe tracks.
    static func reapply(from source: TitleSequence, to target: TitleSequence, freshID: Bool) -> TitleSequence {
        var out = target
        if freshID {
            out = out.id(ClipID(UUID().uuidString))
        } else if let id = source.clipID {
            out = out.id(id)
        }
        if let start = source.startTime { out = out.at(time: start) }
        if let animation = source.transformAnimation {
            out = out.transform(source.transform ?? Transform(), animation: animation)
        } else if let transform = source.transform {
            out = out.transform(transform)
        }
        if let animation = source.opacityAnimation {
            out = out.opacity(source.opacity ?? 1.0, animation: animation)
        } else if let opacity = source.opacity {
            out = out.opacity(opacity)
        }
        return out
    }

    // MARK: - Lookup

    /// Index and composition start time of the top-level clip with `id`.
    public static func topLevelLocation(
        for id: ClipID,
        in clips: [any Clip]
    ) -> (index: Int, startTime: CMTime)? {
        var cursor: CMTime = .zero
        for (index, clip) in clips.enumerated() {
            if clip.clipID == id { return (index, cursor) }
            cursor = CMTimeAdd(cursor, clip.duration)
        }
        return nil
    }

    /// Whether `id` is anywhere in `clip`, including inside a ``Kadr/Track``.
    public static func contains(_ id: ClipID, in clip: any Clip) -> Bool {
        if clip.clipID == id { return true }
        if let track = clip as? Track {
            return track.clips.contains { contains(id, in: $0) }
        }
        return false
    }
}
