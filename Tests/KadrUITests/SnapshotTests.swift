import XCTest
import SwiftUI
import CoreMedia
import Kadr
import SnapshotTesting
@testable import KadrUI

/// Visual-regression snapshots for the editor views. v0.10.1 baseline pass.
///
/// **First-run contract.** On a fresh checkout, each test emits a baseline
/// image to `Tests/KadrUITests/__Snapshots__/` and *fails* with a "no
/// reference" message. The baselines are committed and act as the regression
/// reference for every subsequent run.
///
/// **Re-recording.** Set `isRecording = true` on `SnapshotTesting` (via
/// `record: true` per-call, or globally) to regenerate baselines after an
/// intentional visual change.
///
/// **Determinism.** Tests run at fixed sizes against empty `PlatformImage()`
/// inputs — renders are stable across runs on the same macOS/Xcode version.
/// macOS or Xcode version drift can still produce small pixel differences;
/// pin CI to the toolchain you recorded against.
///
/// **macOS rendering.** swift-snapshot-testing ships a SwiftUI-View strategy
/// for iOS/tvOS only. On macOS we render via the `renderForSnapshot(_:size:)`
/// helper (NSHostingController → NSBitmapImageRep) and snapshot the resulting
/// `NSImage` using the package's `Snapshotting<NSImage, NSImage>.image` strategy.
#if os(macOS)
@MainActor
final class SnapshotTests: XCTestCase {

    private let timelineSize = CGSize(width: 400, height: 100)
    private let overlayHostSize = CGSize(width: 320, height: 240)
    private let inspectorSize = CGSize(width: 320, height: 200)

    // MARK: - Helpers

    private func sampleVideo(clipCount: Int = 3) -> Video {
        let img = PlatformImage()
        return Video {
            for _ in 0..<clipCount {
                ImageClip(img, duration: 2.0)
            }
        }
    }

    private func sampleVideoWithOverlays() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 4.0)
        }
        .overlay(TextOverlay("HELLO").id(LayerID("title")))
        .overlay(StickerOverlay(img).id(LayerID("sticker")))
    }

    // MARK: - TimelineView

    func testTimelineViewBaseSnapshot() {
        let view = TimelineView(sampleVideo())
            .frame(width: timelineSize.width, height: timelineSize.height)
            .background(Color.black)
        let image = renderForSnapshot(view, size: timelineSize)
        assertSnapshot(of: image, as: .image)
    }

    func testTimelineViewWithPlayheadSnapshot() {
        @State var time = CMTime(seconds: 2.0, preferredTimescale: 600)
        let view = TimelineView(sampleVideo(), currentTime: $time)
            .frame(width: timelineSize.width, height: timelineSize.height)
            .background(Color.black)
        let image = renderForSnapshot(view, size: timelineSize)
        assertSnapshot(of: image, as: .image)
    }

    func testTimelineViewWithSelectionSnapshot() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 2.0).id(ClipID("a"))
            ImageClip(img, duration: 2.0).id(ClipID("b"))
        }
        @State var selected: ClipID? = ClipID("a")
        let view = TimelineView(video, selectedClipID: $selected)
            .frame(width: timelineSize.width, height: timelineSize.height)
            .background(Color.black)
        let image = renderForSnapshot(view, size: timelineSize)
        assertSnapshot(of: image, as: .image)
    }

    func testTimelineViewMultiSelectSnapshot() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 2.0).id(ClipID("a"))
            ImageClip(img, duration: 2.0).id(ClipID("b"))
            ImageClip(img, duration: 2.0).id(ClipID("c"))
        }
        @State var multi: Set<ClipID> = [ClipID("a"), ClipID("c")]
        let view = TimelineView(video, selectedClipIDs: $multi)
            .frame(width: timelineSize.width, height: timelineSize.height)
            .background(Color.black)
        let image = renderForSnapshot(view, size: timelineSize)
        assertSnapshot(of: image, as: .image)
    }

    // MARK: - OverlayHost

    func testOverlayHostBaseSnapshot() {
        let view = OverlayHost(sampleVideoWithOverlays())
            .frame(width: overlayHostSize.width, height: overlayHostSize.height)
            .background(Color.black)
        let image = renderForSnapshot(view, size: overlayHostSize)
        assertSnapshot(of: image, as: .image)
    }

    func testOverlayHostWithSelectionSnapshot() {
        @State var single: LayerID? = LayerID("title")
        let view = OverlayHost(sampleVideoWithOverlays(), selectedLayerID: $single)
            .frame(width: overlayHostSize.width, height: overlayHostSize.height)
            .background(Color.black)
        let image = renderForSnapshot(view, size: overlayHostSize)
        assertSnapshot(of: image, as: .image)
    }

    func testOverlayHostMultiSelectSnapshot() {
        @State var multi: Set<LayerID> = [LayerID("title"), LayerID("sticker")]
        let view = OverlayHost(sampleVideoWithOverlays(), selectedLayerIDs: $multi)
            .frame(width: overlayHostSize.width, height: overlayHostSize.height)
            .background(Color.black)
        let image = renderForSnapshot(view, size: overlayHostSize)
        assertSnapshot(of: image, as: .image)
    }

    // MARK: - InspectorPanel

    func testInspectorPanelEmptySelectionSnapshot() {
        let img = PlatformImage()
        let video = Video {
            ImageClip(img, duration: 2.0).id(ClipID("c1"))
        }
        @State var selected: ClipID? = nil
        let view = InspectorPanel(
            video,
            selectedClipID: $selected,
            onTransform: { _, _ in },
            onOpacity: { _, _ in },
            onFilterIntensity: { _, _, _ in }
        )
        .frame(width: inspectorSize.width, height: inspectorSize.height)
        .background(Color.black)
        let image = renderForSnapshot(view, size: inspectorSize)
        assertSnapshot(of: image, as: .image)
    }
}
#endif
