import SwiftUI
import AVKit
import CoreMedia
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
/// **Identity.** Reload is automatic when the composition's structural identity changes — a coarse
/// fingerprint over `clips.count`, `overlays.count`, `audioTracks.count`, and `duration`. For finer
/// control (e.g. reload after editing a clip's `trimRange`), pass a `reloadToken` whose value changes
/// when you want the player rebuilt.
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct VideoPreview: View {

    private let video: Video
    private let reloadToken: AnyHashable?
    private let onLoadFailure: ((Error) -> Void)?

    @State private var player: AVPlayer?
    @State private var didFailToLoad = false

    /// Create a preview for `video`.
    /// - Parameters:
    ///   - video: The Kadr composition to preview.
    ///   - reloadToken: Optional value that triggers a reload when it changes. Use this
    ///     when structural identity (`clips.count` / `overlays.count` / `duration`) is
    ///     insufficient — e.g. when you've edited a clip in place. Default `nil`.
    ///   - onLoadFailure: Optional callback invoked on the main actor if
    ///     ``Kadr/Video/makePlayerItem()`` throws. Default `nil`.
    public init(
        _ video: Video,
        reloadToken: AnyHashable? = nil,
        onLoadFailure: ((Error) -> Void)? = nil
    ) {
        self.video = video
        self.reloadToken = reloadToken
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
        .task(id: identity) {
            player = nil
            didFailToLoad = false
            do {
                let item = try await video.makePlayerItem()
                player = AVPlayer(playerItem: item)
            } catch {
                didFailToLoad = true
                onLoadFailure?(error)
            }
        }
    }

    /// Coarse fingerprint that drives `.task(id:)`. Changes when the composition's
    /// shape changes or when the caller bumps `reloadToken`.
    private var identity: Identity {
        Identity(
            clipCount: video.clips.count,
            overlayCount: video.overlays.count,
            audioTrackCount: video.audioTracks.count,
            durationSeconds: CMTimeGetSeconds(video.duration),
            reloadToken: reloadToken
        )
    }

    private struct Identity: Hashable {
        let clipCount: Int
        let overlayCount: Int
        let audioTrackCount: Int
        let durationSeconds: Double
        let reloadToken: AnyHashable?
    }
}
