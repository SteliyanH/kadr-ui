# KadrUI

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

**SwiftUI components for [Kadr](https://github.com/SteliyanH/kadr).**

KadrUI is a separate Swift package providing ready-made SwiftUI views for previewing and editing `Video` compositions built with Kadr.

## Status

🚧 **Pre-release.** This package is being scaffolded for the Kadr **v0.4.0** milestone. The API is not stable and there are no tagged releases yet.

## Planned components

- `VideoPreview` — preview a `Video` composition before export
- `TimelineView` — visual timeline showing clips, transitions, and audio
- `ThumbnailStrip` — scrubbing strip generated from video thumbnails
- Gesture handlers (`.onTap`, `.onDrag`) on overlay layers, hit-tested via the `LayerID` contract from Kadr v0.3.0

See the [Kadr roadmap](https://github.com/SteliyanH/kadr/blob/main/ROADMAP.md#v040--kadrui) for details.

## License

Apache-2.0. See [LICENSE](LICENSE).
