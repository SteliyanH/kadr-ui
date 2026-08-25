# KadrUI

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2017+%20|%20macOS%2014+%20|%20tvOS%2017+%20|%20visionOS%201+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/steliyanh)

**SwiftUI components for [Kadr](https://github.com/SteliyanH/kadr) — preview, scrub, and overlay-edit `Video` compositions in your own UI.**

KadrUI consumes Kadr's introspection and preview surface (`Video.makePlayerItem`, `Video.thumbnail(at:)`, `Layout.resolveFrame`, `Video.clips`, `Track`, `AudioTrack`) to provide drop-in SwiftUI views: an `AVPlayer`-backed preview, a horizontal thumbnail strip, an overlay layer with built-in renderers and a custom hook, gesture modifiers that hit-test through `LayerID`, and a multi-lane `TimelineView` with selection / drag-to-reorder / live trim / tap-to-scrub and audio waveforms.

## Quick Start

```swift
import SwiftUI
import KadrUI
import Kadr

struct EditorScreen: View {
    let video: Video
    @State private var selectedLayerID: LayerID?
    @State private var selectedClipID: ClipID?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                VideoPreview(video)
                OverlayHost(video)
                    .onLayerTap { selectedLayerID = $0 }
                    .onLayerDrag(onEnded: { id, t in commit(id, offset: t) })
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)

            TimelineView(
                video,
                selectedClipID: $selectedClipID,
                showAudioWaveforms: true,
                onReorder: { _, _, newClips in /* rebuild Video with newClips */ },
                onTrim: { idx, leading, trailing in /* rebuild clip with trims */ }
            )
            .frame(height: 80)

            ThumbnailStrip(video, count: 12)
                .frame(height: 60)
        }
    }

    func commit(_ id: LayerID, offset: CGSize) { /* ... */ }
}
```

## Components

| Component | Purpose | Built on |
|---|---|---|
| `VideoPreview(_ video:)` | Plays a `Video` composition in `AVKit.VideoPlayer` | `Kadr.Video.makePlayerItem()` |
| `ThumbnailStrip(_ video:, count:)` | Horizontal strip of evenly-spaced composition thumbnails | `Kadr.Video.thumbnail(at:)` |
| `OverlayHost(_ video:, customRenderer:)` | Renders Kadr `Overlay`s as SwiftUI views over the player | `Kadr.Layout.resolveFrame(...)` |
| `.onLayerTap` / `.onLayerDrag` | Gesture modifiers on `OverlayHost`, hit-tested through `LayerID` | `Kadr.LayerID` |
| **`TimelineView`** *(v0.4.1, polished v0.4.2 / v0.4.3, multi-lane v0.5, crossfade glyphs v0.6)* | Visual timeline with playhead, tap-to-select, drag-to-reorder (neighbors slide to make space), trim handles, live trim resize, tap-to-scrub. Stacks lanes for Kadr 0.6 multi-track compositions (`Track {}`, `.at(time:)`, audio tracks). Audio crossfade indicators on overlapping tracks. | `Kadr.Video.clips`, `Kadr.ClipID`, `Kadr.Track`, `Kadr.AudioTrack.crossfadeDuration` |
| **`InspectorPanel`** *(v0.6)* | Per-clip property panel: Transform sliders (position / rotation / scale / anchor), opacity, animatable filter intensities. Edits surface through callbacks like `TimelineView.onTrim` | `Kadr.Transform`, `Kadr.Filter`, `Kadr.Clip.opacity` |
| **`KeyframeEditor`** *(v0.6)* | Per-property keyframe tracks. Tap-to-add at playhead, long-press to remove, drag to retime. One row per animatable property (`.transform` / `.opacity` / `.filter(index:)`) | `Kadr.Animation<T>`, `Kadr.Clip.transformAnimation`, `Kadr.Clip.opacityAnimation`, `Kadr.VideoClip.filterAnimations` |
| **Animated `TextOverlay` preview** *(v0.6)* | When a `TextOverlay` carries a `textAnimation`, `OverlayHost` runs the `[CAAnimation]` against a live `CATextLayer` so preview matches export | `Kadr.TextAnimation` |

## Appearance

KadrUI draws with its own colours, radii and fonts by default. If your app has a
design system, set `KadrAppearance` once near the editor's root and every KadrUI
view in the subtree picks it up:

```swift
TimelineView(video, currentTime: $time)
    .kadrAppearance(
        KadrAppearance(
            cornerRadius: 0,
            laneCornerRadius: 0,
            elevation: 0,                    // flat systems have no ambient shadow
            playhead: .white,
            clipColors: .uniform(.gray),     // mono: content carries the meaning, not hue
            clipContentRendering: .grayscale,
            keyframeMarkShape: .diamond
        )
    )
```

**Doing nothing changes nothing.** The environment default is
`KadrAppearance.system`, whose every value is the rendering KadrUI shipped before
the appearance surface existed — the package's snapshot baselines were not
re-recorded when it landed, which is the proof rather than the promise.

Covers geometry (corner radii, stroke width, elevation), timeline colours
(playhead, selection ring, track and lane grounds, waveform, keyframe marks,
overlay lane), footage rendering (`.color` / `.grayscale`), and six type roles.
Each property documents its pre-0.13 value.

### Why a separate package?

Kadr exposes the playback / thumbnail / introspection primitives, but intentionally **does not bake overlays into the preview surface** — `AVVideoCompositionCoreAnimationTool` is export-only and crashes on a playback `videoComposition`. KadrUI renders overlays as SwiftUI views over the player, which is also the only way SwiftUI gestures can hit-test them. The export pipeline still bakes overlays into the on-disk file.

## Installation

Add KadrUI to your `Package.swift`:

```swift
.package(url: "https://github.com/SteliyanH/kadr-ui.git", from: "0.8.0"),
```

Then add `KadrUI` to your target's dependencies. Kadr is pulled in transitively (≥ `0.10.0`).

## Compatibility

| KadrUI | Requires Kadr |
|---|---|
| 0.4.0 | ≥ 0.4.0 |
| 0.4.1 | ≥ 0.4.1 *(uses `ClipID`)* |
| 0.4.2 | ≥ 0.4.1 |
| 0.4.3 | ≥ 0.4.1 |
| 0.4.4 | ≥ 0.5.0 *(uses `Overlay.visibilityRange`)* |
| 0.5.0 | ≥ 0.6.0 *(uses `Track`, `Clip.startTime`)* |
| 0.5.1 | ≥ 0.6.0 |
| 0.5.2 | ≥ 0.7.0 *(uses `Track.name`, `AudioTrack.startTime`, `AudioTrack.explicitDuration`)* |
| 0.5.3 | ≥ 0.7.0 |
| 0.6.0 | ≥ 0.8.0 *(uses `Transform`, `Animation<T>`, animated `TextOverlay`, `AudioTrack.crossfadeDuration`)* |
| 0.7.0 / 0.7.1 | ≥ 0.10.0 *(uses `Track.opacityFactor`)* |
| 0.8.0 | ≥ 0.10.0 |
| 0.9.0 / 0.9.1 / 0.9.2 | ≥ 0.10.1 *(uses animation-clearing modifiers)* |
| 0.10.0 / 0.10.1 / 0.10.2 | ≥ 0.11.0 *(uses `Speed` enum + `FilterID` keyed API)* |
| 0.11.0 | ≥ 0.11.0 *(accessibility sweep — no new Kadr surface)* |
| 0.12.0 | ≥ 0.15.0 *(iOS 17 floor; Kadr 0.15 floor + 0.14 `Speed` enum-only)* |

Same platform floor as Kadr: iOS 17+ / macOS 14+ / tvOS 17+ / visionOS 1+, Swift 6.0, strict concurrency. *(Floor raised in v0.12.0 — was iOS 16 / macOS 13. Stay on `0.11.x` for the iOS 16 floor.)*

## Example app

For a complete reference implementation that wires every KadrUI component into a real iOS editor — preview, multi-lane timeline, inspector panel, keyframe editor, animated text overlays, audio crossfade glyphs — see [`kadr-reels-studio`](https://github.com/SteliyanH/kadr-reels-studio). It's a runnable iOS app (`brew install xcodegen && make project && open ReelsStudio.xcodeproj`) using KadrUI alongside the rest of the kadr ecosystem (kadr core, [kadr-captions](https://github.com/SteliyanH/kadr-captions), [kadr-photos](https://github.com/SteliyanH/kadr-photos)).

The previous `Examples/SimpleViewer/` snippet has been removed in favor of the standalone reels-studio repo.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for KadrUI's own milestones. Latest: **v0.11.0** — library accessibility sweep. VoiceOver labels / values / hints + adjustable actions across every interactive surface (timeline clips & trim handles, scrub/playhead, keyframe & speed-curve markers, inspector sliders, caption fields), Reduce-Motion gating on internal animations, and media-view labels. No visual change (all snapshot baselines unchanged) and no new public API. Recently shipped: v0.10.2 audio trim handles, v0.10.0 API hardening, and v0.10.1 snapshot + gesture-driver test infrastructure (swift-snapshot-testing + ViewInspector). Next: v0.12 `@Observable` migration (when the iOS 17 floor moves). See [Kadr's ROADMAP](https://github.com/SteliyanH/kadr/blob/main/ROADMAP.md) for the upstream library — KadrUI ships on its own version track but each release is gated on the matching Kadr public surface.

## License

Apache-2.0. See [LICENSE](LICENSE).
