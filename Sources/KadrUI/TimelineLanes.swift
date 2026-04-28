import Foundation
import CoreMedia
import Kadr

// MARK: - Lane types
//
// Package-internal in v0.5.0 tier 1. Tier 2 will hook these into `TimelineView.body`.
// Kept as plain value types with `Equatable` so the assignment algorithm stays
// unit-testable as a pure function.

/// One row of the timeline. Either a kind of clip lane or an audio lane.
enum LaneKind: Sendable, Equatable {
    /// The implicit chain — clips declared at the top level without `.at(time:)`.
    case implicitChain
    /// A `Track {}` block. `index` is the Track's declaration order among Tracks
    /// (0-based). `startTime` is the Track's anchor on the composition timeline.
    case track(index: Int, startTime: CMTime, label: String?)
    /// A row of greedy-packed free-floater clips — those declared at the top level
    /// with `.at(time:)`. `packIndex` is the row's position when more than one row
    /// is needed to avoid temporal overlap.
    case freeFloaters(packIndex: Int)
    /// One row per `Video.audioTracks` entry. `index` is its position in that array.
    case audio(index: Int, label: String?)
}

/// A single block on a timeline lane.
struct LaneItem: Sendable, Equatable {
    let clipID: ClipID?
    let startTime: CMTime
    let duration: CMTime
    let kind: ItemKind
}

/// Visual classification used by the renderer to pick a thumb / color / icon.
enum ItemKind: Sendable, Equatable {
    case video
    case image
    case title
    case transition
    case audio
}

// MARK: - Public-to-package helpers

extension TimelineView {

    /// Maps a `Video` into ordered lanes ready to render. Pure and synchronous —
    /// uses each clip's reported `duration` even if that's zero (e.g. an untrimmed
    /// `VideoClip` whose asset hasn't been loaded). The renderer is responsible for
    /// deferring layout until durations resolve, the same as v0.4.x today.
    ///
    /// Order of returned lanes:
    /// 1. Implicit chain (always emitted, even when empty)
    /// 2. Tracks in declaration order
    /// 3. Free-floater rows (greedy-packed)
    /// 4. Audio lanes (when `includeAudio == true`)
    nonisolated static func assignLanes(
        for video: Video,
        includeAudio: Bool
    ) -> [(LaneKind, [LaneItem])] {
        var lanes: [(LaneKind, [LaneItem])] = []

        // 1. Implicit chain.
        let chainItems = walkChain(video.clips)
        lanes.append((.implicitChain, chainItems))

        // 2. Tracks (in declaration order, indexed only among Tracks).
        var trackIndex = 0
        for clip in video.clips {
            guard let track = clip as? Track else { continue }
            let start = track.startTime ?? .zero
            let items = walkTrack(track, anchoredAt: start)
            lanes.append((.track(index: trackIndex, startTime: start, label: nil), items))
            trackIndex += 1
        }

        // 3. Free-floater greedy pack.
        let floaters = video.clips.compactMap { clip -> LaneItem? in
            if clip is Track { return nil }
            guard let start = clip.startTime else { return nil }
            guard let kind = classify(clip) else { return nil }
            return LaneItem(
                clipID: clip.clipID,
                startTime: start,
                duration: clip.duration,
                kind: kind
            )
        }
        let packed = packFreeFloaters(floaters)
        for (i, row) in packed.enumerated() {
            lanes.append((.freeFloaters(packIndex: i), row))
        }

        // 4. Audio lanes.
        if includeAudio {
            for (i, audio) in video.audioTracks.enumerated() {
                // AudioTrack has no per-track duration in Kadr 0.6 — it plays for
                // the composition's duration. Use that as the lane block's width.
                let item = LaneItem(
                    clipID: nil,
                    startTime: .zero,
                    duration: video.duration,
                    kind: .audio
                )
                lanes.append((.audio(index: i, label: audio.url.lastPathComponent), [item]))
            }
        }

        return lanes
    }

    /// Greedy interval-packs `floaters` into the minimum number of non-overlapping
    /// rows. Sort by start time, place each on the first row whose last item ends
    /// at or before this floater's start; else open a new row. Stable for floaters
    /// with identical start times (declaration order is preserved within a row).
    /// Pure: original-array indices of clips that participate in the implicit chain.
    /// Excludes Tracks and clips with a non-`nil` `startTime`. Returned in declaration
    /// order. In a chain-only `Video`, returns every index in `video.clips`.
    nonisolated static func chainIndices(in clips: [any Clip]) -> [Int] {
        var out: [Int] = []
        for i in clips.indices {
            let clip = clips[i]
            if clip is Track { continue }
            if clip.startTime != nil { continue }
            out.append(i)
        }
        return out
    }

