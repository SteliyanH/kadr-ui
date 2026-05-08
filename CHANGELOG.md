# Changelog

All notable changes to KadrUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.9.2] - 2026-05-08

Two-surface micro-patch driving `kadr-reels-studio` v0.4 Tier 5 (Track creation UI — "wrap selection in track"). Same shape as v0.9.1's micro-patch.

### Added

- **`TimelineView(..., selectedClipIDs: Binding<Set<ClipID>>?)`** — additive init parameter for multi-select. Coexists with the v0.6 `selectedClipID:`; render sites (`videoRow`, `imageRow`, `transitionRow`, Track-lane `trackItemBlock`, chain interior render) union-check both bindings via the new helper. Tap behavior is unchanged — taps continue writing to `selectedClipID`; the consumer routes multi-select via `onLongPressClip` + tap-toggle into the set.
- **`TimelineView.onLongPressClip(_:)`** — modifier; fires on a 0.5s long-press of any media clip with a non-nil `clipID`. Composes with the existing tap via `.simultaneousGesture`. The 10-pt minimum-distance reorder drag (`DragGesture(minimumDistance: 10)`) still takes precedence — long-press fires only when the user holds without dragging. Symmetric across chain + Track lanes via the internal `longPressed(_:id:)` helper.
- **`TimelineView.clipMatchesSelection(id:single:set:)`** — `nonisolated public static`. The union rule: nil id never matches; otherwise true if `single == id` or `set.contains(id)`. Pure helper; consumers can reuse it for synchronized custom rendering.

### Tests

- 11 new tests: `ClipMatchesSelectionTests` (7) + `MultiSelectAndLongPressModifierTests` (4). Suite: 290 → 301.

### Notes

