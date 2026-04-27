# KadrUI — Design Document

## v0.5 — Multi-Lane Timeline

KadrUI catches up to Kadr 0.6's multi-track DSL by extending `TimelineView` to render parallel content as stacked lanes. Fully additive: every chain-only composition continues to render as a single lane, pixel-identical to v0.4.x.

### Problem

Kadr 0.6 introduced three shapes of parallel content:

```swift
Video {
    VideoClip(url: main).trimmed(to: 0...10)              // implicit chain
    VideoClip(url: pip).trimmed(to: 0...3).at(time: 2.0)  // free-floater
    Track(at: 4.0) {                                       // grouped sub-timeline
        VideoClip(url: a).trimmed(to: 0...2)
        Transition.dissolve(duration: 0.5)
        VideoClip(url: b).trimmed(to: 0...2)
    }
}
```

KadrUI 0.4.x's `TimelineView` only renders the implicit chain. Free-floaters and Track blocks are silently dropped from the visual, so a v0.6 composition mis-represents itself in the timeline UI. v0.5 fixes that.

### Scope lock

In scope:
- Lane-aware rendering — implicit chain on lane 0, each `Track {}` as a parallel lane, free-floaters greedy-packed onto their own lane(s)
- Optional audio lanes (one per `Video.audioTracks`, simple colored blocks)
- Existing edit gestures preserved on lane 0 (reorder, trim, scrub, selection)
- Selection (`selectedClipID`) honors `ClipID` on any lane
- Pure layout helpers (`assignLanes`, `packFreeFloaters`) with full unit-test coverage

