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

## v0.6 — Editor primitives

Depends on **kadr v0.8.0+** (per-clip Transform, keyframe `Animation<T>`, animated `TextOverlay`, audio cross-fades). Adds the SwiftUI surfaces that turn `TimelineView` into a real editor — tap a clip and edit its properties, animate them with keyframes, preview animated text faithfully, see audio cross-fades on the timeline. Pure additive; every v0.5.x call site continues to compile and renders identically.

### Scope lock

In scope:
- **`InspectorPanel(video:selectedClipID:onTransform:onOpacity:onFilterIntensity:)`** — tap a clip on the timeline, slide-up panel with sliders for the v0.8 surface (Transform fields, opacity, animatable filter intensity). Callback shape mirrors `TimelineView.onReorder` / `onTrim` — consumer rebuilds the `Video`.
- **`KeyframeEditor(video:selectedClipID:currentTime:on…)`** — per-property tracks below `TimelineView`. Tap to add a keyframe at the current playhead, long-press to remove, drag to retime. One row per animatable property of the selected clip (Transform / Opacity / Filter[i]).
- **Animated text preview in `OverlayHost`** — when a `TextOverlay` carries `textAnimation`, the SwiftUI bridge view runs the matching `[CAAnimation]` so preview matches export. Static text continues to use the existing SwiftUI `Text` fast path.
- **TimelineView audio cross-fade glyphs** — small markers on the audio lane where adjacent `AudioTrack`s overlap with `crossfadeDuration` set. Visual-only; no gestures.

Out of scope (deferred to v0.6.x or later):
- Cross-lane drag (move a clip from chain → Track or between Tracks)
- Editing inside `Track {}` blocks (reorder/trim within a Track)
- Animated overlay layout preview (`positionAnimation` / `sizeAnimation` previewed in the player; defer until v0.6.x — engine bakes them into export already)
- Custom keyframe-marker styling (fixed white circles in v0.6.0)
- Snap-to-frame-rate when retiming keyframes

### API examples

```swift
// 1. Inspector panel below the timeline.
struct EditorScreen: View {
    @State var clips: [any Clip]
    @State var selectedClipID: ClipID?
    @State var playheadTime: CMTime = .zero

    var video: Video {
        Video { for clip in clips { clip } }
    }

    var body: some View {
        VStack {
            VideoPreview(video)
            TimelineView(video, currentTime: $playheadTime, selectedClipID: $selectedClipID)
            KeyframeEditor(
                video,
                selectedClipID: $selectedClipID,
                currentTime: $playheadTime,
                onAdd: { id, prop, time in addKeyframe(id, prop, time) },
                onRemove: { id, prop, time in removeKeyframe(id, prop, time) },
                onRetime: { id, prop, oldTime, newTime in retimeKeyframe(id, prop, oldTime, newTime) }
            )
            InspectorPanel(
                video,
                selectedClipID: $selectedClipID,
                onTransform: { id, transform in applyTransform(id, transform) },
                onOpacity: { id, opacity in applyOpacity(id, opacity) },
                onFilterIntensity: { id, filterIndex, intensity in applyFilterIntensity(id, filterIndex, intensity) }
            )
        }
    }
}
```

### Key decisions

| Decision | Choice | Why |
|---|---|---|
| API shape | Property-callback pattern (one closure per editable property) | Matches the existing `TimelineView.onReorder` / `onTrim` shape. Kadr's `Video` is immutable; consumers rebuild via the callbacks. Keeps the editor stateless from kadr-ui's perspective. |
| Inspector binding model | `selectedClipID: Binding<ClipID?>` + per-property `on…` callbacks | Selection state is consumer-owned (matches TimelineView). Property edits flow through callbacks the consumer applies to its `[any Clip]` array. No `@Binding<Clip>` because Kadr clip types aren't a mutable target — they're value-type rebuild-on-edit. |
| Keyframe identification | `KeyframeProperty` enum: `.transform` / `.opacity` / `.filter(index: Int)` | Each animatable property gets its own keyframe-list. The engine path for `Filter` intensity already keys by filter index in `filterAnimations`, so the editor mirrors that. |
| Keyframe gestures | Tap to add at `currentTime`, long-press to remove, drag to retime | Standard timeline-editor conventions. Matches CapCut / IMG.LY / VideoLab. Snap-to-frame deferred. |
| Animated text preview | `UIViewRepresentable` / `NSViewRepresentable` wrapping a CALayer + CAAnimation when `TextOverlay.textAnimation != nil` | Fidelity matches the export's `AVVideoCompositionCoreAnimationTool` path (engine uses CALayer + CAAnimation for animated text). SwiftUI primitives can't reproduce all CAAnimation shapes faithfully (kerning, custom paths, etc.). Static text keeps the SwiftUI `Text` fast path. |
| Crossfade glyph | Small white triangle pointing across the boundary in the audio lane | Visual-only, non-interactive in v0.6. Engine handles the crossfade math; the glyph is a passive indicator. Style tweakable in v0.6.x. |
| `KeyframeEditor` height | Defaults to a sensible per-row height (24px) plus 4px spacing; total = `numProperties × 28px` | Avoids forcing callers to compute. They can override via SwiftUI `.frame(...)` like every other component. |
| Filter intensity slider range | Per-filter, baked into the panel — `.brightness` shows -1...1, `.gaussianBlur` shows 0...50, etc. | Matches each preset's natural range. Consumer code doesn't need to know the ranges. Inspector handles them; out-of-range values clamp at slider edges. |

### Public surface sketch

```swift
public struct InspectorPanel: View {
    public init(
        _ video: Video,
        selectedClipID: Binding<ClipID?>,
        onTransform: ((ClipID, Transform) -> Void)? = nil,
        onOpacity: ((ClipID, Double) -> Void)? = nil,
        onFilterIntensity: ((ClipID, _ filterIndex: Int, _ intensity: Double) -> Void)? = nil
    )
}

public struct KeyframeEditor: View {
    public init(
        _ video: Video,
        selectedClipID: Binding<ClipID?>,
        currentTime: Binding<CMTime>,
        rowHeight: CGFloat = 24,
        rowSpacing: CGFloat = 4,
        onAdd: ((ClipID, KeyframeProperty, CMTime) -> Void)? = nil,
        onRemove: ((ClipID, KeyframeProperty, CMTime) -> Void)? = nil,
        onRetime: ((ClipID, KeyframeProperty, _ from: CMTime, _ to: CMTime) -> Void)? = nil
    )
}

public enum KeyframeProperty: Sendable, Hashable {
    case transform
    case opacity
    case filter(index: Int)
}

// OverlayHost gains an internal CALayer-backed bridge view; no public surface change.
// TimelineView gains an internal crossfade-glyph render path; no public surface change.
```

### Tier breakdown

Mirrors the established RFC-then-tiers staging.

