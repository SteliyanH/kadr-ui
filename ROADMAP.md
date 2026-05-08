# KadrUI Roadmap

This document outlines the planned feature releases for KadrUI. Versions and timelines track Kadr's own roadmap — every kadr-ui feature consumes some part of kadr's public surface, so milestones are gated on the matching kadr release.

For Kadr's roadmap see [kadr/ROADMAP.md](https://github.com/SteliyanH/kadr/blob/main/ROADMAP.md).

## v0.4.0 — Initial release ✓ shipped

Drop-in SwiftUI components consuming Kadr's v0.4 introspection / preview primitives.

- `VideoPreview(_ video:)` — `AVKit.VideoPlayer` wrapper around `Video.makePlayerItem()`
- `ThumbnailStrip(_ video:, count:)` — horizontal strip via `Video.thumbnail(at:)`
- `OverlayHost(_ video:)` — overlay layer with built-in renderers + custom hook
- `.onLayerTap` / `.onLayerDrag` — gesture modifiers routed through `LayerID`

## v0.4.1 / v0.4.2 / v0.4.3 — TimelineView ✓ shipped

`TimelineView` arrives in v0.4.1 with selection / drag-to-reorder. v0.4.2 adds tap-and-drag scrubbing and live trim resize. v0.4.3 polishes reorder with live shifting of non-dragged clips.

## v0.4.4 — Catch-up + polish ✓ shipped

Bumps Kadr dep floor to v0.5.0. Adds `OverlayHost` time-aware visibility (`.visible(during:)`), content-mode support (`.fit` / `.fill` / `.stretch`), `ThumbnailStrip` failure callback, `VideoPreview` reload-on-change.

## v0.5.0 — Multi-Lane Timeline ✓ shipped

Catches kadr-ui up to Kadr 0.6's multi-track DSL. `TimelineView` switches to a stacked-lane render when the composition has Tracks or `.at(time:)` clips.

## v0.5.1 — Chain-aware edit gestures ✓ shipped

Reorder + trim now apply on the implicit chain lane in both chain-only and multi-track render paths. Dragging a chain clip never disturbs Tracks or free-floaters.

## v0.5.2 — Consume Kadr 0.7 surface ✓ shipped

Track lane labels honor `Track.name`; audio lane blocks honor `AudioTrack.startTime` and `AudioTrack.explicitDuration`.

## v0.5.3 — Audio waveforms ✓ shipped

`AudioWaveform` value type, `AudioWaveformLoader.load(url:sampleCount:)`, `TimelineView(showAudioWaveforms:)`. Symmetric vertical-bar render via internal `AudioWaveformShape`.

## v0.6.0 — Editor primitives ✓ shipped

Bumps Kadr dep floor to v0.8.4. Adds the SwiftUI surfaces that turn the timeline into a real editor.

- **`InspectorPanel(video:selectedClipID:)`** — tap a clip on the timeline → property panel with Transform sliders (position / rotation / scale / anchor), per-clip Filter intensity sliders, opacity slider. Callbacks shaped after `TimelineView.onTrim` / `onReorder`.
- **`KeyframeEditor(video:selectedClipID:currentTime:)`** — per-property tracks below `TimelineView`. Tap-to-add at playhead, long-press to remove, drag to retime. One row per animatable property (`.transform` / `.opacity` / `.filter(index:)`).
- **`OverlayHost` animated text preview** — when a `TextOverlay` carries a `textAnimation`, a `UIViewRepresentable` / `NSViewRepresentable` bridge runs the `[CAAnimation]` against a live `CATextLayer` so preview matches export.
- **TimelineView audio cross-fade glyphs** — two-triangles-meeting markers in audio lanes at every `AudioTrack` overlap with non-zero `crossfadeDuration`.

## v0.7.1 — Track-lane trim handles ✓ shipped

Patch closing the v0.7.0 deferral. Trim handles now render on every non-transition Track-lane clip when `onTrackTrim` is non-`nil`; drag morphs live width and fires the callback on release. No public API changes.

## v0.7.0 — Timeline zoom + Track-internal reorder ✓ shipped

Bumps Kadr dep floor to **v0.10.0**. Long compositions become usable, and Track lanes are no longer read-only.

- **`TimelineZoom`** value type + `TimelineView(zoom:)` — pinch-to-zoom and horizontal scroll over an explicit pixels-per-second density (clamped `8…400`). Without `zoom`, layout is pixel-identical to v0.4–v0.6.
- **`onTrackReorder`** + **`applyTrackReorder(track:from:to:)`** — drag-to-reorder inside `Track {}` blocks, preserving `startTime` / `name` / `opacityFactor` and travelling inner `Transition`s with their preceding clip.
- **`onTrackTrim`** callback contract — same delta semantics as `onTrim`, qualified by `trackIndex`. Trim-handle rendering on Track lanes follows in a v0.7.x patch.

