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

## v0.9.2 — Multi-select + long-press ✓ shipped

Two-surface micro-patch driven by `kadr-reels-studio` v0.4 Tier 5 (Track creation UI):

- **`TimelineView(... selectedClipIDs:)`** — additive `Binding<Set<ClipID>>?` parameter. Coexists with `selectedClipID`; render sites union-check both via the new `clipMatchesSelection(id:single:set:)` `nonisolated public static` helper.
- **`TimelineView.onLongPressClip(_:)`** — fires on a 0.5s long-press of any media clip with a non-nil `clipID`. `.simultaneousGesture` with the existing tap. Symmetric across chain + Track lanes.

Pure additive. Same shape as v0.9.1's micro-patch.

## v0.10.0 — API hardening + overlay multi-select ✓ shipped

Pre-v1.0 cycle absorbing API-shape fixes from a cross-package audit:

- **`Sendable` event-struct callbacks** on `TimelineView` (`ClipReorderEvent` / `ClipTrimEvent` / `TrackReorderEvent` / `TrackTrimEvent`). Replaces positional-arg closures where every same-type pair was a swap landmine. Deprecated positional-arg init kept for one minor (removal target v0.11).
- **`OverlayHost` selection bindings + selection ring** — went full scope on discovery that `OverlayHost` had no selection binding at all pre-v0.10. New `selectedLayerID` + `selectedLayerIDs` parameters, white 2pt selection ring matching `TimelineView`'s clip ring, tap-writes-binding + tap-to-deselect, `.isSelected` accessibility trait. `overlayMatchesSelection(id:single:set:)` helper parallel to v0.9.2's `clipMatchesSelection`.
- `OverlayHost` 30%×30% default-size committed (drops "v1 placeholder" framing). `TimelineView` header refreshed to describe the v0.9.2 gesture surface.

kadr floor bumped to ≥ 0.11.0.

## v0.10.1 — Snapshot + gesture-wiring test infrastructure ✓ shipped

Test-only additions. swift-snapshot-testing + ViewInspector both as test-only deps. 8 visual-regression baselines committed for `TimelineView` / `OverlayHost` / `InspectorPanel`. 9 gesture-wiring smoke tests for `onLongPressClip` / `onZoomSnap` / `onClipDragSnap` / full-composition stacks. Custom `renderForSnapshot(_:size:)` helper bridges SwiftUI → NSImage on macOS where swift-snapshot-testing's `Snapshotting<View, UIImage>` is iOS/tvOS-only. Pure-logic gesture seams (`snapTransition`, `crossings`, `clipMatchesSelection`, `overlayMatchesSelection`) already covered the math; these new tests catch *attachment* regressions.

## v0.10.2 — Audio trim handles ✓ shipped

Single-tier patch adding the gesture surface on audio rows; waveform peaks already rendered since v0.6's `showAudioWaveforms`.

