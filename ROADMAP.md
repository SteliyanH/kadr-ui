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

## v0.6.0 — Editor primitives

Depends on **kadr v0.8.0** (per-clip Transform, keyframe animations, animated TextOverlay). Adds the SwiftUI surfaces that turn the timeline into a real editor.

- **`InspectorPanel(video:selectedClipID:)`** — tap a clip on the timeline → property panel with Transform sliders (position / rotation / scale / anchor), per-clip Filter intensity sliders, opacity slider. Wires through callbacks the same way `TimelineView.onTrim` / `onReorder` do.
- **Keyframe editor surface** — per-property tracks rendered below `TimelineView`, tap to add/remove keyframe markers. Drives a binding-based callback for the consumer to rebuild the `Video` with new `Animation<T>` values.
- **`OverlayHost` animated text preview** — when a `TextOverlay` carries `[CAAnimation]`, the SwiftUI bridge view runs the animations live so preview matches export.
- **TimelineView audio cross-fade glyphs** — small triangle / hourglass markers in audio lanes where two adjacent `AudioTrack`s overlap. Hooks into the kadr v0.8 cross-fade surface.

## v0.7.0+ — Speed curve UI / caption editor

Depends on **kadr v0.9.0**.

- Speed-curve editor — visual Bézier curve editor on a selected `VideoClip`, drives `VideoClip.speed(curve:)` callback
- Caption editor — text + timing UI for the `kadr-captions` surface (or kadr v0.9's caption types if rolled into core)

## v1.0.0 — Production Ready

Tracks Kadr v1.0.

- API stability commitment — no breaking changes without major version bump
- DocC tutorials covering each component (`VideoPreview`, `ThumbnailStrip`, `OverlayHost`, `TimelineView`, `InspectorPanel`, keyframe editor)
- Snapshot tests for the visual components (Point-Free's `swift-snapshot-testing`)
- Reference: `kadr-reels-studio` example app uses every kadr-ui component end-to-end

---

## Explicit non-goals

- **Cross-lane drag** (move a clip from chain → Track or between Tracks) — UX-heavy and the use cases are app-specific. Consumers wire their own Track-creation flow.
- **Editing inside `Track {}` blocks** — reorder/trim on Track-internal clips is staged for v0.6.x at earliest; needs the kadr v0.8 Transform surface to feel right.
- **Custom waveform colors / shapes** — fixed white-on-block render in v0.5.3. Exposing styling waits for community demand.
- **Zoom + horizontal scroll on TimelineView** — practical for long compositions but adds enough state machinery (visible time range, virtualized clip blocks) that it's better as its own milestone.

---

## Compatibility track record

| KadrUI | Requires Kadr |
|---|---|
| 0.4.0 – 0.4.3 | ≥ 0.4.0 / 0.4.1 |
| 0.4.4 | ≥ 0.5.0 *(uses `Overlay.visibilityRange`)* |
| 0.5.0 / 0.5.1 | ≥ 0.6.0 *(uses `Track`, `Clip.startTime`)* |
| 0.5.2 / 0.5.3 | ≥ 0.7.0 *(uses `Track.name`, `AudioTrack.startTime`, `AudioTrack.explicitDuration`)* |
| 0.6.0 *(planned)* | ≥ 0.8.0 *(uses `Transform`, `Animation<T>`, animated `TextOverlay`)* |
| 0.7.x *(planned)* | ≥ 0.9.0 |
| 1.0.0 *(planned)* | ≥ 1.0.0 |

## Contributing

Want to help build the next version? Open an issue on this repo or on [kadr](https://github.com/SteliyanH/kadr) for upstream feature requests.
