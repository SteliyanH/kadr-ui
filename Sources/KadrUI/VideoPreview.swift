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
    private let isPlaying: Binding<Bool>?
    private let currentTime: Binding<CMTime>?
    private let loops: Bool
    private let showsPlaybackControls: Bool

    @State private var player: AVPlayer?
    @State private var didFailToLoad = false

    /// Reference box so the periodic observer reads the *current* loop setting.
    ///
    /// The observer closure is created once per player and captures by value, so
    /// a plain `loops` read inside it would freeze at whatever the flag was when
    /// the player was built. That is the bug this box exists to remove: a caller
    /// binding a loop toggle to `loops:` saw it do nothing until something else
    /// happened to rebuild the player.
    @State private var loopBox = LoopBox()

    /// The last position this view pushed into `currentTime` itself.
    ///
    /// `onChange(of:)` cannot tell a caller's seek from the echo of our own
    /// observer write. Comparing against this lets the echo be dropped exactly,
    /// which is what allows the seek threshold below to be frame-scale instead
    /// of a blunt 0.05s — see `seekEpsilon`.
    @State private var lastPushedTime: CMTime?

    /// Attached only when sampling is requested. An `AVPlayerItemVideoOutput`
    /// makes the decoder hand back every frame in BGRA, which costs memory and
    /// bandwidth for callers that never sample — so it is opt-in.
    @State private var videoOutput: AVPlayerItemVideoOutput?

    /// Periodic observer that pushes playback position back into `currentTime`.
    /// Held so it can be removed — an un-removed observer retains the player.
    @State private var timeObserver: Any?

    /// Guards the feedback loop between `currentTime` and the observer: without
    /// it, every tick writes the binding, which seeks, which ticks.
    @State private var isSeekingFromBinding = false

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
    ///   - isPlaying: Optional two-way playback state. Set it to start or stop;
    ///     it flips back to `false` on its own when a non-looping composition
    ///     reaches the end, so a caller's play button does not lie.
    ///   - currentTime: Optional two-way playhead. Writes seek; playback writes
    ///     back roughly 10x a second. Share it with `TimelineView`'s
    ///     `currentTime` and the two stay in step.
    ///   - loops: When `true`, playback restarts at zero instead of stopping.
    ///     Deliberately a plain value, not persisted state — looping is a
    ///     session preference, and the package has no business owning it.
    public init(
        _ video: Video,
        isPlaying: Binding<Bool>? = nil,
        currentTime: Binding<CMTime>? = nil,
        loops: Bool = false,
        showsPlaybackControls: Bool = true,
        reloadToken: AnyHashable? = nil,
        onLoadFailure: ((Error) -> Void)? = nil,
        onSampleColor: ((KadrSampledColor) -> Void)? = nil
    ) {
        self.video = video
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.loops = loops
        self.showsPlaybackControls = showsPlaybackControls
        self.reloadToken = reloadToken
        self.onLoadFailure = onLoadFailure
        self.onSampleColor = onSampleColor
    }

    public var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    // AVKit surfaces its own transport on tap, and a host that
                    // draws its own controls ends up with two that do not agree.
                    // Blocking hit-testing keeps AVKit's chrome from appearing;
                    // hiding the subtree closes the other door, because an
                    // accessibility activation is delivered straight to the
                    // UIKit element and never consults hit-testing at all.
                    .allowsHitTesting(showsPlaybackControls)
                    .accessibilityHidden(!showsPlaybackControls)
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
        .onDisappear {
            // An un-removed periodic observer retains the player, and with it
            // the decoded item.
            if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
            timeObserver = nil
        }
        .onChange(of: loops) { _, nowLoops in
            // Both halves matter: `actionAtItemEnd` governs what AVFoundation
            // does on its own, and the box governs what the observer does when
            // it sees the end. Updating only one leaves them disagreeing.
            loopBox.loops = nowLoops
            player?.actionAtItemEnd = nowLoops ? .none : .pause
        }
        .onChange(of: isPlaying?.wrappedValue ?? false) { _, playing in
            guard let player else { return }
            playing ? player.play() : player.pause()
        }
        .onChange(of: currentTime?.wrappedValue ?? .zero) { _, time in
            guard let player, currentTime != nil else { return }
            // Drop the echo of our own observer write exactly, rather than
            // approximately. Previously this was a 0.05s threshold, which also
            // swallowed every deliberate seek smaller than that — one frame at
            // 30fps is 0.033s, so frame-stepping was impossible: the button
            // moved the binding and nothing happened.
            if let lastPushedTime, time == lastPushedTime { return }
            guard abs(CMTimeGetSeconds(player.currentTime()) - CMTimeGetSeconds(time)) > VideoPreview.seekEpsilon else { return }
            isSeekingFromBinding = true
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                isSeekingFromBinding = false
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
                let newPlayer = AVPlayer(playerItem: item)
                newPlayer.actionAtItemEnd = loops ? .none : .pause
                attachTimeObserver(to: newPlayer)
                player = newPlayer
                if isPlaying?.wrappedValue == true { newPlayer.play() }
            } catch {
                didFailToLoad = true
                onLoadFailure?(error)
            }
        }
    }

    /// Pushes playback position into `currentTime` ~10x a second, and clears
    /// `isPlaying` when a non-looping composition ends.
    private func attachTimeObserver(to player: AVPlayer) {
        loopBox.loops = loops
        player.actionAtItemEnd = loops ? .none : .pause
        guard currentTime != nil || isPlaying != nil || loops else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            // Skip the tick that our own seek produced, or the binding would
            // fight the observer.
            guard !isSeekingFromBinding else { return }

            if let currentTime, currentTime.wrappedValue != time {
                lastPushedTime = time
                currentTime.wrappedValue = time
            }

            guard let item = player.currentItem, item.duration.isNumeric else { return }
            let atEnd = time >= item.duration
            if atEnd {
                if loopBox.loops {
                    player.seek(to: .zero)
                    player.play()
                } else if isPlaying?.wrappedValue == true {
                    // The player pauses itself at the end; reflect that, so a
                    // caller's play button does not sit stuck on "pause".
                    isPlaying?.wrappedValue = false
                }
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
    private var identity: CompositionIdentity {
        VideoPreview.compositionIdentity(of: video, reloadToken: reloadToken)
    }

    /// Smallest position change treated as a deliberate seek.
    ///
    /// A quarter of a frame at 120fps. Small enough that frame-stepping at any
    /// normal frame rate goes through, large enough to absorb timescale
    /// rounding.
    public nonisolated static let seekEpsilon: Double = 0.002

    /// The fingerprint this view uses to decide the player must be rebuilt.
    ///
    /// Exposed because a host driving playback needs to know a rebuild is
    /// coming: the outgoing player's periodic observer is removed in
    /// `onDisappear`, which does not run on a rebuild, so an in-flight
    /// composition edit can leave two players writing to one binding. Consumers
    /// were reconstructing this fingerprint by hand from the same four inputs,
    /// which silently rots the moment this definition changes.
    public nonisolated static func compositionIdentity(
        of video: Video,
        reloadToken: AnyHashable? = nil
    ) -> CompositionIdentity {
        CompositionIdentity(
            clipCount: video.clips.count,
            overlayCount: video.overlays.count,
            audioTrackCount: video.audioTracks.count,
            durationSeconds: CMTimeGetSeconds(video.duration),
            reloadToken: reloadToken
        )
    }

    /// Structural fingerprint of a composition, as `VideoPreview` sees it.
    public struct CompositionIdentity: Hashable {

        public let clipCount: Int
        public let overlayCount: Int
        public let audioTrackCount: Int
        public let durationSeconds: Double
        public let reloadToken: AnyHashable?
    }

    /// Mutable cell shared with the periodic observer. See `loopBox`.
    final class LoopBox: @unchecked Sendable {
        var loops = false
    }
}

// MARK: - Test seams

extension VideoPreview {
    /// Lets a test assert the default without constructing a player.
    var showsPlaybackControlsForTesting: Bool { showsPlaybackControls }
}


extension VideoPreview {
    /// Exposes `loops` for tests. The stored property stays private so callers
    /// cannot mistake it for public API.
    var loopsForTesting: Bool { loops }
}