- **Tier 0** *(this PR)* — design doc only. Bumps Kadr dep floor to 0.8.0.
- **Tier 1** — `InspectorPanel`. Sliders for Transform (center / rotation / scale / anchor), opacity, and per-filter intensity. Callback wiring. ~250 LOC + tests.
- **Tier 2** — `KeyframeEditor`. Per-property track rendering, tap-to-add, long-press-to-remove, drag-to-retime. The biggest tier of the cycle. ~400 LOC + tests.
- **Tier 3** — Animated text preview. `UIViewRepresentable` / `NSViewRepresentable` bridge for `TextOverlay`s with `textAnimation`. ~150 LOC + tests.
- **Tier 4** — TimelineView crossfade glyphs. Detect overlapping `AudioTrack`s with `crossfadeDuration`; render small triangle markers in the audio lane. ~80 LOC + tests.
- **Tier 5** — Release prep: CHANGELOG, README compat row, ROADMAP entry, develop → main release flow.

### Test strategy

Mirrors the v0.5 RFC's pattern — pure helpers carry the bulk:

- **Inspector** — pure helper `clipFor(id:in:)` extracts a clip from `Video.clips` by `ClipID`. Modifier tests: each on… callback wires through. Smoke tests (`@MainActor`) on the View body.
- **KeyframeEditor** — pure helpers: `keyframesForProperty(_:on:)`, `propertyOptions(for:)`. Smoke tests on the body.
- **Animated text preview** — bridge view smoke tests (no faithful CAAnimation playback in unit tests; visual fidelity verified via the example app).
- **Crossfade glyphs** — pure detection helper `crossfadeBoundaries(in: Video) -> [CMTime]`. Smoke test on TimelineView body.

Target coverage: ~25 new tests across the cycle. Suite floor: 119.

### Compatibility

- KadrUI 0.6.0 requires Kadr ≥ 0.8.0 (uses `Transform`, `Animation<T>`, `TextAnimation`, `AudioTrack.crossfadeDuration`).
- v0.5.x call sites: source-compatible. All existing init params keep their meaning. New components are additive.
- README compatibility table: add `0.6.0 | ≥ 0.8.0`.

### Open questions (track in PRs, not blocking RFC merge)

- **Inspector layout direction** — vertical sliders stacked, or horizontal slider rows? Currently leaning **horizontal rows** (label on left, slider in middle, value on right) to match iOS settings-screen conventions. Revisit in tier 1.
- **KeyframeEditor zoom-to-fit** — should the editor's time axis match the parent `TimelineView`'s zoom level (when zoom ships in v0.6.x), or always show the selected clip's full lifetime? Defer to when zoom lands.
- **Crossfade glyph style** — triangle / hourglass / X-mark / custom shape. Triangle pointing along the timeline is the lowest-friction default; revisit if anyone asks.

## v0.7 — Timeline zoom + editing inside Tracks

The two highest-leverage `TimelineView` gaps. Without zoom, long compositions are unworkable; without Track-internal editing, multi-track timelines are partially read-only. Both surfaced as soreness while building reels-studio's editor against v0.6.

### Problem

1. **No zoom.** v0.4.1 fixed the timeline width to `geometry.size.width`. A 5-minute composition at 360 px wide gives ~1.2 px per second — clip blocks are unselectable, transitions invisible. CapCut / Final Cut / iMovie all let users pinch-zoom the timeline; consumers reimplementing this on top of `TimelineView` is a lot of work.
2. **Tracks are read-only.** `TimelineView`'s `onReorder` / `onTrim` callbacks operate on `video.clips` — i.e. the implicit chain. Clips inside a `Track {}` block render but can't be reordered or trimmed. v0.5's RFC explicitly deferred this; reels-studio hits it the moment a user tries to edit a B-roll track.

### Scope lock

In scope:
- **Pinch-to-zoom on `TimelineView`.** New init parameter `zoom: Binding<TimelineZoom>?` (optional); when bound, magnification gesture mutates the zoom. Default behavior unchanged when binding is `nil`.
- **`TimelineZoom` value type.** `pixelsPerSecond: Double` + helpers (`.fitToWidth(_:)`, `.zoomed(by:)`). Floor / ceiling clamps to keep clip blocks at usable sizes (`8 px/s` floor, `400 px/s` ceiling).
- **Horizontal scrolling.** When zoomed timeline's natural width exceeds `geometry.size.width`, content scrolls inside an internal `ScrollView`. Selection / drag gestures keep working on the scrolled content.
- **`TimelineView.onTrackReorder` callback.** `(trackIndex: Int, from: Int, to: Int, newClips: [any Clip]) -> Void` — fires when the user drags a clip *within* a `Track {}` block. `trackIndex` indexes into `video.clips.compactMap { $0 as? Track }`; `newClips` is the rebuilt inner-clip array ready for the consumer to drop into a fresh `Track`.
- **`TimelineView.onTrackTrim` callback.** `(trackIndex: Int, clipIndex: Int, leadingTrim: CMTime, trailingTrim: CMTime) -> Void` — same Track-rooted indexing as above; mirror of the v0.4.3 `onTrim` shape.
- **Pure helpers** — `applyTrackReorder(track:from:to:)` returns `[any Clip]`, mirroring `applyChainReorder`. Public for tests + consumers building custom reorder UI.

Out of scope (v0.7.x or later):
- **Cross-lane drag** (move a clip from chain → Track or between Tracks) — already declared a non-goal in v0.5 RFC; UX-heavy and consumer-specific.
- **Editing free-floater rows** — clips pinned with `.at(time:)` into a free-floater pack stay read-only. The packing assignment is greedy and brittle to reorder; consumers wanting per-floater edits should use a Track instead. Document the limitation.
- **Zoom-to-fit / auto-zoom on selection.** Out of scope; consumers can drive `TimelineZoom` via the binding if they want this UX.
- **Vertical zoom / lane-height adjustment.** Out of scope; lanes stay at the existing `laneHeight` parameter.
- **Velocity-based zoom inertia.** Out of scope; pinch-end snaps to the gesture's final scale.
- **Animated zoom transitions.** Out of scope; the binding mutation is whatever SwiftUI's default animation does.
- **Track lane label tap → expand/collapse.** Considered, dropped — lanes already render fully; collapse is a different feature (track muting / hiding).

### API examples

```swift
import Kadr
import KadrUI

// 1. Zoom — opt-in via binding.
@State private var zoom = TimelineZoom.fitToWidth(360)  // start at fit-to-width
@State private var time: CMTime = .zero

TimelineView(
    video,
    currentTime: $time,
    zoom: $zoom
)
.frame(height: 96)
.gesture(MagnifyGesture().updating(...))   // app drives the binding via gesture; or
                                             // pass through TimelineView's built-in
                                             // pinch-to-zoom (auto-bound when zoom: is non-nil).

// 2. Editing inside a Track.
TimelineView(
    video,
    selectedClipID: $selected,
    onReorder:      { _, _, newClips in /* chain reorder */ },
    onTrackReorder: { trackIndex, _, _, newInnerClips in
        // Rebuild Video with newInnerClips at the given Track.
    },
    onTrim:         { _, leading, trailing in /* chain trim */ },
    onTrackTrim:    { trackIndex, clipIndex, leading, trailing in
        // Apply trim to the inner clip.
    }
)
```