Out of scope (deferred to v0.5.x or later):
- Cross-lane drag (move clip from chain into a Track, or between Tracks)
- Editing inside Tracks (reorder/trim within a `Track {}` block)
- Audio waveform rendering
- Zoom + horizontal scroll
- Nested-Track expanded visualization (rendered flat as a single block — matches engine pre-render)
- Visual representation of `MultiInputCompositor` (no useful visual; it's a render-time concept)

### API examples

```swift
import SwiftUI
import KadrUI
import Kadr

// 1. Chain-only — identical to v0.4.x. Single lane.
TimelineView(video, currentTime: $time, selectedClipID: $selected)

// 2. Multi-track — stacks lanes automatically. No new params required.
TimelineView(video, currentTime: $time, selectedClipID: $selected)

// 3. Multi-track with audio lanes hidden + lane labels visible.
TimelineView(
    video,
    currentTime: $time,
    selectedClipID: $selected,
    showAudioLanes: false,
    showLaneLabels: true
)

// 4. Edit gestures still apply to the implicit chain on lane 0.
TimelineView(
    video,
    currentTime: $time,
    onReorder: { newOrder in /* re-emit chain */ },
    onTrim: { id, range in /* update clip */ }
)
```

### Key decisions

| Decision | Choice | Why |
|---|---|---|
| API shape | Extend `TimelineView`; no new component | Kadr 0.6 uses one DSL for single + multi-track. KadrUI mirrors that. Chain-only callers see identical output; new behavior only kicks in when the `Video` actually has Tracks or `.at(time:)` clips. Source-compatible. |
| Lane order | Lane 0 = implicit chain; then Tracks in declaration order; then free-floater lanes; then audio lanes | Matches the user's mental model — the chain is the "spine," parallel content rides above it, audio is a separate concern visually grouped at the bottom. |
| Free-floater packing | Greedy interval-pack into the smallest set of non-overlapping lanes | Avoids one-lane-per-floater explosion when many PiPs don't temporally collide. Tracks stay one-lane-each because they're a deliberate authorial grouping. |
| Nested Tracks | Render as a single flat block on the outer lane | Matches Kadr 0.6's engine, which pre-renders nested Tracks to a temp file. Showing nested lanes would mis-represent what plays back. Expanded visualization can land later. |
| Edit gestures | Preserved on lane 0 only | Reorder/trim semantics inside Tracks need product decisions (do you reorder among the Track's clips, or move the Track's `startTime`?). Lane-0-only keeps v0.5.0 small and ships the read-only multi-lane win first. |
| Audio lanes | One per `Video.audioTracks`, no waveform | `Video.audioTracks` is already public (Kadr 0.4). Colored blocks with label match TimelineView's existing visual vocabulary. Waveforms are additive polish for v0.5.1+. |
| Total composition duration | `max(implicit chain end, max(track end), max(floater end))` | Single source of truth for the time axis; matches what the export pipeline produces. |
| Lane height | Configurable param with sensible default | Apps will want to scale the timeline to fit different screens. Default chosen to match v0.4.x clip block height for chain-only call sites. |

### Public surface sketch

```swift
extension TimelineView {
    /// New init signature — additive params have defaults so v0.4.x call sites compile unchanged.
    public init(
        _ video: Video,
        currentTime: Binding<CMTime>? = nil,
        selectedClipID: Binding<ClipID?>? = nil,
        showAudioLanes: Bool = true,
        showLaneLabels: Bool = false,
        laneHeight: CGFloat = 60,
        laneSpacing: CGFloat = 4,
        onReorder: (([ClipID]) -> Void)? = nil,
        onTrim: ((ClipID, ClosedRange<CMTime>) -> Void)? = nil
    )
}

/// Pure types and helpers — package-internal until tier 2 wires them up.
extension TimelineView {

    enum LaneKind: Sendable, Equatable {
        case implicitChain
        case track(index: Int, startTime: CMTime, label: String?)
        case freeFloaters(packIndex: Int)
        case audio(index: Int, label: String?)
    }

    struct LaneItem: Sendable, Equatable {
        let clipID: ClipID?
        let startTime: CMTime
        let duration: CMTime
        let kind: ItemKind
    }

    enum ItemKind: Sendable, Equatable {
        case video
        case image
        case title
        case transition
        case audio
    }

    /// Pure: maps a `Video` into ordered lanes ready to render.
    static func assignLanes(
        for video: Video,
        includeAudio: Bool
    ) -> [(LaneKind, [LaneItem])]

    /// Pure: greedy interval-packs floaters into the minimum number of non-overlapping lanes.
    static func packFreeFloaters(_ floaters: [LaneItem]) -> [[LaneItem]]
}
```

### Lane assignment algorithm

```
Input: Video v
Output: [(LaneKind, [LaneItem])]

1. Build implicitChainLane:
   - Walk v.clips in declaration order
   - Skip clips with non-nil startTime (those are free-floaters)
   - Skip Track blocks (those become their own lanes)
   - Sequential start times from t=0, accumulating duration
   - Append as (LaneKind.implicitChain, items)

2. Build trackLanes:
   - For each Track block in v.clips (in declaration order, indexed):
     - items = walk track.clips sequentially anchored at track.startTime
     - Append as (LaneKind.track(index, startTime, label: nil), items)

3. Build freeFloaterLanes:
   - floaters = v.clips filter { $0.startTime != nil && !($0 is Track) }
   - Greedy-pack via packFreeFloaters into N lanes
   - For each pack i, append (LaneKind.freeFloaters(packIndex: i), items)

4. Build audioLanes (if includeAudio):
   - For each AudioTrack in v.audioTracks (indexed):
     - Append as (LaneKind.audio(index, label: url.lastPathComponent), [single item])

Return concatenated.
```

`packFreeFloaters` uses the standard greedy algorithm: sort floaters by `startTime`, place each on the first lane whose last item ends before this floater starts, else open a new lane.

### Migration & compatibility

- KadrUI 0.5.0 requires Kadr ≥ 0.6.0 (uses `Track`, `Clip.startTime`)
- v0.4.x call sites: source-compatible. All existing init params keep their meaning. New params default to "preserve v0.4.x behavior" where applicable
- Visual output for chain-only compositions: pixel-identical to v0.4.x (single lane fallback short-circuits the multi-lane stack)
- README compatibility table: add `0.5.0 | ≥ 0.6.0`

### Tier breakdown

Mirrors Kadr's RFC-then-tiers staging.

- **Tier 0 — RFC** *(this PR)*. Design doc only. No code.
- **Tier 1 — Surface + pure helpers**. `LaneKind`, `LaneItem`, `ItemKind`, `assignLanes`, `packFreeFloaters` as package-internal pure functions. Full unit test coverage for the lane assignment algorithm + edge cases (empty Video, chain-only, only floaters, only Tracks, mixed, overlapping floaters needing 2+ lanes, audio inclusion). Bump Kadr dep floor to 0.6.0. No render changes — `TimelineView.body` still uses the v0.4.x single-lane code path.
- **Tier 2 — Multi-lane render**. Hook helpers into `TimelineView.body`. Stack lanes vertically with `laneSpacing`. Lane 0 keeps existing edit gestures (reorder, trim). Other lanes render read-only. Playhead spans all lanes. Selection (`selectedClipID`) hits any lane. Visual regression test: chain-only Video produces a single lane indistinguishable from v0.4.x.
- **Tier 3 — Audio lanes**. Wire `showAudioLanes` to render one block per `AudioTrack`. Simple colored block + label. Selection: opt-out (audio tracks have no `ClipID`).
- **Tier 4 — Polish + docs**. Lane labels (`showLaneLabels`), DocC catalog updates, `Examples/SimpleViewer` gets a v0.6 multi-track sample, README compatibility table, CHANGELOG entry.
- **Release** — `develop → main` PR, tag `v0.5.0`, GitHub Release.

### Test strategy

Pure helpers carry the weight, same pattern as the existing `TimelineViewTests` (56 of the 67 tests are static-helper unit tests). Targets:

- `assignLanes`: 8+ cases (empty, chain-only, single-floater, multi-floater overlapping/non-overlapping, single-Track, multi-Track, mixed, audio-inclusion toggle)
- `packFreeFloaters`: 6+ cases (empty, single, two non-overlapping → 1 lane, two overlapping → 2 lanes, three with mixed overlap, edge-touching ranges)
- One integration test that builds a v0.6 multi-track `Video` and asserts lane count + item counts via `assignLanes`
- All existing 67 tests keep passing

### Open questions (track in PRs, not blocking RFC merge)

- **Default for `showAudioLanes`** — true (show by default, callers opt out) is friendlier for new users; false (opt in) keeps the visual minimal. Currently leaning **true**, can revisit in tier 3.
- **Lane label text for Tracks** — `Track` doesn't carry a name in Kadr 0.6. Either generate `"Track 1"`, `"Track 2"`, … or extend Kadr to add an optional `Track(name:)`. v0.5.0 ships generated names; the Kadr-side change is a separate RFC if it's worth doing.
- **Lane reordering** — should the user be able to drag lanes vertically to change z-order? Kadr 0.6's z-order is fixed by declaration order, so this would require Kadr DSL changes too. Defer until requested.