    /// Pure: reorder only the implicit-chain clips, preserving the original positions
    /// of Tracks and free-floaters in the full array. `from` and `to` are positions
    /// **within the chain** (0-based among chain items). Returns the new full-array
    /// `clips` plus the new chain-position the source landed at — `nil` for no-op
    /// moves (drop-on-self group).
    nonisolated static func applyChainReorder(
        clips: [any Clip],
        from chainSource: Int,
        to chainTarget: Int
    ) -> (newClips: [any Clip], chainTargetIndex: Int)? {
        let indices = chainIndices(in: clips)
        guard indices.indices.contains(chainSource) else { return nil }

        // Extract chain in declaration order, run the existing chain-aware reorder,
        // then merge the new chain back into the full clips array at the same slots.
        let chain = indices.map { clips[$0] }
        guard let result = applyReorder(clips: chain, from: chainSource, to: chainTarget) else {
            return nil
        }
        var merged = clips
        for (chainPos, originalIdx) in indices.enumerated() {
            // Bounds-safe — the chain length is unchanged by applyReorder (transitions
            // travel with their preceding media clip; total count stays equal).
            if chainPos < result.newClips.count {
                merged[originalIdx] = result.newClips[chainPos]
            }
        }
        return (merged, result.targetIndex)
    }

    nonisolated static func packFreeFloaters(_ floaters: [LaneItem]) -> [[LaneItem]] {
        let sorted = floaters.sorted { a, b in
            CMTimeCompare(a.startTime, b.startTime) < 0
        }
        var rows: [[LaneItem]] = []
        var rowEnds: [CMTime] = []

        for item in sorted {
            let itemStart = item.startTime
            let itemEnd = CMTimeAdd(itemStart, item.duration)
            var placed = false
            for i in rowEnds.indices {
                if CMTimeCompare(rowEnds[i], itemStart) <= 0 {
                    rows[i].append(item)
                    rowEnds[i] = itemEnd
                    placed = true
                    break
                }
            }
            if !placed {
                rows.append([item])
                rowEnds.append(itemEnd)
            }
        }
        return rows
    }

    // MARK: - Internal walkers

    /// Walks the implicit chain: top-level clips without `startTime` and not Tracks.
    /// Time accumulates from zero. Transitions stay in the lane (their position is
    /// the running cursor); they don't advance the cursor — same model the engine
    /// uses for the chain.
    nonisolated private static func walkChain(_ clips: [any Clip]) -> [LaneItem] {
        var cursor = CMTime.zero
        var out: [LaneItem] = []
        for clip in clips {
            if clip is Track { continue }
            if clip.startTime != nil { continue }
            guard let kind = classify(clip) else { continue }
            let item = LaneItem(
                clipID: clip.clipID,
                startTime: cursor,
                duration: clip.duration,
                kind: kind
            )
            out.append(item)
            if kind != .transition {
                cursor = CMTimeAdd(cursor, clip.duration)
            }
        }
        return out
    }

    /// Walks a Track's inner clips, anchored at `start`. Inside a Track, clips
    /// chain sequentially — the engine handles internal transitions via the same
    /// mechanism as the implicit chain.
    nonisolated private static func walkTrack(_ track: Track, anchoredAt start: CMTime) -> [LaneItem] {
        var cursor = start
        var out: [LaneItem] = []
        for clip in track.clips {
            guard let kind = classify(clip) else { continue }
            let item = LaneItem(
                clipID: clip.clipID,
                startTime: cursor,
                duration: clip.duration,
                kind: kind
            )
            out.append(item)
            if kind != .transition {
                cursor = CMTimeAdd(cursor, clip.duration)
            }
        }
        return out
    }

    /// Maps a Kadr `Clip` to a visual `ItemKind`. Returns `nil` for unknown clip
    /// types (defensive — a future Kadr release could add a new `Clip` conformer
    /// the timeline doesn't yet know how to render).
    nonisolated private static func classify(_ clip: any Clip) -> ItemKind? {
        if clip is Transition { return .transition }
        if clip is VideoClip { return .video }
        if clip is ImageClip { return .image }
        if clip is TitleSequence { return .title }
        return nil
    }
}
