import Foundation
import CoreMedia
import Kadr

/// Payload for ``TimelineView``'s chain-clip reorder callback.
///
/// Replaces the v0.4–v0.9.2 positional-arg shape `(from: Int, to: Int,
/// newClips: [any Clip])` to make field swaps at consumer call sites
/// compile-time impossible. Pre-v0.10 a consumer accidentally swapping
/// `from` and `to` got silent nonsense; v0.10 names every field.
public struct ClipReorderEvent: Sendable {
    /// Original index of the dragged media clip in `video.clips`.
    public let from: Int

    /// Target index after the drop. May equal `from` if the user dragged
    /// without crossing a slot boundary.
    public let to: Int

    /// The full rebuilt `video.clips` array, ready to be passed back into a
    /// fresh ``Kadr/Video``. Transitions automatically travel with their
    /// preceding media clip — consumers don't see a freestanding
    /// ``Kadr/Transition`` mid-reorder.
    public let newClips: [any Clip]

    public init(from: Int, to: Int, newClips: [any Clip]) {
        self.from = from
        self.to = to
        self.newClips = newClips
    }
}

/// Payload for ``TimelineView``'s chain-clip trim callback.
///
/// Replaces the v0.5.1 positional-arg shape `(clipIndex: Int, leadingTrim:
/// CMTime, trailingTrim: CMTime)`.
public struct ClipTrimEvent: Sendable {
    /// Index of the trimmed clip in `video.clips`.
    public let clipIndex: Int

    /// Leading-edge trim delta. Positive = trimmed from the front;
    /// negative = extended forward.
    public let leadingTrim: CMTime

    /// Trailing-edge trim delta. Positive = trimmed from the back;
    /// negative = extended backward.
    public let trailingTrim: CMTime

    public init(clipIndex: Int, leadingTrim: CMTime, trailingTrim: CMTime) {
        self.clipIndex = clipIndex
        self.leadingTrim = leadingTrim
        self.trailingTrim = trailingTrim
    }
}

/// Payload for ``TimelineView``'s Track-lane reorder callback.
///
/// Replaces the v0.7.0 positional-arg shape `(trackIndex: Int, from: Int,
/// to: Int, newClips: [any Clip])`.
public struct TrackReorderEvent: Sendable {
    /// Track-only ordinal identifying which Track the reorder happened
    /// inside (matches `LaneKind.track(index:...)`).
    public let trackIndex: Int

    /// Source position inside the Track's `clips` array.
    public let from: Int

    /// Target position inside the Track's `clips` array. May equal `from`.
    public let to: Int

    /// The full rebuilt `video.clips` array with the modified Track
    /// substituted in place.
    public let newClips: [any Clip]

    public init(trackIndex: Int, from: Int, to: Int, newClips: [any Clip]) {
        self.trackIndex = trackIndex
        self.from = from
        self.to = to
        self.newClips = newClips
    }
}

/// Payload for ``TimelineView``'s Track-lane trim callback.
///
/// Replaces the v0.7.1 positional-arg shape `(trackIndex: Int, clipIndex:
/// Int, leadingTrim: CMTime, trailingTrim: CMTime)`.
public struct TrackTrimEvent: Sendable {
    /// Track-only ordinal identifying which Track the clip lives in.
    public let trackIndex: Int

    /// Index of the trimmed clip inside the Track's `clips` array.
    public let clipIndex: Int

    /// Leading-edge trim delta. Same semantics as ``ClipTrimEvent/leadingTrim``.
    public let leadingTrim: CMTime

    /// Trailing-edge trim delta. Same semantics as ``ClipTrimEvent/trailingTrim``.
    public let trailingTrim: CMTime

    public init(trackIndex: Int, clipIndex: Int, leadingTrim: CMTime, trailingTrim: CMTime) {
        self.trackIndex = trackIndex
        self.clipIndex = clipIndex
        self.leadingTrim = leadingTrim
        self.trailingTrim = trailingTrim
    }
}

/// Payload for ``TimelineView``'s audio-lane trim callback.
///
/// Fired on drag-end of a leading / trailing handle on an audio row.
/// Identifies the row by its position in `video.audioTracks` and surfaces
/// the trim delta relative to the row's pre-drag bounds. Consumers resolve
/// the delta against `AudioTrack.startTime` / `.explicitDuration`
/// themselves — kadr-ui doesn't synchronously load the source asset to
/// know its natural duration, so the surface mirrors ``ClipTrimEvent`` /
/// ``TrackTrimEvent`` (relative deltas, not absolute targets).
///
/// Added in v0.10.2.
public struct AudioTrimEvent: Sendable {
    /// Index into the host `Video`'s top-level `audioTracks` array.
    public let trackIndex: Int

    /// Leading-edge trim delta. Positive = drag inward (later start);
    /// negative = drag outward (earlier start).
    public let leadingTrim: CMTime

    /// Trailing-edge trim delta. Positive = drag outward (later end);
    /// negative = drag inward (earlier end).
    public let trailingTrim: CMTime

    public init(trackIndex: Int, leadingTrim: CMTime, trailingTrim: CMTime) {
        self.trackIndex = trackIndex
        self.leadingTrim = leadingTrim
        self.trailingTrim = trailingTrim
    }
}
