# KadrUI

[![CI](https://github.com/SteliyanH/kadr-ui/actions/workflows/ci.yml/badge.svg)](https://github.com/SteliyanH/kadr-ui/actions/workflows/ci.yml)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSteliyanH%2Fkadr-ui%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SteliyanH/kadr-ui)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSteliyanH%2Fkadr-ui%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SteliyanH/kadr-ui)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/steliyanh)

**SwiftUI components for [Kadr](https://github.com/SteliyanH/kadr) — preview, scrub, and overlay-edit `Video` compositions in your own UI.**

**[API documentation →](https://swiftpackageindex.com/SteliyanH/kadr-ui/documentation)**  ·  built and hosted by the Swift Package Index for every release.

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
.package(url: "https://github.com/SteliyanH/kadr-ui.git", .upToNextMinor(from: "0.21.0")),
```

Then add `KadrUI` to your target's dependencies. Kadr is pulled in transitively — 0.16.x resolves `>=0.17.0, <0.18.0`.

> **Use `.upToNextMinor`, not `from:`.** `from:` means `.upToNextMajor`, and SwiftPM does not special-case `0.x` — so `from: "0.21.0"` would accept every future 0.x release including breaking ones. This package's own kadr dependency is pinned the same way, because kadr's minors do break: 0.15.0 raised the platform floor.

## Compatibility

Requires **kadr 1.0 or later** and is pinned `from: "1.0.0"`, so any `1.x` works.

Swift 6 · iOS 17 · macOS 14 · tvOS 17 · visionOS 1

> This section used to carry a table mapping every KadrUI version to the kadr
> version it needed. That table was correct on the day of each release and wrong
> by the next one, which is worse than absent — a reader deciding whether to
> adopt would have concluded this package trailed kadr by five releases. While
> kadr was pre-1.0 the mapping mattered, because each adapter accepted exactly
> one kadr minor. Since kadr 1.0 it does not: `1.x` is `1.x`.

## Example app

For a complete reference implementation that wires every KadrUI component into a real iOS editor — preview, multi-lane timeline, inspector panel, keyframe editor, animated text overlays, audio crossfade glyphs — see [`kadr-reels-studio`](https://github.com/SteliyanH/kadr-reels-studio). It's a runnable iOS app (`brew install xcodegen && make project && open ReelsStudio.xcodeproj`) using KadrUI alongside the rest of the kadr ecosystem (kadr core, [kadr-captions](https://github.com/SteliyanH/kadr-captions), [kadr-photos](https://github.com/SteliyanH/kadr-photos)).

The previous `Examples/SimpleViewer/` snippet has been removed in favor of the standalone reels-studio repo.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for KadrUI's milestones, and
[Releases](https://github.com/SteliyanH/kadr-ui/releases) for what actually
shipped — linked rather than summarised here, because a README that names a
latest version is a README that is wrong within a week.

KadrUI ships on its own version track; each release is gated on the matching
kadr public surface.

## The kadr ecosystem

| Package | Purpose |
|---|---|
| [`kadr`](https://github.com/SteliyanH/kadr) | The engine. Declarative video composition and export. |
| [`kadr-ui`](https://github.com/SteliyanH/kadr-ui) | SwiftUI components — preview, timeline, transport, inspector, keyframe editor. |
| [`kadr-persistence`](https://github.com/SteliyanH/kadr-persistence) | Save a composition to a file and open it again. |
| [`kadr-audio`](https://github.com/SteliyanH/kadr-audio) | Music library, voiceover recording, LUFS loudness. |
| [`kadr-captions`](https://github.com/SteliyanH/kadr-captions) | SRT, VTT, iTT, ASS and SSA parsing and authoring. |
| [`kadr-photos`](https://github.com/SteliyanH/kadr-photos) | Photos library integration. |

And a reference application: [**Kadr Studio**](https://github.com/SteliyanH/kadr-reels-studio), a short-form vertical video editor built on all six.

## License

Apache-2.0. See [LICENSE](LICENSE).

Contributions are accepted under the [Contributor License Agreement](CLA.md), which is signed once and covers all future contributions. It does not transfer ownership — you keep the copyright in your work.
