# ``KadrUI``

SwiftUI components for Kadr — preview, scrub, and overlay-edit `Video` compositions in your own UI.

## Overview

KadrUI consumes [Kadr](https://github.com/SteliyanH/kadr)'s public introspection and preview primitives to provide drop-in SwiftUI views: an `AVPlayer`-backed preview (``VideoPreview``), a horizontal thumbnail strip (``ThumbnailStrip``), an overlay layer with built-in renderers, a custom hook, and `LayerID`-routed gesture modifiers (``OverlayHost``), and a visual timeline with selection, drag-to-reorder, trim handles, and **multi-lane rendering for v0.6+ multi-track compositions** (``TimelineView``).

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

### Timeline (v0.4.1+, multi-lane v0.5+)

- ``TimelineView``

### Audio waveforms (v0.5.3+)

- ``AudioWaveform``
- ``AudioWaveformLoader``

### Namespace

- ``KadrUI/KadrUI``