- `AudioTrimEvent` Sendable payload (trackIndex + leadingTrim + trailingTrim CMTimes), mirroring `TrackTrimEvent` shape minus the inner clipIndex — audio rows have no inner array, each row IS the trim unit.
- `TimelineView.onAudioTrim(_:)` modifier, same callback shape as `onTrackTrim`. Default-nil = audio rows render exactly as pre-v0.10.2 (zero pixel diff for callers that don't opt in).
- `audioItemBlock` / `audioTrimHandle` / `audioTrimGesture` mirror `trackItemBlock` structure: live width preview during drag, wider hit target than visual, drag-end fires through the existing `computeTrimDeltas` pure helper.

Suite +2 tests (event shape + gesture wiring); 322 → 324 across 25 suites. Pairs with **reels-studio v0.7 Tier 1** which wires the callback to `ProjectStore.applyMusicTrim` / `applySFXTrim`.

## v0.11.0 — Library accessibility sweep ✓ shipped

`.accessibilityLabel` / `.accessibilityHint` / `.accessibilityValue` (+ `.accessibilityAdjustableAction` on drag-only controls) across every interactive surface inside the library — consumers shouldn't be more accessible than the views they're built on. Plus a Dynamic Type pass and Reduce-Motion gating on internal animations. The library ships exactly one `.accessibility*` call today, so this is a from-scratch sweep. Five tiers grouped by surface (see DESIGN.md for the full RFC):

1. **Timeline + overlay canvas** — `TimelineView` / `TimelineLanes` / `TimelineZoom` / `OverlayHost`: clips, trim handles, scrubber/playhead, zoom, overlay selection.
2. **Editors with control points** — `KeyframeEditor` / `OverlayKeyframeEditor` / `SpeedCurveEditor`: per-marker labels + values + adjustable retiming.
3. **Inspector panels + caption editor** — `InspectorPanel` / `OverlayInspector` / `CaptionEditor`: slider values + adjustable actions, picker labels, timestamp fields.
4. **Cross-cutting** — Dynamic Type pass + Reduce-Motion gating + media-view labels (`VideoPreview` / `ThumbnailStrip` / `AudioWaveform` / `AnimatedTextLayerView`).
5. **Release prep** + tag v0.11.0.

Internal view modification — minimal-to-no new public API (accessibility is automatic, not opt-in).

## v0.12.0 — iOS 17 platform floor ✓ shipped

Floor raised to **iOS 17 / macOS 14 / tvOS 17 / visionOS 1** as the middle step of a coordinated stack-wide move (kadr v0.15 → **kadr-ui v0.12** → reels-studio `@Observable` migration). Concretely:

- `Package.swift` platforms bumped; Kadr floor bumped to **≥ 0.15.0**.
- Dropped 40 now-redundant `@available(iOS 16, …)` annotations across the library.
- Migrated 4 `onChange(of:perform:)` call sites to the iOS-17 two-parameter `onChange` (the only new SDK deprecation the floor surfaced).
- Migrated a lingering `.speed(curve:)` test call to the `Speed` enum (Kadr removed the deprecated overloads in 0.14).

No behavior change; snapshot baselines unchanged. **Correction to the original roadmap:** this entry was pencilled in as the `@Observable` migration, but KadrUI holds no `ObservableObject`s — it's pure value-type SwiftUI. The actual `@Observable` migration lives in **reels-studio** (which owns the app's stores) and rides on this floor move.

## v0.13.0 — Appearance surface ✓ shipped

`KadrAppearance`, propagated through the environment, so a consuming app can style the views KadrUI draws. Additive and non-breaking: every default reproduces the pre-0.13 rendering, and the eight snapshot baselines pass unchanged as proof.

