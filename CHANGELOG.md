# Changelog

All notable changes to KadrUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

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