### Public surface sketch

```swift
public struct TimelineZoom: Sendable, Equatable {

    /// Horizontal pixel density. Higher = wider clip blocks. Clamped to
    /// `8...400` px/s to keep blocks selectable at zoom-out and avoid
    /// runaway timelines at zoom-in.
    public var pixelsPerSecond: Double

    /// Build a zoom that fits the entire composition into the given width.
    /// Call sites pass `geometry.size.width` and the composition's duration.
    public static func fitToWidth(_ width: Double, totalSeconds: Double) -> TimelineZoom

    /// Multiply the current density by `factor`, clamped.
    public func zoomed(by factor: Double) -> TimelineZoom

    /// Density floor / ceiling. Public so consumers can build custom UIs that
    /// hint at zoom limits.
    public static let minPixelsPerSecond: Double = 8
    public static let maxPixelsPerSecond: Double = 400
}

public extension TimelineView {

    /// New init param. When `zoom` is non-`nil`, the timeline switches to a
    /// scrolling render with the specified pixel density and binds a
    /// magnification gesture to mutate it. When `nil` (default), behavior is
    /// the v0.6 fit-to-width render.
    init(
        _ video: Video,
        currentTime: Binding<CMTime>? = nil,
        selectedClipID: Binding<ClipID?>? = nil,
        zoom: Binding<TimelineZoom>? = nil,
        laneHeight: CGFloat = 40,
        laneSpacing: CGFloat = 4,
        showAudioLanes: Bool = true,
        showAudioWaveforms: Bool = false,
        showLaneLabels: Bool = false,
        onReorder: ((_ from: Int, _ to: Int, _ newClips: [any Clip]) -> Void)? = nil,
        onTrim: ((_ clipIndex: Int, _ leadingTrim: CMTime, _ trailingTrim: CMTime) -> Void)? = nil,
        onTrackReorder: ((_ trackIndex: Int, _ from: Int, _ to: Int, _ newInnerClips: [any Clip]) -> Void)? = nil,
        onTrackTrim: ((_ trackIndex: Int, _ clipIndex: Int, _ leadingTrim: CMTime, _ trailingTrim: CMTime) -> Void)? = nil
    )

    /// Pure: apply a reorder (from → to) to a Track's inner clips. Mirrors
    /// `applyChainReorder` for chain clips. Public for tests + consumers
    /// building custom Track-row UI.
    static func applyTrackReorder(track: Track, from: Int, to: Int) -> [any Clip]
}
```

### Engine notes

