# KadrUI

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2016+%20|%20macOS%2013+%20|%20tvOS%2016+%20|%20visionOS%201+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

**SwiftUI components for [Kadr](https://github.com/SteliyanH/kadr) — preview, scrub, and overlay-edit `Video` compositions in your own UI.**

KadrUI consumes Kadr's v0.4.0 introspection and preview primitives (`Video.makePlayerItem`, `Video.thumbnail(at:)`, `Layout.resolveFrame`) to provide drop-in SwiftUI views: an `AVPlayer`-backed preview, a horizontal thumbnail strip, an overlay layer with built-in renderers and a custom hook, and gesture modifiers that hit-test through Kadr's `LayerID`.

## Quick Start

```swift
import SwiftUI
import KadrUI
import Kadr

struct EditorScreen: View {
    let video: Video
    @State private var selectedLayerID: LayerID?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                VideoPreview(video)
                OverlayHost(video)
                    .onLayerTap { selectedLayerID = $0 }
                    .onLayerDrag(onEnded: { id, t in commit(id, offset: t) })
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)

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
| **`TimelineView`** *(v0.4.1, polished v0.4.2 / v0.4.3)* | Visual timeline with playhead, tap-to-select, drag-to-reorder (neighbors slide to make space), trim handles, live trim resize, tap-to-scrub | `Kadr.Video.clips`, `Kadr.ClipID` |

### Why a separate package?

Kadr 0.4.0 exposes the playback / thumbnail / introspection primitives, but intentionally **does not bake overlays into the preview surface** — `AVVideoCompositionCoreAnimationTool` is export-only and crashes on a playback `videoComposition`. KadrUI renders overlays as SwiftUI views over the player, which is also the only way SwiftUI gestures can hit-test them. The export pipeline still bakes overlays into the on-disk file.

## Installation

Add KadrUI to your `Package.swift`:

```swift
.package(url: "https://github.com/SteliyanH/kadr-ui.git", from: "0.4.0"),
```

Then add `KadrUI` to your target's dependencies. Kadr is pulled in transitively (≥ `0.4.0`).

## Compatibility

| KadrUI | Requires Kadr |
|---|---|
| 0.4.0 | ≥ 0.4.0 |
| 0.4.1 | ≥ 0.4.1 *(uses `ClipID`)* |
| 0.4.2 | ≥ 0.4.1 |
| 0.4.3 | ≥ 0.4.1 |

Same platform floor as Kadr: iOS 16+ / macOS 13+ / tvOS 16+ / visionOS 1+, Swift 6.0, strict concurrency.

## Roadmap

See [Kadr's ROADMAP](https://github.com/SteliyanH/kadr/blob/main/ROADMAP.md). KadrUI ships on its own version track; v0.4.x covers the four components above. `TimelineView` is planned for v0.4.1.

## License

Apache-2.0. See [LICENSE](LICENSE).
