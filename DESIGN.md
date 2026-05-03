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
