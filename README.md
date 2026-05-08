# KadrUI

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2016+%20|%20macOS%2013+%20|%20tvOS%2016+%20|%20visionOS%201+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

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

Same platform floor as Kadr: iOS 16+ / macOS 13+ / tvOS 16+ / visionOS 1+, Swift 6.0, strict concurrency.

## Example app

For a complete reference implementation that wires every KadrUI component into a real iOS editor — preview, multi-lane timeline, inspector panel, keyframe editor, animated text overlays, audio crossfade glyphs — see [`kadr-reels-studio`](https://github.com/SteliyanH/kadr-reels-studio). It's a runnable iOS app (`brew install xcodegen && make project && open ReelsStudio.xcodeproj`) using KadrUI alongside the rest of the kadr ecosystem (kadr core, [kadr-captions](https://github.com/SteliyanH/kadr-captions), [kadr-photos](https://github.com/SteliyanH/kadr-photos)).

The previous `Examples/SimpleViewer/` snippet has been removed in favor of the standalone reels-studio repo.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for KadrUI's own milestones (shipped: v0.9.2 `TimelineView` multi-select + `onLongPressClip` micro-patches on top of v0.9's `fixedCenterPlayhead` + `onZoomSnap`; next: v1.0 stability — DocC tutorials, snapshot tests), and [Kadr's ROADMAP](https://github.com/SteliyanH/kadr/blob/main/ROADMAP.md) for the upstream library. KadrUI ships on its own version track but each release is gated on the matching Kadr public surface.

## License

Apache-2.0. See [LICENSE](LICENSE).
