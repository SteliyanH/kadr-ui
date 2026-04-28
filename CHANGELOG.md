# Changelog

All notable changes to KadrUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

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