- Geometry (`cornerRadius`, `laneCornerRadius`, `strokeWidth`, `elevation`), timeline colours (playhead, selection ring, track and lane grounds, waveform, keyframe marks, overlay lane), footage rendering (`.color` / `.grayscale`), six type roles.
- `ClipColors.uniform(_:)` for mono schemes; `KeyframeMarkShape.diamond` for editors that mark authored values with a diamond.
- Driven by [reels-studio#68](https://github.com/SteliyanH/kadr-reels-studio/pull/68), whose design migration stopped at the editor because this surface didn't exist. Closes [#101](https://github.com/SteliyanH/kadr-ui/issues/101).

**Still open after this:** [#102](https://github.com/SteliyanH/kadr-ui/issues/102) — `VideoPreview` tap-to-sample, so consumers can build an eyedropper. Unrelated to appearance; it needs a coordinate → pixel mapping the package alone can do correctly, since it owns letterboxing and scale.

## v0.14.0 — Preview interaction ✓ shipped

Two additive hooks on `VideoPreview`, both driven by consumer needs that were unbuildable without them.

- **Tap-to-sample** (#102) — a tap on the picture reports the colour under it plus a normalised point, so an app can build an eyedropper. Taps in the letterbox bars report nothing rather than the surround's black. Geometry lives in `VideoSampling` as free functions, so it is unit-tested on runners that cannot decode media.
- **Playback control** — `isPlaying` / `currentTime` bindings and a `loops` flag, so an app can build a transport band. `currentTime` is meant to be shared with `TimelineView`'s binding: one playhead, not two that drift. `isPlaying` clears itself at the end of a non-looping composition.

Both default to inert, so v0.13 call sites are unchanged. Suite 335 → 354.

## v0.15.0 — Ten API gaps closed ✓ shipped

Every change additive and defaulting to previous behaviour, so an existing caller upgrades without edits. The common thread: each of these forced a consumer to copy something out of this package, reimplement it, or do without — and several of those copies had already drifted.

- **`VideoPreview.compositionIdentity(of:reloadToken:)`** — the structural fingerprint deciding when the player is rebuilt. Consumers were reconstructing it by hand from the same four inputs.
- **`VideoPreview(showsPlaybackControls:)`** — suppresses AVKit's transport for hosts drawing their own. Blocks hit-testing *and* hides the subtree from accessibility, because an accessibility activation is delivered straight to the UIKit element and never consults hit-testing.
- **`VideoPreview.seekEpsilon`**, **`TimelineView.Metrics`**, **`contentHeight(...)`**, **`LaneHeights`**, **`onScrollOffsetChange:`**, **`clipAccessibilityLabel:`**, **`InspectorPanel.Section`**, **`OverlayInspectorPanel(onTextStroke:onTextShadow:)`**.
- **`loops` now takes effect while a player is alive.** The periodic observer captured the flag by value and `.task(id:)`'s identity never included it, so a loop toggle reviewed clean and did nothing on device.

## v0.16.0 — Adopts kadr 0.17.0 ✓ shipped

No API change. The pin is `.upToNextMinor`, so picking up a kadr minor is a deliberate act rather than something that happens on its own. What comes with it: kadr's errors now conform to `LocalizedError`, so a failure surfaced through this package reads as a sentence rather than `(Kadr.KadrError error 6.)`.

## v0.17.0 — Adopts kadr 0.19.0 ✓ shipped

- **kadr floor raised to `0.19.0`.** Two cycles at once: 0.18.0 and 0.19.0 are two
  halves of the same change.
- **`AudioWaveform` / `AudioWaveformLoader` now come from core.** Reading an audio
  file's peaks should not require importing a view package. `KadrUI.AudioWaveform`
  stays valid as a typealias, so existing code is unaffected.
- **`AudioWaveformShape` stays here** — drawing the peaks is this package's job.
  It uses core's new `AudioWaveform.resampled(to:)`, which exists because the move
  had left the resampling helper internal and this Shape unable to compile.
- Four tests added for the Shape. The rendering path had been covered only by the
  compiler.

## v1.0.0 — Production Ready

Tracks Kadr v1.0.

- API stability commitment — no breaking changes without major version bump
- DocC **articles** covering each component (`VideoPreview`, `ThumbnailStrip`, `OverlayHost`, `TimelineView`, `InspectorPanel`, keyframe editor)

  > **Downgraded from tutorials, matching kadr's decision and for the same reason with more force.** `.tutorial` files carry a screenshot and a code snapshot per step, and both rot on any API or UI change. These would document *views*, so every screenshot is invalidated by any visual change — and this package has just been through a design-system migration that changed all of them. For a single maintainer that is the promise most likely to be quietly broken, and a 1.0 shipped against a broken promise is worse than one that amends it.
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
| 0.9.2 | ≥ 0.10.0 |
| 0.10.0 | ≥ 0.11.0 *(uses `Speed` enum / `FilterID` from the kadr v0.11 hardening cycle)* |
| 0.10.1 | ≥ 0.11.0 |
| 1.0.0 *(planned)* | ≥ 1.0.0 |

## Contributing

Want to help build the next version? Open an issue on this repo or on [kadr](https://github.com/SteliyanH/kadr) for upstream feature requests.
