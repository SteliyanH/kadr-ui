# ``KadrUI``

SwiftUI components for Kadr — preview, scrub, and overlay-edit `Video` compositions in your own UI.

## Overview

KadrUI consumes [Kadr](https://github.com/SteliyanH/kadr) 0.4.x's public introspection and preview primitives to provide drop-in SwiftUI views: an `AVPlayer`-backed preview (``VideoPreview``), a horizontal thumbnail strip (``ThumbnailStrip``), an overlay layer with built-in renderers and a custom hook plus `LayerID`-routed gesture modifiers (``OverlayHost``), and a visual timeline with selection, drag-to-reorder, and trim handles (``TimelineView``).

```swift
import SwiftUI
import KadrUI
import Kadr

struct EditorScreen: View {
    let video: Video
    var body: some View {
        ZStack {
            VideoPreview(video)
            OverlayHost(video)
                .onLayerTap { id in print("tapped \(id)") }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
    }
}
```

> **Why a separate package?** Kadr 0.4.0 intentionally does not bake overlays into its preview surface — `AVVideoCompositionCoreAnimationTool` is export-only and crashes on a playback `videoComposition`. KadrUI renders overlays as SwiftUI views over the player, which is also the only way SwiftUI gestures can hit-test them. The export pipeline still bakes overlays into the on-disk file.

## Topics

### Preview

- ``VideoPreview``

### Thumbnails

- ``ThumbnailStrip``

### Overlays

- ``OverlayHost``
- ``OverlayHost/onLayerTap(_:)``
- ``OverlayHost/onLayerDrag(onChanged:onEnded:)``

### Timeline (v0.4.1+)

- ``TimelineView``

### Namespace

- ``KadrUI/KadrUI``
