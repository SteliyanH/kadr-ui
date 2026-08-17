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
public struct VideoPreview: View {

    /// v0.13 — appearance tokens; defaults reproduce pre-0.13 rendering.
    @Environment(\.kadrAppearance) private var appearance

    private let video: Video
    private let reloadToken: AnyHashable?
    private let onLoadFailure: ((Error) -> Void)?
    private let onSampleColor: ((KadrSampledColor) -> Void)?

    @State private var player: AVPlayer?
    @State private var didFailToLoad = false

    /// Attached only when sampling is requested. An `AVPlayerItemVideoOutput`
    /// makes the decoder hand back every frame in BGRA, which costs memory and
    /// bandwidth for callers that never sample — so it is opt-in.
    @State private var videoOutput: AVPlayerItemVideoOutput?

    /// Create a preview for `video`.
    /// - Parameters:
    ///   - video: The Kadr composition to preview.
    ///   - reloadToken: Optional value that triggers a reload when it changes. Use this
    ///     when structural identity (`clips.count` / `overlays.count` / `duration`) is
    ///     insufficient — e.g. when you've edited a clip in place. Default `nil`.
    ///   - onLoadFailure: Optional callback invoked on the main actor if
    ///     ``Kadr/Video/makePlayerItem()`` throws. Default `nil`.
    ///   - onSampleColor: Optional eyedropper. When set, a tap on the picture
    ///     reports the colour under it plus the normalised point, so the caller
    ///     can draw a reticle. Taps in the letterbox bars report nothing —
    ///     `nil` rather than the surround's black, which would be a colour the
    ///     caller could not tell apart from real footage. Passing `nil` (the
    ///     default) leaves playback untouched and attaches no video output.
    public init(
        _ video: Video,
        reloadToken: AnyHashable? = nil,
        onLoadFailure: ((Error) -> Void)? = nil,
        onSampleColor: ((KadrSampledColor) -> Void)? = nil
    ) {
        self.video = video
        self.reloadToken = reloadToken
        self.onLoadFailure = onLoadFailure
        self.onSampleColor = onSampleColor
    }

    public var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .overlay { if onSampleColor != nil { samplingLayer } }
            } else if didFailToLoad {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Preview failed to load")
            } else {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Loading preview")
            }
        }
        .task(id: identity) {
            player = nil
            didFailToLoad = false
            do {
                let item = try await video.makePlayerItem()
                if onSampleColor != nil {
                    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ])
                    item.add(output)
                    videoOutput = output
                }
                player = AVPlayer(playerItem: item)
            } catch {
                didFailToLoad = true
                onLoadFailure?(error)
            }
        }
    }

    /// Transparent tap target over the picture. Only built when sampling is on,
    /// so the default preview keeps AVKit's own gesture handling untouched.
    @ViewBuilder
    private var samplingLayer: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    // DragGesture with zero distance rather than onTapGesture:
                    // it reports the location, which is the whole point here.
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in sample(at: value.location, in: proxy.size) }
                )
                .accessibilityLabel("Sample colour from the frame")
                .accessibilityHint("Double tap a point in the picture to pick its colour")
        }
    }

    /// Resolves a tap to a colour, or does nothing if it cannot.
    private func sample(at point: CGPoint, in bounds: CGSize) {
        guard let onSampleColor, let player, let output = videoOutput else { return }

        let presentation = player.currentItem?.presentationSize ?? .zero
        guard let normalized = VideoSampling.normalizedPoint(
            forTapAt: point, in: bounds, presentation: presentation
        ) else { return }   // letterbox bar, or size not resolved yet

        // `hasNewPixelBuffer` is deliberately not consulted: it answers "has the
        // frame changed since the last copy", which is false on a paused player —
        // exactly when someone is most likely to be picking a colour.
        // `copyPixelBuffer` still returns the current frame; a nil result is
        // handled by the guard.
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil),
              let rgb = VideoSampling.rgb(at: normalized, in: buffer)
        else { return }

        onSampleColor(
            KadrSampledColor(
                color: Color(red: rgb.red, green: rgb.green, blue: rgb.blue),
                point: normalized
            )
        )
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