- **Long-press duration** is fixed at 0.5s (SwiftUI's default). A `minimumDuration:` overload can land in v0.9.x if reels-studio v0.4 manual QA flags the timing.
- **Long-press on `OverlayHost`** — symmetric surface for overlay multi-select — was discussed and explicitly deferred. Overlays are flat-z-ordered (the Layers sheet shows everything), not lane-positioned, so the use case is weaker. Track if requested.
- **Multi-select drag reorder** (move an arbitrary subset as one block) is out of scope; kadr's `Video` builder doesn't model "swap these N clips into block X".

## [0.9.1] - 2026-05-08

Single-surface micro-patch closing a haptic-symmetry gap discovered during `kadr-reels-studio` v0.4 Tier 3 scoping. The v0.4 RFC mistakenly claimed `TimelineView.onClipDragSnap` already shipped in v0.8 (parallel to the `OverlayHost.onLayerTap` errata); verification showed it never did.

### Added

- **`TimelineView.onClipDragSnap(_:)`** — fires when an in-flight reorder drag crosses an adjacent-slot boundary, the moment the dragged clip would land on a new resting position if released. Same callback fires for chain reorders (when `onReorder` is bound) and Track-internal reorders (when `onTrackReorder` is bound). No payload — consumers fire haptics from here.
- **`TimelineView.snapTransition(previous:current:)`** — `nonisolated public static`. Encodes the change-detection rule the gesture-side fire path uses: first observation latches without firing; same target is silent; change to a different target fires once; direction-symmetric.

### Tests

- 7 new tests: `OnClipDragSnapTests` (5 pure-logic + 2 modifier smoke). Suite: 283 → 290.

### Notes

- Implementation reuses the existing `computeTargetIndex(...)` helper that already drove `.onEnded` reorder placement; `onChanged` now consults it on every drag tick. State tracks last-fired target via two `@State` fields (chain + Track), reset on gesture end.
- Index-bearing overload (`onClipDragSnap((Int) -> Void)`) deferred until a real consumer surfaces a use case for the target index.

## [0.9.0] - 2026-05-08

Two-surface mid-cycle patch driven by `kadr-reels-studio` v0.4's UX-polish cycle. Same shape as the kadr v0.10.1 patch landed mid-v0.3. Pure additive across both surfaces; the `TimelineView(...)` init is untouched.

### Added

- **`TimelineView.fixedCenterPlayhead(_:)`** — anchors the playhead to the horizontal center of the viewport and scrolls the timeline content under it, instead of letting the playhead drift toward the right edge as time advances. CapCut / VN / iMovie pattern. Implemented by wrapping the existing `ScrollView` in a `ScrollViewReader` with an invisible 1×1 anchor positioned at the playhead's x; `proxy.scrollTo(_:anchor: .center)` re-emits on every `currentTime` change with a 0.15s easeOut. Three no-op fallbacks: `currentTime` nil → playhead doesn't render anyway; `zoom` nil → no ScrollView at all; `enabled: false` → identical to legacy behavior.
- **`TimelineView.onZoomSnap(_:)`** — fires when pinch-zoom crosses a perceptible density breakpoint. Wired through the existing `zoomGesture.onChanged`: captures `prev` before applying `TimelineZoom.clamp`, runs `ZoomSnapThreshold.crossings(prev:current:in:)` against `.standard`, fires once per crossed threshold per gesture update. No emission when `prev == current` (stays inside one bracket — the steady-state pinch case). Direction-symmetric.
- **`ZoomSnapThreshold`** — `Sendable, Hashable` struct with `pixelsPerSecond: Double` + `label: String`. `.standard: [ZoomSnapThreshold]` ships the v0.9.0 list (frame at 30fps / 1s / 5s / 30s; densest first by `pixelsPerSecond`). Picked from CapCut / VN feel-tuning.
- **`ZoomSnapThreshold.crossings(prev:current:in:)`** — `nonisolated public static`. Returns thresholds strictly between `prev` and `current` (open interval; landing exactly on a value doesn't count). No emission when `prev == current`.

### Tests

- 20 new tests across the cycle: `FixedCenterPlayheadTests` (7), `ZoomSnapThresholdTests` (10), `OnZoomSnapModifierTests` (3). Suite: 263 → 283.

### Notes

- `OverlayHost.onLayerTap(_:)` was originally listed in the v0.9 RFC scope but already shipped in v0.8.0 (alongside `OverlayInspectorPanel`). Dropped from this cycle without a replacement — `kadr-reels-studio` v0.4 Tier 6 wires against the existing v0.8 surface.
- **Snap-to-threshold settle** (gesture *settles* at the nearest threshold on `onEnded`) and **custom threshold lists** are deferred to a v0.9.x patch — RFC noted both as low priority until reels-studio v0.4 manual QA flags either as a feel gap.

## [0.8.0] - 2026-05-03

Three editor surfaces deferred since v0.6, all built against kadr's existing public surface (no kadr v0.11 needed). Closes the demo-critical gaps that were blocking kadr-reels-studio from being a complete editor walkthrough — speed authoring, caption editing, and overlay property + keyframe editing.

### Added

- **`SpeedCurveEditor`** — visual 2D keyframe editor for ``Kadr/VideoClip/speed(curve:)``. Time on the x-axis (clip-relative, anchored to `trimRange.duration`); speed multiplier on a log2-scaled y-axis (`0.25× ... 4×`, `1.0` rendered as a baseline gridline so equal-ratio deltas are equidistant). Tap empty area → add keyframe; drag marker → retime + rescale; long-press → remove. Picker for `TimingFunction` (Linear / Ease In / Ease Out / Ease In Out — Cubic Bézier and Custom intentionally absent, consumers wanting either pass via `clip.speed(curve:)` directly). Optional `currentTime` binding overlays a playhead. Read-only model: `onUpdate: (Animation<Double>?) -> Void` fires on every commit; consumer rebuilds the clip.
- **`CaptionEditor`** — list-style cue editor for ``Kadr/Video/captions(_:)``. Each row exposes a multi-line text field, start / end timestamps, "→" set-to-playhead shortcuts (when `currentTime` is bound), and a delete button. Cues outside `[0, compositionDuration]` get a red border + warning glyph (not silently dropped). Trailing **+ Add cue** appends a 2-second cue starting at the playhead (or composition midpoint), clamped so the default window stays inside the composition where possible. Sort-on-emit (no in-place reorder); stable for ties.
- **`OverlayInspectorPanel`** — sibling to v0.6 ``InspectorPanel`` retargeted at overlays. Common rows (Position X/Y, Anchor, Opacity) for every overlay; type-specific rows for ``Kadr/TextOverlay`` (text field + ``Kadr/TextAnimation`` preset picker — None / Fade In / Slide In × 4 directions / Scale Up; consumer-built animations round-trip as `.custom`) and ``Kadr/StickerOverlay`` (rotation slider). ``Kadr/ImageOverlay`` (and ``Kadr/Video/watermark(_:position:size:opacity:)`` instances — same type, just `layerID == "watermark"`) get common-only.
- **`OverlayKeyframeEditor`** — sibling to v0.6 ``KeyframeEditor`` retargeted at overlays. Property rows for ``Kadr/ImageOverlay`` / ``Kadr/StickerOverlay``: `.position`, `.size`. ``Kadr/TextOverlay`` produces zero rows (kadr's text overlays use the enum-driven ``Kadr/TextAnimation`` instead of `Animation<Position>` / `Animation<Size>`). Composition-relative time mapping (matching kadr's overlay-animation semantics — distinct from the clip-relative `KeyframeEditor`). Same gesture model: tap-to-add at playhead, long-press marker to remove, drag to retime.
- **`OverlayProperty`** — `.position` / `.size` enum surfaced as ``OverlayKeyframeEditor`` row identifiers.
- **`OverlayTextAnimationKind`** — picker round-trip enum for the Text-overlay animation surface. `.none` / `.fadeIn` / `.slideIn(direction:)` / `.scaleUp` / `.custom`.
- Pure helpers exposed `nonisolated public static`: `SpeedCurveEditor.{clampMultiplier, normalizedY, multiplier(forNormalizedY:), point, locationToKeyframe, draggedKeyframe, keyframesByAdding/Removing/Replacing, timingPresets, timingLabel}`; `CaptionEditor.{sortedByStart, isValidCueRange, defaultNewCueStart, cueRange}`; `InspectorPanel.{overlayFor, textAnimationKind, textAnimation(forKind:)}`; `OverlayInspectorPanel.{animationPresets, animationPickerIndex}`; `OverlayKeyframeEditor.{propertyOptions, keyframesForProperty, label}`.

### Tests

- 75 new tests across the cycle: `SpeedCurveEditorTests` (30), `CaptionEditorTests` (18), `OverlayInspectorTests` (27). Suite: 188 → 263.

### Notes

- **Scope decision: RFC said init overloads, ships as sibling types.** RFC #60 promised the overlay surfaces as init overloads on `InspectorPanel` / `KeyframeEditor`. In implementation, splitting bodies between separate View structs is cleaner than stuffing two distinct edit modes into one — the new public types `OverlayInspectorPanel` and `OverlayKeyframeEditor` carry identical callback ergonomics.
- **Bézier control-handle UX**, **styled caption authoring**, and **multi-select on overlays** stayed deferred (real-but-niche, not on the demo critical path). Custom `TextAnimation`s round-trip safely as `.custom` so consumer-built animations aren't silently lost.
- **`MagnificationGesture`** is still in use to keep the iOS 16 deployment floor (deprecated on iOS 17+ but functional).
- Caught and fixed a Swift 6 strict-concurrency SIGTRAP during initial Tier 1 testing — array-filter closures in static helpers needed `nonisolated` annotation. Lesson logged for v1.0 audit.

## [0.7.1] - 2026-05-03

Track-lane trim handle rendering — closes the deferral from v0.7.0. Pure additive; the `onTrackTrim` callback contract from v0.7.0 is unchanged.

### Added

- **Track-lane trim handles** — thin grab handles render on the leading and trailing edges of every non-transition Track-lane clip when `onTrackTrim` is non-`nil`. Drag morphs the clip's live width (the slot's reserved width stays fixed so neighbors don't reflow); on release fires `onTrackTrim(trackIndex, clipIndex, leadingTrim, trailingTrim)` with the same `CMTime` delta semantics as the chain `onTrim`. State machinery and trim math are isolated from the chain path — independent in-flight drags don't interfere.

### Notes

- No public API changes. v0.7.0 call sites pick up handle rendering automatically when they pass `onTrackTrim`.

## [0.7.0] - 2026-05-03

Timeline zoom + editing inside `Track {}` blocks. Long compositions are now usable (pinch to zoom, horizontal scroll), and Track lanes are no longer read-only — drag a clip inside a Track to reorder it.

Bumps the Kadr dep floor to **0.10.0** (uses `Track.opacityFactor` to preserve per-track opacity through reorder).

### Added

- **`TimelineZoom`** value type — explicit pixels-per-second density with clamped bounds (`8…400`). Helpers: `init(pixelsPerSecond:)` (clamps), `fitToWidth(_:totalSeconds:)` (defensive against zero / out-of-range), `zoomed(by:)`, `clamp(_:)`. `Sendable + Equatable`.
- **`TimelineView(zoom:)`** init param — when bound, `pxPerSecond` is sourced from the binding and content is wrapped in a horizontal `ScrollView`. A `MagnificationGesture` (iOS 16 / macOS 13 floor) writes the zoom back; the gesture captures a pre-pinch baseline on first `onChanged` so updates multiply from a stable base instead of compounding. Without `zoom`, layout is pixel-identical to v0.4–v0.6.
- **`TimelineView.applyTrackReorder(track:from:to:)`** pure helper — rebuilds a `Kadr.Track` with reordered inner clips while preserving `startTime`, `name`, and `opacityFactor`. Inner `Transition`s travel with their preceding clip — same rule as the implicit chain.
- **`onTrackReorder(trackIndex:from:to:newClips:)`** callback on `TimelineView` — wires drag-to-reorder gestures on Track lane items. Emits the full rebuilt `video.clips` so consumers reconstruct `Video {}` directly.
- **`onTrackTrim(trackIndex:clipIndex:leadingTrim:trailingTrim:)`** callback on `TimelineView` — same delta semantics as `onTrim`, qualified by `trackIndex`. Callback contract is stable in v0.7; trim-handle rendering on Track lanes follows in a v0.7.x point release.

### Tests

- 24 new tests across the cycle: `TimelineZoomTests` (16) — clamping, fit-to-width math, equality, body smoke; `TimelineLanesTests` extensions (6) — `applyTrackReorder` reorder + invariants; `TimelineViewTests` extensions (2) — track-callback smoke. Suite: 164 → 188.

### Notes

- Track-lane editing surface ships in two stages — reorder lands in 0.7.0; track-lane trim handles arrive in a 0.7.x patch alongside the already-shipped `onTrackTrim` contract (no API churn at the consumer).
- `MagnificationGesture` is deprecated on iOS 17+ in favor of `MagnifyGesture`, but switching would raise the deployment floor; keeping the iOS 16 floor is the higher-priority constraint.
- Speed-curve UI and caption editor remain deferred (gated on Kadr v0.11 surface area).

## [0.6.0] - 2026-04-29

Editor primitives. KadrUI catches up to Kadr 0.8 (Transform / Animation / animated `TextOverlay`) and ships the SwiftUI surfaces that turn the timeline into a real editor: a per-clip property panel, a per-property keyframe track, an animated text preview path that matches export, and audio cross-fade indicators on the timeline.

Bumps the Kadr dep floor to **0.8.4** (uses `Transform`, `Animation<T>`, `TextAnimation`, `AudioTrack.crossfadeDuration`, and the `gaussianBlur` / `vignette` / `sharpen` / `zoomBlur` / `glow` filter presets).

### Added

- **`InspectorPanel`** — sliders for the v0.8 per-clip surface. Position X/Y, rotation, scale, anchor (Transform), opacity, and an intensity slider for each animatable filter on the selected clip. Edits surface through callbacks shaped after `TimelineView.onTrim` / `onReorder` — `InspectorPanel` never mutates the (immutable) `Video`. Pure helpers exposed: `clipFor(id:in:)`, `normalizedXY(of:)`, `scalar(of:)`, `range(of:)`, ordered `allAnchors`, label helpers for `Anchor` and `Filter`.
- **`KeyframeEditor`** — per-property keyframe track surface that pairs with `TimelineView` via the existing `selectedClipID` binding. One row per animatable property of the selected clip (`.transform` / `.opacity` / `.filter(index:)`), markers placed at clip-relative keyframe times. **Tap** an empty row → `onAdd` at the playhead (mapped to clip-relative via `clipStartTime`). **Long-press** a marker → `onRemove`. **Drag** a marker horizontally → `onRetime` on release. Pure helpers: `propertyOptions(for:)`, `keyframesForProperty(_:on:)`, `clipStartTime(for:in:)`. New public type `KeyframeProperty`.
- **Animated `TextOverlay` preview in `OverlayHost`** — when a `TextOverlay` carries a `textAnimation`, `OverlayHost` routes through a `UIViewRepresentable` / `NSViewRepresentable` bridge hosting a `CATextLayer` and runs `TextAnimation.makeAnimations(for:)` against the live layer so preview matches export. Begin-time remap shifts each animation's `beginTime` by `CACurrentMediaTime() - AVCoreAnimationBeginTimeAtZero` so playthroughs start now while preserving positive offsets relative to t=0.
- **`TimelineView` audio crossfade glyphs** — every overlapping `AudioTrack` pair where at least one side carries a non-zero `crossfadeDuration` shows a small two-triangles-meeting marker at the overlap midpoint on every audio lane. Visual-only, non-interactive. Tracks without `explicitDuration` are skipped (UI can't compute the end time without an async asset load).

### Tests

- 45 new tests across the cycle: `InspectorPanelTests` (15), `KeyframeEditorTests` (15), `AnimatedTextLayerViewTests` (7), `CrossfadeBoundariesTests` (8). Suite: 119 → 164.

### Notes

- `OverlayHost` public surface is unchanged — the bridge is internal; the only behavior change is that animated `TextOverlay`s now animate in preview.
- The crossfade glyph style is fixed in v0.6.0 (white-on-lane, two-triangles-meeting). Custom styling waits for community demand.
- `KeyframeEditor`'s clip-relative time mapping handles top-level chain clips and free-floaters; clips inside `Track {}` blocks fall back to the track's start time (no per-inner accumulation).
- Inspector-for-overlays, speed-curve UI, and caption editor are deferred to v0.7+ alongside the Kadr v0.9 surface they depend on.

## [0.5.3] - 2026-04-28

Audio waveforms in `TimelineView`. Closes the v0.5.x deferred item from the multi-lane RFC. Pure additive — every v0.5.2 call site renders identically; waveforms only appear when callers opt in via `showAudioWaveforms: true`.

### Added

- **`AudioWaveform`** value type — a fixed-length array of normalized peak values suitable for rendering as bars or a polyline. `Sendable` + `Equatable`.
- **`AudioWaveformLoader.load(url:sampleCount:)`** — async loader that reads PCM samples via `AVAssetReader`, downmixes multi-channel sources to mono, bucket-peaks into the target sample count, and normalizes so the max peak is `1.0`. Defensive on unreadable assets / asset-with-no-audio (returns `.empty`).
- **`TimelineView(showAudioWaveforms:)`** — new init param (default `false`). When true, audio lane blocks render a symmetric vertical-bar waveform centered on the block's midline. Loader runs once per audio URL via an internal `@State` cache; survives clip-state changes, reloads only when the audio-track URL list changes.
- Internal `AudioWaveformShape` SwiftUI `Shape` for the bar render. Bucket-decimates the peak array down to the rect's pixel-column count so visuals stay crisp regardless of lane width.

### Tests

- 9 new tests covering the bucketing math (empty input, zero-bucket-count, padding, abs-magnitude, non-divisible-counts, all-zero normalization, scale-to-one, shape preservation, value-type equality) plus 1 smoke test for `TimelineView(showAudioWaveforms: true)`. Suite: 108 → 119.

### Notes

- Waveform loading is async and can take several hundred ms on long assets. The `.task(id:)` driving the load fires once per audio-URL set change, not per body re-eval.
- Custom waveform colors / shapes are not exposed in v0.5.3 — `TimelineView` uses a fixed white-on-block fill. A future minor version may expose styling if there's demand.

## [0.5.2] - 2026-04-28

Catch-up to Kadr 0.7. `TimelineView` now consumes `Track.name` for real lane labels and honors `AudioTrack.at(time:)` / `.duration(_:)` for time-aware audio lanes. Pure additive; every v0.5.1 call site renders identically to before — only previously-unreachable surface (named Tracks, time-pinned audio) changes.

### Changed

- **Track lane label** — `assignLanes` now passes `track.name` through to `LaneKind.track(label:)` instead of always nil. Previously `TimelineView` fell back to "Track 1" / "Track 2" auto-generated labels for every named or unnamed Track. Now named Tracks surface their real label; unnamed ones still get the auto-generated number.
- **Audio lane timing** — audio lanes now use `audio.startTime ?? .zero` for the lane block's start and `audio.explicitDuration ?? compositionEnd` for its duration (clamped to the composition end). Previously every audio lane spanned the full composition. Audio tracks pinned past the composition end render as zero-duration blocks (matches the engine, which skips them at export).

### Added

- Bumped Kadr dep floor to `0.7.0`.

### Tests

- 6 new tests across `TimelineLanesTests` covering both Track-name shapes (named, unnamed) and four audio-timing shapes (explicit start + duration, capped-to-composition-end, past-end-zero-duration, no-timing default-to-full). Suite: 102 → 108.

## [0.5.1] - 2026-04-28

Closes the v0.5.0 deferral on edit gestures in multi-track compositions. `TimelineView`'s reorder + trim now apply to the implicit chain lane in **both** chain-only and multi-track render paths — dragging a chain clip leaves Tracks and free-floaters in their original `video.clips` positions.

### Added

- `TimelineView.chainIndices(in:)` and `TimelineView.applyChainReorder(clips:from:to:)` — `nonisolated` static helpers that reorder only chain items, preserving Tracks and free-floaters at their original full-array positions.
- Multi-lane render now uses an editable HStack for the chain lane (lane 0). Reorder + trim work the same as v0.4.x — drag a chain clip, drop it, the consumer rebuilds the `Video` from the callback's `newClips`. Other lanes (Tracks, free-floaters, audio) remain read-only as in v0.5.0.

### Changed

- Reorder math (`computeTargetIndex`, `clipReorderOffset`, `reorderAnimationKey`, `handleReorder`) now operates in chain-position space internally and translates to/from original-array indices at the gesture-handler boundary. Chain-only mode is identical to v0.5.0 (chainIndices == video.clips.indices); multi-track gains correct chain-aware behavior.
- All `internal static` helpers in `TimelineView` are now explicitly `nonisolated`. Required so the new chain-aware code paths can call them from `nonisolated` contexts; same `View`-MainActor inheritance gotcha that bit Tier 1.

### Tests

- 7 new (5 `chainIndices` / `applyChainReorder` cases + 1 multi-track edit-callbacks smoke + 1 transition-travels-with-source case). Suite: 95 → 102.

## [0.5.0] - 2026-04-28

Multi-lane `TimelineView` for Kadr 0.6 multi-track compositions. Built across four tiered PRs per the [DESIGN.md](DESIGN.md#v05--multi-lane-timeline) RFC. Pure additive — every v0.4.x chain-only call site continues to compile and renders pixel-identical to v0.4.x.

**Compatibility:** requires Kadr ≥ 0.6.0 (uses `Track`, `Clip.startTime`).

### Added — Lane assignment helpers ([#30](https://github.com/SteliyanH/kadr-ui/pull/30))

- Package-internal lane types: `LaneKind`, `LaneItem`, `ItemKind`. `Equatable` + `Sendable`.
- `TimelineView.assignLanes(for:includeAudio:)` — pure helper mapping a `Video` into ordered lanes. Lane order: implicit chain → tracks (declaration order) → free-floater rows (greedy-packed) → audio.
- `TimelineView.packFreeFloaters(_:)` — greedy interval-packs free-floaters into the minimum non-overlapping rows. Edge-touching ranges share a row.
- New static helpers are explicitly `nonisolated` (the `View`-conformance MainActor inheritance otherwise traps inside `compactMap` closures during isolation checks).

### Added — Multi-lane render ([#31](https://github.com/SteliyanH/kadr-ui/pull/31))

- New `TimelineView` init params `laneHeight: CGFloat = 40` and `laneSpacing: CGFloat = 4`. Defaults match v0.4.x chain row sizing.
- `TimelineView.body` branches on `assignLanes(...)`: a chain-only composition takes the v0.4.x render path unchanged (pixel-identical, edit gestures preserved); a multi-track composition (Tracks or `.at(time:)` clips) takes a new multi-lane render with read-only lane rows positioned on a shared time axis.
- `compositionDuration()` consults the lane assignment, so the time axis spans the full multi-track composition. Chain-only result is identical to v0.4.x.
- Selection (`selectedClipID`) honors `ClipID` on any lane in the multi-lane render — tap a clip on a Track lane or free-floater lane to update the binding.

### Added — Audio lanes ([#32](https://github.com/SteliyanH/kadr-ui/pull/32))

- New `TimelineView` init param `showAudioLanes: Bool = true`. Default matches v0.4.x; pass `false` to hide audio in either render path.
- Multi-lane render now includes audio tracks as additional lanes — one lane per `Video.audioTracks` entry, sized to composition duration.
- Branch decision uses non-audio lane count, so a chain-only Video with audio still takes the v0.4.x single-lane render.

### Added — Polish + docs

- New `TimelineView` init param `showLaneLabels: Bool = false`. When `true`, each non-chain lane renders a small label at top-left ("Track 1", "Floaters", filename for audio).
- Static helper `TimelineView.laneLabel(for:)` (package-internal) for unit-testing label semantics.
- DocC catalog and `TimelineView` header updated with multi-lane behavior.
- README compatibility table updated; components row mentions multi-lane.
- `Examples/SimpleViewer` ships a new `MultiTrackViewerView` demonstrating the lane stack against a Kadr 0.6 multi-track Video.
- CI workflow brought into byte-parity with the kadr repo (`on:` branch list).

### Tests

- 28 new tests across `TimelineLanesTests` (lane assignment + packing + label helpers) and `TimelineViewTests` (constructor + multi-track body smoke). Suite: 67 → 95.

### Deferred to v0.5.x

- **Edit gestures (reorder, trim) only apply on the chain-only render path.** Multi-track compositions render every lane read-only in v0.5.0 — including the implicit chain. The DESIGN-doc commitment "edit gestures preserved on lane 0" is honored on the chain-only short-circuit only. Index-translation between the full `video.clips` array and the chain sub-array is staged into a v0.5.x edit-in-multi-track follow-up.
- Cross-lane drag, in-Track editing, audio waveforms, zoom + scroll, nested-Track expanded visualization. All explicitly out of scope per RFC.

## [0.4.4] - 2026-04-27

Catch-up + polish patch. Bumps the Kadr dep floor to `0.5.0` so the new components in this release can lean on Kadr 0.5's `Overlay.visibilityRange`. Pure additive — every v0.4.3 call site continues to compile.

### Added — Catch-up to Kadr 0.5

- **`OverlayHost` time-aware visibility.** New `currentTime: CMTime?` parameter on the `OverlayHost` initializer. When non-`nil`, overlays whose `Overlay.visibilityRange` does not contain `currentTime` are skipped. Untimed overlays (and `currentTime == nil`) render unconditionally. Wire to your `AVPlayer.currentItem` periodic time observer to match the export's overlay timing.
- **Static helper `OverlayHost.isVisible(overlay:at:)`** for unit-testing the gating logic in isolation.

### Added — Polish

- **`OverlayHost` content-mode support.** New `contentMode: ContentMode` parameter (`.fit` default, `.fill`, `.stretch`). `.fit` lets a parent host the overlay layer without pinning the aspect ratio — overlays now appear inside the letterboxed display rect, not in the bands. `.stretch` matches pre-v0.4.4 behavior for callers using `.aspectRatio(...)` on the parent. Static helper `OverlayHost.containerFrame(...)` is exposed (package-internal) for unit tests.
- **`ThumbnailStrip` failure surfacing.** New `onThumbnailFailure: ((Int, Error) -> Void)?` parameter mirrors `VideoPreview.onLoadFailure`. Slot still falls back to the gray placeholder; the callback fires with the slot index and underlying error so consumers can log or retry.
- **`VideoPreview` reload-on-change.** Replaces a latent bug where swapping the `Video` left the player bound to the first composition. The `.task` now keys off a coarse fingerprint over `clips.count` / `overlays.count` / `audioTracks.count` / `duration`. New `reloadToken: AnyHashable?` parameter for callers who edit a clip in-place and need explicit reload (the structural fingerprint can't catch e.g. `trimRange` changes that don't shift counts).

### Tests

- 11 new tests across `OverlayHostHelpersTests` (visibility gating + content-mode math) and additive constructor checks on `OverlayHostTests`, `ThumbnailStripTests`, `VideoPreviewTests`. Suite: 56 → 67.

### Compatibility

- **Requires Kadr ≥ 0.5.0** (was 0.4.0). The dep floor moves up because `OverlayHost.isVisible` reads `Overlay.visibilityRange`, added in Kadr 0.5.
- No breaking changes to existing call sites. `OverlayHost(video)` and `OverlayHost(video) { ... }` continue to compile and behave as before — except `OverlayHost(video)` now defaults to `.fit`. Callers that previously relied on `.aspectRatio(...)` on the parent will see identical layout (matching aspect → `.fit` and `.stretch` produce the same frame). Callers that did not pin the aspect ratio will see overlays correctly aligned to the video for the first time; if you want the old (misaligned) behavior, pass `contentMode: .stretch`.

## [0.4.3] - 2026-04-27

Final UX polish on `TimelineView`. Closes the v0.4.x deferred-polish list. No API changes; still requires Kadr ≥ 0.4.1.

### Changed ([#24](https://github.com/SteliyanH/kadr-ui/pull/24))

- **Live shifting of non-dragged clips during reorder.** Promised in #14 (*"other clips stay put for v1 (no live shifting)"*). Clips between source and projected target now slide horizontally to make space — `groupWidth` left when source moves right, `groupWidth` right when source moves left. Snap shifts use `.animation(.snappy(duration: 0.18))` keyed off the projected target index, so the transition fires only on slot crossings, not on every drag pixel.
- **The source's trailing transition now travels with the source during drag.** Latent visual bug from #14 — when the source had `groupSize == 2`, the transition glyph stayed put while the source floated, then jumped to its new position only on release. It now offsets by `dragOffset` alongside the source for the full drag.

### Tests

- 6 new tests across `TimelineViewTests` covering the new `reorderShiftOffset` static helper (source-itself-zero, move-right / move-left intermediate shifts, no-movement, `groupSize=2` cases). Suite: 50 → 56.

### Known limitations

- The `Range.reduce(CGFloat(0)) { ... }` form segfaulted Swift Testing's runner under `--filter` while writing this PR; replaced with an explicit `for`-loop. Possibly a runner/compiler quirk; flagged here in case anyone hits it.

## [0.4.2] - 2026-04-27

UX polish on `TimelineView`. Two deferred items from the v0.4.1 cycle land here. Zero API breakage; the `currentTime` binding becomes bidirectional and a live-resize behavior is added during trim drags.

### Changed

- **Live trim resize** ([#19](https://github.com/SteliyanH/kadr-ui/pull/19)) — during a trim handle drag, the dragged clip's visible width updates in real time and other clips don't reflow. The slot's reserved width stays constant; only the inner content morphs (extending past the slot if needed). On release the consumer rebuilds and slot widths recompute. Fulfills the "live resize is deferred to v0.4.2 polish" promise from #15.
- **Tap-and-drag scrubbing** ([#20](https://github.com/SteliyanH/kadr-ui/pull/20)) — `currentTime: Binding<CMTime>?` is now bidirectional. When non-`nil`, a thin scrub strip renders above the clip lane with a small triangular playhead marker. Tapping or dragging anywhere in the strip writes a clamped time back to the binding. `DragGesture(minimumDistance: 0)` so a stationary tap also seeks. Consumers wire the binding's `.onChange` to seek their `AVPlayer`. Fulfills the "scrubbing-by-tap is reserved for a future PR" promise from #12.

### Tests

- 11 new tests across `TimelineViewTests` covering live trim metrics (5) and scrub-time conversion (6). Pure static helpers (`liveTrimMetrics`, `scrubTime`) factored out alongside the existing `computeTargetIndex` / `applyReorder` / `computeTrimDeltas`. Suite: 39 → 50.

### Known deferred to v0.4.3 (or later)

- Live shifting of non-dragged clips during reorder (so the dragged clip displaces neighbors visually as it crosses them). The current behavior — dragged clip floats with `zIndex(1)`, others stay put — is functional but less polished. Per the v0.4.2 plan agreed at the start of the cycle.

## [0.4.1] - 2026-04-27

Adds `TimelineView` — the visual timeline component originally deferred from v0.4.0, now landing as the v0.4.1 feature release. Built up across four small PRs: read-only render → selection → reorder → trim. Requires Kadr ≥ 0.4.1 for the new `ClipID` type.

### Added

- **`TimelineView(_ video:, currentTime:, selectedClipID:, onReorder:, onTrim:)`** — visual horizontal timeline visualizing a Kadr ``Video`` composition. Each capability is independently opt-in; pass `nil` for any callback / binding you don't need.

  - **Read-only layout** ([#12](https://github.com/SteliyanH/kadr-ui/pull/12)) — clips render as proportional blocks color-coded by type (`VideoClip` blue, `ImageClip` green, `TitleSequence` orange), transitions as glyphs in the gaps, audio tracks as a lane below. Optional `currentTime: Binding<CMTime>?` draws a vertical playhead. Untrimmed `VideoClip`s have their `.metadata.duration` resolved asynchronously on appear.
  - **Selection** ([#13](https://github.com/SteliyanH/kadr-ui/pull/13)) — `selectedClipID: Binding<ClipID?>?` + tap-to-select with toggle semantics. Selected clip gets a thicker white border. Transitions and unidentified clips don't participate.
  - **Reorder** ([#14](https://github.com/SteliyanH/kadr-ui/pull/14)) — `onReorder: ((from: Int, to: Int, newClips: [any Clip]) -> Void)?` callback. Drag-to-reorder via 10pt-minimum-distance `DragGesture`. Transitions glue to their preceding media clip and travel together — consumers never see freestanding `Transition`s mid-array. Reorder math (`computeTargetIndex`, `applyReorder`) extracted as pure static functions; unit-tested directly. Surfaced two off-by-one bugs in development; both fixed.
  - **Trim** ([#15](https://github.com/SteliyanH/kadr-ui/pull/15)) — `onTrim: ((Int, leadingTrim: CMTime, trailingTrim: CMTime) -> Void)?` callback. Thin grab handles render on each media clip's leading and trailing edges when `onTrim` is non-`nil`. Sign convention: positive = trim, negative = extend. Consumer maps deltas to `VideoClip.trimRange` (CMTimeRange shift) or `ImageClip.duration(_:)` (CMTime adjustment). No live visual resize during drag in v1 — clip re-renders on consumer rebuild; live resize deferred to v0.4.2.

### Changed

- `Package.resolved` updated to **kadr 0.4.1**, which ships the `ClipID` type that selection / reorder / trim all consume. The existing `from: "0.4.0"` pin was already permissive enough; `swift package update` resolved cleanly.

### Tests

- 17 new tests across `TimelineViewTests`. Construction smoke-tests for each new binding/callback combination, plus direct unit tests for the pure static math (`computeTargetIndex`, `applyReorder`, `computeTrimDeltas`). Suite: 16 → 39, all green.

### Architectural notes

- **Reorder and trim use the callback model** because Kadr's `Video` is immutable. `TimelineView` surfaces user intent (`onReorder` gives you the rebuilt clip array; `onTrim` gives you the deltas to apply); the consumer constructs a fresh `Video` and feeds it back. This keeps the timeline a pure read of the composition with no hidden state, matches the same pattern KadrUI already uses for `OverlayHost` gestures, and avoids any kadr-side mutation API.
- **`CMTime`-throughout** for time deltas matches Kadr's frame-accuracy convention; consumers map directly into `CMTimeRange`-typed `VideoClip.trimRange` / `CMTime`-overload of `ImageClip.duration(_:)` with no lossy seconds round-trip.

## [0.4.0] - 2026-04-27

The first feature release. Four drop-in SwiftUI views consuming Kadr 0.4.0's introspection and preview primitives, plus gesture modifiers that hit-test through `LayerID`.

### Added

- **`VideoPreview(_ video:, onLoadFailure:)`** ([#3](https://github.com/SteliyanH/kadr-ui/pull/3)) — `AVKit.VideoPlayer`-backed preview wrapping `Kadr.Video.makePlayerItem()`. Loading / loaded / error states; optional failure callback.
- **`ThumbnailStrip(_ video:, count:)`** ([#4](https://github.com/SteliyanH/kadr-ui/pull/4)) — horizontal strip of evenly-spaced thumbnails generated via `Kadr.Video.thumbnail(at:)`. Pre-sized layout, gray placeholder for failed slots, empty for zero-duration compositions.
- **`OverlayHost(_ video:, customRenderer:)`** ([#5](https://github.com/SteliyanH/kadr-ui/pull/5)) — SwiftUI overlay layer rendering Kadr `Overlay`s using `Kadr.Layout.resolveFrame(...)` for pixel-exact placement. Built-in renderers for `ImageOverlay` / `TextOverlay` / `StickerOverlay`; per-overlay `customRenderer` hook for hybrid replacement.
- **`OverlayHost.onLayerTap` / `OverlayHost.onLayerDrag`** ([#6](https://github.com/SteliyanH/kadr-ui/pull/6)) — gesture modifiers that hit-test through `Kadr.LayerID`. Drag uses 5-pt minimum distance so taps and drags don't conflict. Only overlays with a non-`nil` `LayerID` participate.

### Documentation ([#7](https://github.com/SteliyanH/kadr-ui/pull/7))

- README rewrite with badges, Quick Start, component table, Installation, and a Compatibility table mapping KadrUI versions to required Kadr versions.
- DocC catalog (`Sources/KadrUI/KadrUI.docc/KadrUI.md`) with Topics for Preview / Thumbnails / Overlays.

### Examples ([#8](https://github.com/SteliyanH/kadr-ui/pull/8))

- `Examples/SimpleViewer/ContentView.swift` — single-file SwiftUI sample wiring all four components together. No external resources; demo composition built from system symbols. Demonstrates `customRenderer`, `.onLayerTap` selection state, `.onLayerDrag` translation HUD, and a yellow outline drawn via `Kadr.Layout.resolveFrame(...)` over the selected overlay.

### Internal

- **`Kadr` dependency** ([#2](https://github.com/SteliyanH/kadr-ui/pull/2)) — pinned to `from: "0.4.0"`. `Package.resolved` committed for deterministic CI / contributor resolution.
- **`Image.init(platformImage:)` / `Color.init(platformColor:)`** — package-internal cross-platform bridges from Kadr's `PlatformImage` / `PlatformColor` to SwiftUI primitives.

### Tests

- 16 smoke tests across `KadrUITests`, `VideoPreviewTests`, `ThumbnailStripTests`, `OverlayHostTests`, `OverlayGestureTests`. SwiftUI views can't be visually tested without a hosting environment; tests lock in the public constructor / modifier-chain contracts so a public-API regression fails to compile, not at runtime. Visual / playback / gesture-firing behavior is verified manually via the example app.

### Architectural notes

- Overlays are rendered by KadrUI as SwiftUI views over `VideoPreview`, not baked into the AVPlayer's `videoComposition`. This is structural: Kadr's preview surface intentionally excludes overlays (`AVVideoCompositionCoreAnimationTool` is export-only and crashes on a playback `videoComposition`), and SwiftUI gestures can only hit-test what's in the SwiftUI tree. The exported file from Kadr still bakes overlays in via the engine's animation tool.
- `OverlayHost` assumes its bounds equal the video's display rectangle (parent uses `.aspectRatio(...)`). Letterboxing alignment is out of scope for v0.4.x; if your parent letterboxes, overlays will land in the bands, not the video.
