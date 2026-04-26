import SwiftUI
import CoreMedia
import Kadr
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A horizontal strip of evenly-spaced thumbnails for a Kadr ``Kadr/Video`` composition.
///
/// Each thumbnail is rendered through ``Kadr/Video/thumbnail(at:)``, so it honors the same
/// crop and preset resolution the engine would use. Useful as a scrubbing strip below a
/// ``VideoPreview``, or as a standalone visual summary of a composition.
///
/// ```swift
/// VStack(spacing: 8) {
///     VideoPreview(video)
///     ThumbnailStrip(video, count: 12)
///         .frame(height: 60)
/// }
/// ```
///
/// **Lifecycle.** All thumbnails are generated in parallel on first appear via a
/// `TaskGroup`. Slots populate as their frames complete; slots whose generation fails
/// silently render an empty placeholder so the strip's spacing stays stable. The video
/// is captured at first appear — use `.id(video)` on the parent if the composition can
/// change while the strip is on screen.
///
/// **Empty composition.** If ``Kadr/Video/duration`` is zero (e.g. an untrimmed
/// `VideoClip` whose asset hasn't been loaded), the strip renders nothing.
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct ThumbnailStrip: View {

    private let video: Video
    private let count: Int

    @State private var thumbnails: [PlatformImage?]

    /// Create a strip for `video` with `count` evenly-spaced thumbnails.
    /// - Parameters:
    ///   - video: The Kadr composition.
    ///   - count: Number of thumbnails to generate. Defaults to `10`. Values `<= 0`
    ///     render an empty strip.
    public init(_ video: Video, count: Int = 10) {
        self.video = video
        self.count = count
        // Pre-size the array so SwiftUI has stable layout from first frame.
        self._thumbnails = State(initialValue: Array(repeating: nil, count: max(count, 0)))
    }

    public var body: some View {
        let aspect = video.preset.resolution.height > 0
            ? video.preset.resolution.width / video.preset.resolution.height
            : 1
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(thumbnails.indices, id: \.self) { i in
                    cell(for: thumbnails[i])
                        .aspectRatio(aspect, contentMode: .fit)
                }
            }
        }
        .task {
            await loadThumbnails()
        }
    }

    @ViewBuilder
    private func cell(for image: PlatformImage?) -> some View {
        if let image {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            Color.gray.opacity(0.2)
        }
    }

    private func loadThumbnails() async {
        let total = CMTimeGetSeconds(video.duration)
        guard count > 0, total.isFinite, total > 0 else { return }
        let step = total / Double(count)

        // Serial generation: each `await` returns to the same actor, so PlatformImage
        // never has to cross an isolation boundary. Avoids the macOS-13 Sendable warning
        // on NSImage (which only conforms from macOS 14). Per-frame cost is small enough
        // (single AVAssetImageGenerator call) that the lost parallelism is acceptable.
        for i in 0..<count {
            let t = step * Double(i)
            thumbnails[i] = try? await video.thumbnail(at: t)
        }
    }
}