## v0.8.0 — SpeedCurveEditor / CaptionEditor / OverlayInspector ✓ shipped

Closes the v0.6 deferral list. Built against the existing kadr ≥ 0.10 surface — no kadr v0.11 needed.

- **`SpeedCurveEditor`** — log2-scaled 2D keyframe editor authoring `Animation<Double>` for `VideoClip.speed(curve:)`.
- **`CaptionEditor`** — list-style cue editor over `Video.captions(_:)` with sort-on-emit and playhead-anchored set-start/end shortcuts.
- **`OverlayInspectorPanel`** — sibling to `InspectorPanel` retargeted at overlays. Common (Position / Anchor / Opacity) plus type-specific (TextOverlay text + animation, StickerOverlay rotation).
- **`OverlayKeyframeEditor`** — sibling to `KeyframeEditor` retargeted at overlay `.position` / `.size` keyframes.

Custom `TextAnimation`s round-trip as `.custom` so the picker can clear them but not re-author. Bézier control-handle UX, styled caption authoring, and multi-select on overlays remain deferred (real-but-niche).

## v0.9.0 — Fixed-center playhead + zoom-snap callback ✓ shipped

Pure additive, three tiers (one per surface + release prep). Driven by `kadr-reels-studio` v0.4's UX-polish cycle.

- **`TimelineView.fixedCenterPlayhead(_:)`** — anchors the playhead to the viewport center and scrolls content under it via `ScrollViewReader` + an invisible 1×1 anchor at the playhead's x. Opt-in modifier; no-op when `currentTime` / `zoom` aren't bound.
- **`TimelineView.onZoomSnap(_:)`** — fires on pinch-zoom crossings of `ZoomSnapThreshold.standard` (frame / second / 5s / 30s). `nonisolated public static crossings(prev:current:in:)` is the testable seam.

`OverlayHost.onLayerTap(_:)` was originally on this cycle's list but already shipped in v0.8.0 — kadr-reels-studio v0.4 Tier 6 wires against the existing surface.

## v0.9.1 — onClipDragSnap ✓ shipped

Single-surface micro-patch. `TimelineView.onClipDragSnap(_:)` fires when an in-flight reorder drag crosses an adjacent-slot boundary — the moment the dragged clip would land on a new resting position. Closes a haptic-symmetry gap discovered during `kadr-reels-studio` v0.4 Tier 3 scoping (the v0.4 RFC mistakenly claimed this surface already shipped in v0.8). Same shape for chain reorders and Track-internal reorders. `nonisolated public static snapTransition(previous:current:)` is the testable seam.

## v1.0.0 — Production Ready

Tracks Kadr v1.0.

- API stability commitment — no breaking changes without major version bump
- DocC tutorials covering each component (`VideoPreview`, `ThumbnailStrip`, `OverlayHost`, `TimelineView`, `InspectorPanel`, keyframe editor)
- Snapshot tests for the visual components (Point-Free's `swift-snapshot-testing`)
- Reference: `kadr-reels-studio` example app uses every kadr-ui component end-to-end

---

## Explicit non-goals

- **Cross-lane drag** (move a clip from chain → Track or between Tracks) — UX-heavy and the use cases are app-specific. Consumers wire their own Track-creation flow.
- **Cross-lane drag** between Tracks (move a clip from one Track to another) — Track-internal reorder shipped in v0.7.0; cross-Track moves remain UX-heavy and app-specific.
- **Custom waveform colors / shapes** — fixed white-on-block render in v0.5.3. Exposing styling waits for community demand.
- **Virtualized clip rendering at high zoom levels** — v0.7.0 ships zoom + ScrollView with full clip rendering; virtualization for very large compositions waits for community demand.

---

## Compatibility track record

| KadrUI | Requires Kadr |
|---|---|
| 0.4.0 – 0.4.3 | ≥ 0.4.0 / 0.4.1 |
| 0.4.4 | ≥ 0.5.0 *(uses `Overlay.visibilityRange`)* |
| 0.5.0 / 0.5.1 | ≥ 0.6.0 *(uses `Track`, `Clip.startTime`)* |
| 0.5.2 / 0.5.3 | ≥ 0.7.0 *(uses `Track.name`, `AudioTrack.startTime`, `AudioTrack.explicitDuration`)* |
| 0.6.0 | ≥ 0.8.0 *(uses `Transform`, `Animation<T>`, animated `TextOverlay`, `AudioTrack.crossfadeDuration`)* |
| 0.7.0 / 0.7.1 | ≥ 0.10.0 *(uses `Track.opacityFactor`)* |
| 0.8.0 | ≥ 0.10.0 |
| 0.9.0 | ≥ 0.10.0 |
| 0.9.1 | ≥ 0.10.0 |
| 1.0.0 *(planned)* | ≥ 1.0.0 |

## Contributing

Want to help build the next version? Open an issue on this repo or on [kadr](https://github.com/SteliyanH/kadr) for upstream feature requests.
