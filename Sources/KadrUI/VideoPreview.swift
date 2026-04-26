import SwiftUI
import AVKit
import Kadr

/// A SwiftUI view that previews a Kadr ``Kadr/Video`` composition using `AVKit.VideoPlayer`.
///
/// Drop a `Video` into a `VideoPreview` to play the composition without writing it to disk first.
/// What you see matches what ``Kadr/Video/export(to:)`` would write *except* overlays, which Kadr's
/// preview surface intentionally excludes (`AVVideoCompositionCoreAnimationTool` is export-only).
/// Render overlays as views layered over `VideoPreview` using
/// ``Kadr/Layout/resolveFrame(position:size:anchor:in:)`` for placement.
///
/// ```swift
/// import KadrUI
/// import Kadr
///
/// struct PreviewScreen: View {
///     let video: Video
///     var body: some View {
///         VideoPreview(video)
///             .aspectRatio(9.0/16.0, contentMode: .fit)
///     }
/// }
/// ```
///
/// **Lifecycle.** The composition is loaded asynchronously via ``Kadr/Video/makePlayerItem()`` on first
/// appear. While loading, the view shows a black background with a centered progress indicator. If
/// loading fails, the view shows a black background with a warning glyph; pass an `onLoadFailure`
/// closure to surface the underlying error to your own UI.
///
/// **Identity.** The composition is captured at first appear; passing a different `Video` to the same
/// `VideoPreview` instance won't trigger a reload. Use `.id(...)` on the parent if you need re-loading
/// when the composition changes.
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct VideoPreview: View {

    private let video: Video
    private let onLoadFailure: ((Error) -> Void)?

    @State private var player: AVPlayer?
    @State private var didFailToLoad = false

    /// Create a preview for `video`.
    /// - Parameters:
    ///   - video: The Kadr composition to preview.
    ///   - onLoadFailure: Optional callback invoked on the main actor if
    ///     ``Kadr/Video/makePlayerItem()`` throws. Default `nil`.
    public init(_ video: Video, onLoadFailure: ((Error) -> Void)? = nil) {
        self.video = video
        self.onLoadFailure = onLoadFailure
    }

    public var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else if didFailToLoad {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task {
            do {
                let item = try await video.makePlayerItem()
                player = AVPlayer(playerItem: item)
            } catch {
                didFailToLoad = true
                onLoadFailure?(error)
            }
        }
    }
}