- **Zoom rendering.** When `zoom != nil`, the timeline body wraps lane rows in a `ScrollView(.horizontal)`. Lane width = `totalSeconds * zoom.pixelsPerSecond`. Existing `pxPerSecond` math shifts from `geometry.width / totalSeconds` to `zoom.pixelsPerSecond`. The playhead and gesture math reference the scroll content's coordinate space.
- **Pinch gesture.** `MagnifyGesture` (iOS 17+) on the lane stack scales the bound `pixelsPerSecond` by the gesture's `magnification`. Starting density captured on `onChanged` first fire; subsequent updates multiply. Clamped to `[minPixelsPerSecond, maxPixelsPerSecond]`. The gesture composes with selection / reorder / trim (existing pattern: drag uses 5-pt minimum distance).
- **Track reorder routing.** When the user starts dragging a clip on a Track lane (`LaneKind.track(index, ...)`), the existing reorder math switches to the Track's inner-clips array, and the resulting `newClips` array goes through `onTrackReorder` instead of `onReorder`. Transitions inside a Track travel with their preceding clip identically to chain reorder. The `applyTrackReorder` pure helper does the math without view-layer state.
- **Track trim routing.** Same swap — when a trim handle drag starts on a Track lane, the eventual `onTrackTrim` callback fires with `trackIndex` (position of the Track in `video.clips.compactMap { $0 as? Track }`) + `clipIndex` (position within the Track's inner clips).

### Tier breakdown

- **Tier 0** *(this PR)* — design doc only. No code.
- **Tier 1** — `TimelineZoom` + zoom binding + ScrollView wrapping + pinch gesture. ~250 LOC + tests.
- **Tier 2** — Track-internal reorder + trim. `onTrackReorder` / `onTrackTrim` callbacks; `applyTrackReorder` helper. ~300 LOC + tests.
- **Tier 3** — Release prep + ship as **v0.7.0**.

### Test strategy

- **`TimelineZoom`** — `fitToWidth` math, `zoomed(by:)` clamping, equality. Pure value-type tests.
- **Pinch gesture** — `@MainActor` smoke test that mutates zoom via test-only access; integration via reels-studio.
- **`applyTrackReorder`** — full coverage mirroring `applyChainReorderTests`: empty, single clip, swap adjacent, swap non-adjacent, drag past end, transition-travels-with-preceding-clip.
- **Body smoke** — TimelineView constructs with non-nil zoom binding and Track-callbacks without crashing.

Target test count: ~30 new tests. Suite floor: 164 → ~194.

### Compatibility

- **Pure additive.** Every v0.6 call site compiles unchanged — both new parameters are optional.
- **Bumps Kadr dep floor.** No (kadr 0.10's surface isn't required by v0.7); kadr ≥ 0.8.0 stays the floor.
- **Same platform support.** iOS 16+ / macOS 13+ / tvOS 16+ / visionOS 1+.

### Open questions (track in PRs, not blocking RFC merge)

- **Vertical scroll for many lanes.** A composition with 6+ tracks plus audio gets tall. v0.7 doesn't add vertical scroll inside `TimelineView` — consumers wrap in their own `ScrollView` if needed. Revisit if real users hit it.
- **Zoom-state persistence.** `TimelineZoom` is per-view state; consumers persist it themselves (e.g. in a `ProjectStore`). Should `TimelineView` offer a "remembered zoom" affordance? Probably not — keep state ownership explicit.
- **Track-row trim on the *whole* track.** "Trim every clip in this track to fit under 5 seconds" — niche. Consumers can do this themselves by iterating `track.clips` and applying their own trim math.

---

## v0.8 — SpeedCurveEditor / CaptionEditor / OverlayInspector

**Status:** RFC. Tier 0 only — no code.

### Motivation

Three editor surfaces have been deferred since v0.6 — they're listed in the v0.6 CHANGELOG as "deferred to v0.7+" and got nudged again to v0.7+ as the timeline-zoom + Track-internal-reorder cycle took priority. They're the last gaps blocking `kadr-reels-studio` from being a complete editor demo and they all consume kadr ≥ 0.9 surface that's already public — no kadr v0.11 cycle needed.

- **Speed-curve editor** — kadr v0.9 shipped `VideoClip.speed(curve: Animation<Double>)` and exposes `speedCurve: Animation<Double>?` as a public read-only property. There's no SwiftUI surface to author the curve. Consumers writing inspector UIs end up either hard-coding presets or skipping speed entirely.
- **Caption editor** — kadr v0.9.2 made `Video.captions(_:)` and the `Caption` struct public. Reels-studio can ingest captions via `kadr-captions`' parsers, but there's no surface to add / edit / retime cues after import.
- **Inspector for overlays** — `InspectorPanel` (v0.6) only handles per-`Clip` properties: Transform / Filter / opacity. Overlay types (`TextOverlay`, `StickerOverlay`, `ImageOverlay`, `Watermark`) have no inspector surface. Reels-studio's `AddOverlaySheet` defers image overlays to v0.1.x partly because there's no editor to follow up the add.

### Public API

```swift
// MARK: - Tier 1: SpeedCurveEditor

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct SpeedCurveEditor: View {
    public init(
        clip: VideoClip,
        currentTime: Binding<CMTime>? = nil,
        height: CGFloat = 80,
        onUpdate: @escaping (Animation<Double>?) -> Void
    )
}
```

- Vertical axis = speed multiplier (clamped to display range `0.25...4.0`, with `1.0` rendered as a baseline gridline).
- Horizontal axis = clip-relative time (`0...trimRange.duration`).
- **Tap empty area** → add keyframe at that (time, multiplier).
- **Drag a marker** horizontally → retime; vertically → rescale the multiplier.
- **Long-press a marker** → remove.
- Picker for `TimingFunction` (linear / easeIn / easeOut / easeInOut / cubicBezier presets).
- Passing `nil` to `onUpdate` clears the curve (consumer calls `clip.speed(1.0)` to reset to flat playback, or `clip.speed(curve:)` with the new animation).
- `currentTime` binding (optional) overlays a vertical playhead synced to the host's playback time, mirroring `TimelineView`'s pattern.

```swift
// MARK: - Tier 2: CaptionEditor

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct CaptionEditor: View {
    public init(
        captions: [Caption],
        compositionDuration: CMTime,
        currentTime: Binding<CMTime>? = nil,
        onUpdate: @escaping ([Caption]) -> Void
    )
}
```

- Vertical list of cues sorted by `timeRange.start`.
- Each row: text field (multi-line), start / end timestamp fields, "delete" button, "set start to playhead" / "set end to playhead" shortcuts (active when `currentTime` is bound).
- "+ Add cue" — appends a new `Caption(text: "", timeRange: <2-second window starting at currentTime ?? composition mid>)`.
- Reorder is implicit (sort by start time on every emit) — no drag handles.
- `compositionDuration` is the upper bound for end-time validation (cues outside `[0, duration]` get red-bordered but aren't dropped silently).
- `onUpdate` fires on every commit (text-field blur / timestamp edit / +/- tap). Consumer rebuilds `Video` via `video.captions(newCues)`.

```swift
// MARK: - Tier 3: OverlayInspector extension + overlay keyframe authoring

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension InspectorPanel {

    /// Overlay-targeted variant of `InspectorPanel`. Same callback shape; one
    /// inspector renders all four built-in overlay kinds via type dispatch.
    public init(
        video: Video,
        selectedOverlayID: Binding<LayerID?>,
        onUpdate: @escaping (LayerID, OverlayUpdate) -> Void
    )
}

public enum OverlayUpdate: Sendable {
    /// Plain `TextOverlay` text / font / color / position / opacity / animation.
    case text(TextOverlayUpdate)
    /// `StickerOverlay` source / scale / position / opacity.
    case sticker(StickerOverlayUpdate)
    /// `ImageOverlay` source / position / opacity.
    case image(ImageOverlayUpdate)
    /// `Watermark` text / corner / opacity.
    case watermark(WatermarkUpdate)
}

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension KeyframeEditor {

    /// Overlay-targeted variant of `KeyframeEditor`. Same gesture model — tap
    /// empty row to add at playhead, long-press a marker to remove, drag to
    /// retime — but rows bind to overlay properties instead of `Clip` properties.
    /// Property set per overlay kind:
    /// - `TextOverlay`    → `.position`, `.opacity`
    /// - `StickerOverlay` → `.position`, `.opacity`, `.scale`
    /// - `ImageOverlay`   → `.position`, `.opacity`
    /// - `Watermark`      → `.opacity` (corner-anchored, position not animated)
    public init(
        video: Video,
        selectedOverlayID: Binding<LayerID?>,
        currentTime: Binding<CMTime>,
        onAdd: @escaping (LayerID, OverlayProperty, CMTime) -> Void,
        onRemove: @escaping (LayerID, OverlayProperty, CMTime) -> Void,
        onRetime: @escaping (LayerID, OverlayProperty, CMTime, CMTime) -> Void
    )
}

public enum OverlayProperty: Sendable, Hashable {
    case position
    case opacity
    case scale  // sticker-only; row suppressed for other overlay kinds
}
```

- Overlay-update structs mirror existing kadr Overlay constructor params; consumers route them back into a fresh `Video { ... overlay(...) }` rebuild.
- Surface picks the inspector body by inspecting the selected layer ID's underlying overlay type (via `Video.overlays.first { $0.layerID == id }` matching).
- The `Clip`-targeted `InspectorPanel(video:selectedClipID:onUpdate:)` and `KeyframeEditor(video:selectedClipID:...)` from v0.6 stay untouched — adding overloads, not replacing.
- **Why overlay keyframes are in Tier 3 scope (not deferred):** animated text and animated stickers are *the* visual signature of TikTok / IG-style reels. Without authoring, kadr-reels-studio is stuck on the fixed `TextAnimation` enum (typewriter / fade / slide) — fine for the walking skeleton, limiting for a real demo. The v0.6 `KeyframeEditor` already solved the per-property authoring pattern for clips; extending it to overlays is incremental, not novel.

### Engine notes

- **Speed-curve sampling.** No engine work — `SpeedCurveSampler` already discretizes `Animation<Double>` for export. The editor only authors the value type.
- **Caption ordering.** kadr's engine accepts cues in any order (`Video.captions(_:)` accumulates). The editor sort is purely a UX choice.
- **Overlay layer-ID lookup.** Every overlay type already conforms to a layer-ID-bearing protocol; the inspector reuses `OverlayHost`'s existing introspection helpers (`overlay(for:in:)`).

### Tier breakdown

- **Tier 0** *(this PR)* — RFC only. No code.
- **Tier 1** — `SpeedCurveEditor`. Pure helpers (`keyframeForGesture`, `clampMultiplier`, hit-test math) factored as `nonisolated static` for testability. ~350 LOC + ~25 tests.
- **Tier 2** — `CaptionEditor`. Validation helpers (`isValidCueRange`, `sortedByStart`) static + pure. ~250 LOC + ~15 tests.
- **Tier 3** — `OverlayInspector` overload + four `OverlayUpdate` variants + dispatch, plus `KeyframeEditor` overlay overload + `OverlayProperty` row dispatch. ~600 LOC + ~30 tests.
- **Tier 4** — Release prep + ship as **v0.8.0**.

### Test strategy

- **`SpeedCurveEditor`** — keyframe hit-test math, multiplier clamping, drag-resolution rules (which marker wins when two share a time), `TimingFunction` round-trip via update callback.
- **`CaptionEditor`** — sort-on-emit, validation flagging out-of-range cues, "set to playhead" math, add-cue default-window logic.
- **`OverlayInspector`** — overlay-type dispatch, `OverlayUpdate` round-trip per variant, layer-ID lookup defensive against stale IDs (overlay removed but selection still set).
- **Overlay `KeyframeEditor`** — property-set dispatch per overlay kind (sticker emits `.scale` row, watermark suppresses `.position`), keyframe hit-test parity with v0.6 chain editor, retime monotonicity (drag past adjacent keyframe clamps).
- **Body smoke** — each surface constructs without crashing under the same patterns as `TimelineViewTests` (every required init-param permutation).

Target test count: ~70 new tests. Suite floor: 188 → ~258.

### Compatibility

- **Pure additive.** All three surfaces are new. The existing `InspectorPanel(video:selectedClipID:)` v0.6 init stays unchanged; `OverlayInspector` is an overload distinguished by `selectedOverlayID:` vs `selectedClipID:`.
- **Kadr floor.** Stays at **≥ 0.10.0** (the v0.7 floor — no new kadr surface required).
- **Platform.** iOS 16+ / macOS 13+ / tvOS 16+ / visionOS 1+.

### Open questions (track in PRs, not blocking RFC merge)

- **Bézier handles vs. discrete keyframes.** The speed-curve editor renders `Animation<Double>` keyframes as discrete points connected by the timing function. A "true" Bézier editor would expose `cubicBezier` control handles directly. Defer — keyframes-with-timing covers the common case.
- **Caption text styling.** v0.8 ships plain-text cues only. Styled output via `kadr-captions`' `StyledCaption` is reels-studio's import-side concern; the editor doesn't author per-cue colors / positions in this cycle.
- **Multi-select on overlays.** Single-selection only in v0.8. Multi-select edit (e.g., set opacity on three overlays at once) is a v0.9+ if requested.

## v0.9 — Fixed-center playhead + zoom-snap callback

**Status:** RFC. Tier 0 only — no code.

### Motivation

`kadr-reels-studio` v0.4 is wiring up the *feel* layer of the editor — two-tier toolbar, snap haptics on pinch-zoom, fixed-center playhead during scrub, accent threading. Two surfaces inside `TimelineView` need new public hooks for that work to land:

- **Playhead drift during scrub.** `TimelineView`'s playhead is anchored to its time position inside the scroll content. As the playhead advances during playback or scrub, it walks toward the right edge of the viewport and eventually leaves it, requiring the user to manually scroll the timeline to find it. CapCut / VN / iMovie all anchor the playhead to the screen-center and scroll the *content* under it. There's no opt-in for that mode today.
- **Snap-aware haptics.** Pinch-to-zoom in `TimelineView` is continuous — `pixelsPerSecond` updates on every magnification delta. UX-wise, beat / second / 5s / 30s alignments are perceptible breakpoints, and consumers want to fire haptics when the user crosses one. The zoom math lives inside `TimelineView` (`TimelineZoom.clamp`, the magnification baseline capture); duplicating it consumer-side to detect crossings is brittle.

`OverlayHost.onLayerTap(_:)` was originally listed in this RFC's scope but it's already shipping in v0.8. Drop it.

### Public API

```swift
// MARK: - Tier 1: fixedCenterPlayhead

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension TimelineView {
    /// Anchor the playhead to the horizontal center of the viewport and scroll
    /// the timeline content under it, instead of letting the playhead drift
    /// toward the right edge as time advances. No-op when ``currentTime`` was
    /// not bound at init — the playhead only renders in that case.
    public func fixedCenterPlayhead(_ enabled: Bool = true) -> TimelineView
}
```

- Implemented by wrapping the existing `ScrollView(.horizontal)` in a `ScrollViewReader` and emitting `proxy.scrollTo(_:anchor:)` with `anchor: .center` keyed to a hidden anchor view positioned at `currentTime`.
- The user can still scroll manually; the modifier governs the *automatic* behavior on `currentTime` change. Manual scrolls don't fight the auto-snap because we only emit `scrollTo` when `currentTime` actually changes (Combine `.removeDuplicates` on the binding).
- No-op when zoom isn't bound — without zoom there's no scroll view to drive.

```swift
// MARK: - Tier 2: onZoomSnap

public struct ZoomSnapThreshold: Sendable, Hashable {
    public let pixelsPerSecond: Double
    /// Human-readable label — e.g. "1f", "1s", "5s", "30s". Consumers can use
    /// this for UI ("Snap: 5s") or pick haptic strength based on the bracket.
    public let label: String
}

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension TimelineView {
    /// Fires whenever pinch-zoom crosses an internal snap threshold. The
    /// threshold list is fixed (frame / second / 5s / 30s) — kadr-ui owns the
    /// zoom math, so it owns the breakpoints.
    public func onZoomSnap(_ action: @escaping (ZoomSnapThreshold) -> Void) -> TimelineView
}
```

- Threshold list at v0.9.0: `[1 frame (~30 px/s @ 30fps), 1 second (50 px/s), 5 seconds (10 px/s), 30 seconds (~1.7 px/s)]`. Exposed as `ZoomSnapThreshold.standard: [ZoomSnapThreshold]` for consumers who want to label zoom levels in their UI.
- Fires only on *crossing* — the magnification gesture's `onChanged` checks the previous and current `pixelsPerSecond` against the threshold list; emits when an entry sits between them. No emission when the gesture stays inside one bracket.
- Doesn't snap the value itself. The consumer decides whether to play haptics, show a label, or do nothing. If a future tier wants opt-in snap-to-threshold behavior (the gesture *settles* at the nearest threshold on `onEnded`), that's a v0.9.1 patch — out of scope here.

### Tier breakdown

- **Tier 0** *(this PR)* — RFC only. No code.
- **Tier 1** — `fixedCenterPlayhead(_:)` modifier + `ScrollViewReader` integration. Anchor view + `.removeDuplicates` Combine plumbing. ~80 LOC + ~8 tests (anchor presence, no-op when `currentTime` is nil, no-op when zoom is nil).
- **Tier 2** — `onZoomSnap(_:)` callback + `ZoomSnapThreshold` struct + crossing-detection helper. `nonisolated static crossings(prev:current:in:)` for testability. ~60 LOC + ~10 tests (single-bracket no-fire, single-crossing emission, multi-crossing on rapid zoom, direction-symmetric).
- **Tier 3** — Release prep + ship as **v0.9.0**.

### Test strategy

- **`fixedCenterPlayhead`** — `TimelineView` body construction with the modifier flipped on / off; smoke that `ScrollViewReader` anchor positioning compiles. Real centering is visual — `swift-snapshot-testing` harness is on the v1.0 list, so v0.9 sticks to construction smoke.
- **`onZoomSnap`** — pure logic on `crossings(prev:current:in:)`. Cases: stay inside one bracket → empty result; cross one threshold up → single entry; cross multiple on rapid zoom → ordered list; symmetric on zoom-out (direction-agnostic, consumer can detect direction from `prev` vs `current` if needed in a future tier).

Target test count: ~18 new tests.

### Compatibility

- **Pure additive.** Both surfaces are new modifiers; the `TimelineView(...)` init is untouched.
- **Kadr floor.** Stays at **≥ 0.10.0**.
- **Platform.** iOS 16+ / macOS 13+ / tvOS 16+ / visionOS 1+.

### Open questions (track in PRs, not blocking RFC merge)

- **Snap-to-threshold settle.** v0.9 fires a callback on crossing but doesn't *change* `pixelsPerSecond`. v0.9.1 could add an opt-in `.snapToThresholds()` modifier that nudges zoom to the nearest threshold on `gesture.onEnded`. Defer — fires-on-crossing is what reels-studio v0.4 needs and snap-to-settle changes the feel materially.
- **Threshold customization.** `ZoomSnapThreshold` is a public struct so consumers *could* build their own list, but `onZoomSnap` only consumes the kadr-ui internal list at v0.9. Adding a `thresholds:` overload is a v0.9.x patch if community demand surfaces.
- **Manual-scroll detente.** When the user pans the timeline manually with `fixedCenterPlayhead` on, current spec lets the auto-snap re-center on the next `currentTime` change. CapCut adds a brief "user is scrubbing" detente that suppresses re-centering for ~500ms. Not in v0.9 scope; track in a follow-up if reels-studio v0.4 manual QA flags it.

## v0.9.1 — onClipDragSnap

**Status:** RFC. No code yet.

### Motivation

`kadr-reels-studio` v0.4 Tier 3 wires snap haptics on the timeline's pinch-zoom (via the v0.9 `onZoomSnap`) and *was supposed to* mirror them on drag-snap-to-adjacent-clip. The v0.4 RFC claimed `TimelineView.onClipDragSnap` already shipped in v0.8 (parallel to the `OverlayHost.onLayerTap` errata). Verification during Tier 3 scoping showed it never landed — the v0.9 cycle accidentally inherited the gap.

This is a single-surface micro-patch — same shape as kadr v0.10.1's animation-clearing modifiers — to close the haptic-symmetry gap before Tier 3 ships.

### Public API

```swift
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension TimelineView {
    /// Fires when an in-flight reorder drag crosses an adjacent-slot
    /// boundary — the moment the dragged clip would land on a new resting
    /// position if released. Same callback fires for chain reorders (when
    /// `onReorder` is bound) and Track-internal reorders (when
    /// `onTrackReorder` is bound). Consumers fire haptics from here.
    public func onClipDragSnap(_ action: @escaping () -> Void) -> TimelineView
}
```

- **Trigger.** During each reorder gesture's `onChanged`, recompute the would-be `targetIndex` via the existing `computeTargetIndex(...)` helper. Fire when the value differs from the previously-fired one. State lives on a single `@State lastChainSnapIndex: Int?` (chain) + `lastTrackSnapIndex: TrackDragKey?` (Track) — reset on `onEnded`.
- **No payload.** Consumers wire haptics; they don't need the index. A future overload (`onClipDragSnap((Int) -> Void)`) could expose the index if useful — defer until requested.
- **Direction-symmetric.** Drag-left and drag-right both fire each time the boundary crosses.
- **Both gestures.** Chain (`reorderGesture`) and Track-internal (`trackReorderGesture`) share the modifier — consumers don't have to wire two callbacks for the same haptic.

### Tier breakdown

- **Tier 0** *(this PR)* — RFC only. No code.
- **Tier 1** — `onClipDragSnap(_:)` modifier + chain + Track wiring. ~40 LOC + ~6 tests (target-index change detection on each gesture, no-emit when target stays put, no-emit at gesture start, fire-on-each-cross-back-and-forth).
- **Tier 2** — Release prep + ship as **v0.9.1**.

### Compatibility

- **Pure additive.** Single new modifier; reorder gesture call paths unchanged for non-callers.
- **Kadr floor.** Stays at **≥ 0.10.0**.
- **Platform.** iOS 16+ / macOS 13+ / tvOS 16+ / visionOS 1+.

### Open questions

- **Index-bearing overload.** The current spec is no-payload. Add `onClipDragSnap((Int) -> Void)` if a real consumer surfaces a use case for the target index (e.g. live-label "moves to position 3"). Defer.
- **Threshold customization for snap aggressiveness.** Today the snap point is the slot midpoint (set by the existing `computeTargetIndex` math). A future patch could let consumers pull or push the snap threshold (sticky / loose). Out of scope; revisit if QA flags.

## v0.9.2 — Multi-select + long-press

**Status:** RFC. No code yet.

### Motivation

`kadr-reels-studio` v0.4 Tier 5 (Track creation UI — "wrap selection in track") needs two surfaces from `TimelineView` that don't ship today, both blocking proper UX:

- **Visual feedback for multi-selected clips.** `TimelineView`'s selection ring is single-clip (`Binding<ClipID?>`). Without exposing a multi-select binding, multi-selected clips render identical to unselected ones — the user can't see what they've selected. Faking multi-select consumer-side via the existing single binding loses this entirely.
- **Long-press to enter multi-select mode.** CapCut / VN / iMovie all enter multi-select via long-press on a clip. `TimelineView` only exposes `onTapGesture` for selection; there's no callback for long-press. Forcing the consumer to build a "Select Clips" toolbar-button mode toggle ships, but the gesture is the more discoverable affordance.

This is the same shape as v0.9.1's `onClipDragSnap` patch — narrow micro-additions driven by a downstream cycle. Two surfaces, both additive, no breaking changes.

### Public API

```swift
// MARK: - Tier 1: Multi-select binding

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct TimelineView: View {
    public init(
        _ video: Video,
        currentTime: Binding<CMTime>? = nil,
        selectedClipID: Binding<ClipID?>? = nil,
        selectedClipIDs: Binding<Set<ClipID>>? = nil,  // NEW
        zoom: Binding<TimelineZoom>? = nil,
        // …
    )
}
```

- **Coexists with `selectedClipID`.** A clip renders selected when *either* binding marks it: `(selectedClipID == clip.id) || selectedClipIDs.contains(clip.id)`. Consumers running both bindings (current single-select + new multi-select) see the union; the typical multi-select UX is to clear `selectedClipID` while a multi-select gesture is active.
- **Tap behavior is unchanged** — taps continue to write to `selectedClipID` only. Toggle-into-set semantics are the consumer's call, driven by `onLongPressClip` entering a mode where the consumer intercepts tap binding writes. v0.9.2 doesn't bake mode state into `TimelineView`.
- **Renders rings on every member.** All three render sites (`videoRow`, `imageRow`, `transitionRow`) extend `isSelected` to check both bindings.

```swift
// MARK: - Tier 1 (continued): onLongPressClip

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension TimelineView {
    /// Fires on a 0.5s long-press of any media clip with a non-nil
    /// ``Kadr/Clip/clipID``. Hands over the clip's id; consumers typically
    /// use this to enter a multi-select mode and seed the set with the
    /// long-pressed clip.
    public func onLongPressClip(_ action: @escaping (ClipID) -> Void) -> TimelineView
}
```

- **Composes with the existing tap gesture** via SwiftUI's `.simultaneousGesture` so both can register without one swallowing the other. The 5-pt minimum-distance reorder drag (`DragGesture(minimumDistance: 10)`) sits above; long-press fires only when the user holds without dragging.
- **Track-lane clips fire the same callback.** Symmetric with `onTapGesture` coverage in v0.7+.
- **Single-fire per gesture.** No repeated emissions on continued press.

### Tier breakdown

- **Tier 0** *(this PR)* — RFC only. No code.
- **Tier 1** — Both surfaces in one PR (small enough — ~50 LOC + ~10 tests). `selectedClipIDs` parameter + render-site `isSelected` extensions; `onLongPressClip(_:)` modifier + LongPressGesture wired alongside existing tap. Pure helpers exposed `nonisolated public static`: `clipMatchesSelection(id:single:set:)` for the union check.
- **Tier 2** — Release prep + ship as **v0.9.2**.

### Compatibility

- **Pure additive.** Existing `selectedClipID:` parameter and `onTapGesture` selection write are unchanged.
- **Kadr floor.** Stays at **≥ 0.10.0**.
- **Platform.** iOS 16+ / macOS 13+ / tvOS 16+ / visionOS 1+.

### Open questions

- **Long-press duration tuning.** v0.9.2 ships 0.5s (SwiftUI's `LongPressGesture` default). CapCut feels closer to 0.4s; VN to 0.6s. Defer customization until reels-studio v0.4 manual QA; expose `onLongPressClip(minimumDuration:_:)` overload if the default is wrong.
- **Multi-select drag reorder.** Today only single clips reorder. Multi-select drag — the gesture moves an arbitrary subset — is a much bigger change (kadr's `Video` builder doesn't model "swap these N clips into block X"). Out of scope; track if reels-studio v0.4+ asks for it.
- **Long-press on overlays (`OverlayHost`).** Symmetric surface for overlay multi-select. Defer until a real consumer asks — overlays are flat-z-ordered (Layers sheet shows everything), not lane-positioned, so the use case is weaker.

## v0.10.0 — API hardening + overlay multi-select

**Status:** RFC. No code yet.

### Motivation

A cross-package audit before the v1.0 stability commitment surfaced two API-shape issues that should be fixed before v1.0 freezes the surface. Both are breaking; bundle in one cycle so reels-studio v0.6.0 (which floor-bumps kadr-ui) absorbs the migration once.

- **Callback parameter-order landmines.** Every `TimelineView` reorder / trim callback uses positional args of the same primitive types: `onTrim: (Int, CMTime, CMTime)`, `onTrackTrim: (Int, Int, CMTime, CMTime)`, `onReorder: (Int, Int, [any Clip])`. A swap of `leading` / `trailing` or `from` / `to` produces silent nonsense, not a compile error. Refactor-safety is zero at consumer call sites.
- **Multi-select asymmetry.** v0.9.2 shipped `TimelineView(selectedClipIDs:)` for clip multi-select, but `OverlayHost` is still single-select (`Binding<LayerID?>?`). Consumers building unified multi-select UIs hit the wall immediately. Reels-studio's v0.4 Tier 5 wrap-in-track flow worked around it via the `LayersSheet`, but proper batch overlay edits (opacity / position on N overlays at once) need parity.

A v0.10.1 micro-patch follows for snapshot + gesture test infrastructure.

### Scope lock — v0.10.0

In scope:
- **Callback payloads as `Sendable` structs.** Replace every positional callback with a single struct argument; the named-field style makes call-site swaps impossible at compile time.
- **`OverlayHost(selectedLayerIDs:)`** additive `Binding<Set<LayerID>>?` parameter. Coexists with `selectedLayerID`; render sites union-check both via a new `overlayMatchesSelection(id:single:set:)` `nonisolated public static` helper (parallel to v0.9.2's `clipMatchesSelection`).
- **Default `OverlayHost` size policy** — current 30%×30% placeholder either fixed or explicitly documented as a permanent v1.0 default.
- **Stale-comment sweep** — `TimelineView` "v0.4.1 read-only" header, `InspectorPanel` pre-v0.8 placeholders, `OverlayHost` "v1 placeholder" note.

Out of scope:
- Snapshot + gesture test infrastructure — v0.10.1 micro-patch (additive, ships fast).
- Library-level a11y sweep — v0.11.
- `@Observable` migration — v0.12 (after iOS 17 floor).

### Public API changes

```swift
// MARK: - Tier 1: Callback payloads

public struct ClipReorderEvent: Sendable {
    public let from: Int
    public let to: Int
    public let newClips: [any Clip]
}

public struct ClipTrimEvent: Sendable {
    public let clipIndex: Int
    public let leadingTrim: CMTime
    public let trailingTrim: CMTime
}

public struct TrackReorderEvent: Sendable {
    public let trackIndex: Int
    public let from: Int
    public let to: Int
    public let newClips: [any Clip]
}

public struct TrackTrimEvent: Sendable {
    public let trackIndex: Int
    public let clipIndex: Int
    public let leadingTrim: CMTime
    public let trailingTrim: CMTime
}

extension TimelineView {
    public init(
        _ video: Video,
        currentTime: Binding<CMTime>? = nil,
        selectedClipID: Binding<ClipID?>? = nil,
        selectedClipIDs: Binding<Set<ClipID>>? = nil,
        zoom: Binding<TimelineZoom>? = nil,
        // ... layout params unchanged ...
        onReorder: ((ClipReorderEvent) -> Void)? = nil,
        onTrim: ((ClipTrimEvent) -> Void)? = nil,
        onTrackReorder: ((TrackReorderEvent) -> Void)? = nil,
        onTrackTrim: ((TrackTrimEvent) -> Void)? = nil
    )
}
```

Old positional-arg init stays as a deprecated overload for one minor; bodies dispatch through the struct form.

```swift
// MARK: - Tier 2: Overlay multi-select

extension OverlayHost {
    public init(
        _ video: Video,
        currentTime: CMTime = .zero,
        selectedLayerID: Binding<LayerID?>? = nil,
        selectedLayerIDs: Binding<Set<LayerID>>? = nil
    )
}

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension OverlayHost {
    public nonisolated static func overlayMatchesSelection(
        id: LayerID?,
        single: LayerID?,
        set: Set<LayerID>?
    ) -> Bool
}
```

`onLayerTap` / `onLayerDrag` semantics unchanged — taps still write to `selectedLayerID`. Consumers handle multi-select toggling the same way reels-studio v0.4 Tier 5 did for clips.

### Tier breakdown

- **Tier 0** *(this PR)* — RFC. No code.
- **Tier 1** — Callback payload structs + `TimelineView` init refactor + deprecated overload. ~150 LOC + ~12 tests.
- **Tier 2** — `OverlayHost(selectedLayerIDs:)` + `overlayMatchesSelection` helper. ~60 LOC + ~8 tests.
- **Tier 3** — `OverlayHost` default-size decision (fix or document) + stale-comment sweep + release prep + tag v0.10.0.

### Test strategy

- **Callback structs:** body smoke per init permutation; field-by-field assertions on the emitted events; deprecated overloads still compile + emit equivalent events.
- **Overlay multi-select:** `overlayMatchesSelection` table (mirror v0.9.2's `ClipMatchesSelectionTests`); body smoke with both bindings; long-press hook (if added) routes correctly.

Target: ~20 new tests. Suite: 301 → ~321.

### Compatibility

- **Breaking** for `TimelineView` positional-arg callbacks (deprecated overload absorbs the migration window).
- **Pure additive** for overlay multi-select.
- **kadr floor** bumped to ≥ 0.11.0 (paired with the kadr v0.11 hardening cycle).

### Open questions

- **Should we backport a `*Event` struct shape to `OverlayHost.onLayerTap` / `onLayerDrag`?** Today they're single-arg (`(LayerID) -> Void` / `(LayerID, CGSize) -> Void`). Defer — single positional arg of a strongly-typed struct isn't a swap landmine. Touch only if a future field surfaces.
- **Long-press on `OverlayHost`?** RFC for v0.9.2 deferred this. The unified multi-select story now has half a leg (binding) but no driver. If reels-studio v0.6 wants overlay multi-select, it can wire it via the LayersSheet today. v0.10.1 could add `onLongPressOverlay` if a real consumer asks.

## v0.10.1 — Snapshot + gesture test infrastructure *(planned, sketch)*

Additive micro-patch following v0.10.0. Same shape as v0.9.1 / v0.9.2. Three tiers:

1. **`swift-snapshot-testing` harness** — baseline images for `TimelineView`, `KeyframeEditor`, `SpeedCurveEditor`, `OverlayHost`, `InspectorPanel`, `OverlayInspectorPanel`.
2. **Gesture-driver tests** — `onZoomSnap`, `onClipDragSnap`, `onLongPressClip`, pinch-zoom, drag-retime. ViewInspector or XCUITest-in-package.
3. **Release prep + tag v0.10.1**.

Closes audit gaps #8 and #9.

## v0.11.0 — Library accessibility sweep *(planned, sketch)*

Parallel to reels-studio v0.5's app sweep, applied to the **library** views every consumer ships. Five tiers:

1. `TimelineView` clip / transition / scrub blocks — labels, values, hints.
2. `KeyframeEditor` / `OverlayKeyframeEditor` rows — per-property labels, per-marker values.
3. `SpeedCurveEditor` + Inspector slider values + Dynamic Type pass.
4. Reduce Motion awareness on internal animations.
5. Release prep + tag v0.11.0.

Closes audit gap #7.

## v0.10.2 — Audio trim handles *(planned)*

**Status:** RFC. No code yet.

### Motivation

`TimelineView`'s audio rows already render waveform peaks (via `showAudioWaveforms`) since v0.6 — the *visual* surface is done. What's missing is the *gesture surface*: leading + trailing trim drag handles on each `AudioTrack` row, mirroring the existing handles on video clips and Track-internal clips.

Consumers can already trim audio programmatically through kadr's `AudioTrack.at(time:)` / `.duration(_:)` modifiers; what they can't do is wire a drag gesture to those modifiers from a TimelineView callback. Reels Studio v0.7 Tier 1 needs this surface to let users trim background music with a finger.

Patch cycle, not a minor — the addition is one Sendable event struct + one modifier, mirroring `TrackTrimEvent` + `onTrackTrim(_:)`.

### Scope lock — v0.10.2

In scope:
- **`AudioTrimEvent` Sendable struct** — payload mirroring `TrackTrimEvent` shape:
  ```swift
  public struct AudioTrimEvent: Sendable {
      /// Index into the host `Video`'s top-level audio track array.
      public let trackIndex: Int
      /// Leading-edge trim delta (CMTime).
      public let leadingTrim: CMTime
      /// Trailing-edge trim delta (CMTime).
      public let trailingTrim: CMTime
  }
  ```
- **`TimelineView.onAudioTrim(_:)` modifier** — single callback fired on gesture commit. Same callback shape as `onTrackTrim`. Default nil = audio rows render but don't accept the trim gesture (today's behavior).
- **Drag-handle rendering** on each `AudioTrack` lane row. Reuses the existing handle visual from the video-clip rows; the gesture path needs an audio-track-specific recogniser because the host coordinate space differs (single-row lane vs. multi-row Track).

Out of scope:
- **Audio scrubbing** (drag-through-row → seek). A separate `onAudioScrub` callback was sketched in the reels-studio v0.7 RFC; pull into v0.10.3 if needed, not v0.10.2.
- **Per-track volume scrubbing** (vertical drag on the row body). Inspector-panel surface, not timeline.
- **Crossfade-region direct manipulation.** v0.11 candidate.

### Surface

```swift
extension TimelineView {
    public func onAudioTrim(_ handler: ((AudioTrimEvent) -> Void)?) -> TimelineView
}
```

Internal: `AudioLane` (or whatever `TimelineLanes.swift` ends up calling it post-Tier 1 implementation) routes its drag-end recogniser through this callback. Same haptic / snap semantics as the video-clip trim handles already use.

### Tier breakdown

Single-tier patch — too small to split.

- Add `AudioTrimEvent` to `TimelineEvents.swift` (alongside `ClipTrimEvent` / `TrackTrimEvent`).
- Add `onAudioTrim(_:)` modifier on `TimelineView`.
- Wire the drag recogniser inside the audio-row rendering path. Reuse the existing handle visual + snap haptics from the video clip path.
- Tests: gesture-wiring smoke (modifier attached survives `.inspect()`), pure-helper tests for delta calculation, snapshot baseline for the row-with-handles render (consistent with the existing `TimelineView` snapshot test in v0.10.1's harness).

~150 LOC + ~10 tests.

### Pairs with

**reels-studio v0.7 Tier 1** which wires the callback to `ProjectStore.applyMusicTrim(_:)` / `applySFXTrim(_:)` mutations. The reels-studio cycle blocks on this patch shipping first.

### Risks

- **Gesture conflict with timeline pan.** The trim drag has to start inside the handle hot-zone — pan-to-scroll has to win when the drag begins outside it. Existing video-clip handles already solved this; we follow the same pattern.
- **`AudioTrack.explicitDuration` vs. asset-duration ambiguity.** Trimming an audio track whose duration is implicit (no `.duration(_:)` call) requires us to either (a) resolve the asset duration synchronously, or (b) emit `leadingTrim` / `trailingTrim` as relative deltas and let the consumer reconcile. We go with (b) — same shape as `ClipTrimEvent` / `TrackTrimEvent` already uses, no async surprise in the gesture path.
