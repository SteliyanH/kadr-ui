import SwiftUI
import CoreMedia
import Kadr

/// Playback controls for a composition: skip back, play/pause, skip forward, a
/// time readout, and optional loop and full-screen toggles.
///
/// ``VideoPreview`` takes `isPlaying` and `currentTime` as two-way bindings and
/// will follow whatever you write to them — but it ships no controls, so every
/// consumer that wanted a play button built one. This is that strip.
///
/// ```swift
/// VStack {
///     VideoPreview(video, isPlaying: $isPlaying, currentTime: $currentTime)
///     TransportBand(
///         duration: video.duration,
///         currentTime: $currentTime,
///         isPlaying: $isPlaying,
///         isLooping: $isLooping
///     )
/// }
/// ```
///
/// ## Bindings, not callbacks
///
/// The rest of this package hands you a value and calls back with an edit,
/// because a `Video` is immutable and you have to rebuild it. Transport state
/// is different: it is genuinely two-way, it is *yours*, and ``VideoPreview``
/// already takes it as bindings. Callbacks here would mean writing the same
/// state through two different shapes in the same `VStack`.
///
/// ## The band never touches AVPlayer
///
/// Everything it does is a write to the bindings. That keeps it testable — the
/// decisions are static functions, exposed below, and the view is the thin part
/// over them.
///
/// Added in v0.20.
public struct TransportBand: View {

    @Environment(\.kadrAppearance) private var appearance

    private let duration: CMTime
    private let currentTime: Binding<CMTime>
    private let isPlaying: Binding<Bool>
    private let isLooping: Binding<Bool>?
    private let isFullscreen: Binding<Bool>?
    private let skipInterval: TimeInterval

    /// Set by the pause half of the play/pause button, cleared by the next
    /// `isPlaying` observation.
    ///
    /// Without it, pausing by hand inside ``endOfPlaybackTolerance`` of the end
    /// is indistinguishable from playback running out — both arrive as
    /// `isPlaying` going false with the playhead at the end — and loop would
    /// drag the viewer back to zero after they deliberately stopped.
    @State private var suppressLoopRestart = false

    /// Create a transport band.
    ///
    /// - Parameters:
    ///   - duration: the composition's length. `Video.duration` is the usual
    ///     source. A zero or indefinite duration disables the controls rather
    ///     than offering a play button that does nothing.
    ///   - currentTime: the playhead, shared with ``VideoPreview``.
    ///   - isPlaying: playback state, shared with ``VideoPreview``.
    ///   - isLooping: pass `nil` to hide the loop control. When bound, the band
    ///     restarts playback itself — do **not** also pass `loops: true` to
    ///     `VideoPreview`, or the two will fight over the playhead.
    ///   - isFullscreen: pass `nil` to hide the full-screen control. The band
    ///     only toggles the value; what "full screen" means is yours.
    ///   - skipInterval: seconds per skip. One second by default, which is a
    ///     frame-ish nudge at a glance rather than a scrub.
    public init(
        duration: CMTime,
        currentTime: Binding<CMTime>,
        isPlaying: Binding<Bool>,
        isLooping: Binding<Bool>? = nil,
        isFullscreen: Binding<Bool>? = nil,
        skipInterval: TimeInterval = TransportBand.defaultSkipInterval
    ) {
        self.duration = duration
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.isLooping = isLooping
        self.isFullscreen = isFullscreen
        self.skipInterval = skipInterval
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Two flexible frames split whatever the readout does not take
            // *equally*, which is what actually centres it: the leading group
            // is three cells wide and the trailing group at most two, so a
            // plain Spacer() pair would sit the readout off-centre.
            transportGroup
                .frame(maxWidth: .infinity, alignment: .leading)
            timeReadout
            trailingGroup
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: isPlaying.wrappedValue) { wasPlaying, playing in
            restartForLoopIfNeeded(wasPlaying: wasPlaying, isPlaying: playing)
        }
    }

    // MARK: - Groups

    @ViewBuilder
    private var transportGroup: some View {
        HStack(spacing: 4) {
            button(
                systemImage: TransportBand.skipBackSymbol,
                label: TransportBand.skipBackLabel,
                disabled: !TransportBand.canPlay(duration: duration)
                    || TransportBand.isAtStart(currentTime.wrappedValue)
            ) {
                currentTime.wrappedValue = TransportBand.skipTarget(
                    from: currentTime.wrappedValue, by: -skipInterval, duration: duration
                )
            }

            button(
                systemImage: isPlaying.wrappedValue ? "pause.fill" : "play.fill",
                label: TransportBand.playPauseLabel(isPlaying: isPlaying.wrappedValue),
                disabled: !TransportBand.canPlay(duration: duration),
                size: TransportBand.playGlyphSize
            ) {
                // Record the intent *before* the state changes: a deliberate
                // pause near the end must not read as playback ending.
                if isPlaying.wrappedValue { suppressLoopRestart = true }
                isPlaying.wrappedValue.toggle()
            }

            button(
                systemImage: TransportBand.skipForwardSymbol,
                label: TransportBand.skipForwardLabel,
                disabled: !TransportBand.canPlay(duration: duration)
                    || TransportBand.isAtEnd(currentTime.wrappedValue, duration: duration)
            ) {
                currentTime.wrappedValue = TransportBand.skipTarget(
                    from: currentTime.wrappedValue, by: skipInterval, duration: duration
                )
            }
        }
    }

    @ViewBuilder
    private var timeReadout: some View {
        let elapsed = TransportBand.timecode(currentTime.wrappedValue)
        let total = TransportBand.durationTimecode(duration)
        HStack(spacing: 2) {
            Text(elapsed).foregroundStyle(.primary)
            Text("/").foregroundStyle(.secondary)
            Text(total).foregroundStyle(.secondary)
        }
        .font(appearance.timecodeFont)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TransportBand.timeReadoutLabel(elapsed: elapsed, total: total))
    }

    @ViewBuilder
    private var trailingGroup: some View {
        HStack(spacing: 4) {
            if let isLooping {
                button(
                    systemImage: "repeat",
                    label: TransportBand.loopLabel,
                    disabled: false,
                    tinted: isLooping.wrappedValue
                ) {
                    isLooping.wrappedValue.toggle()
                }
                .accessibilityValue(TransportBand.loopValueLabel(isLooping: isLooping.wrappedValue))
            }
            if let isFullscreen {
                button(
                    systemImage: isFullscreen.wrappedValue
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right",
                    label: TransportBand.fullscreenLabel(isFullscreen: isFullscreen.wrappedValue),
                    disabled: false
                ) {
                    isFullscreen.wrappedValue.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private func button(
        systemImage: String,
        label: String,
        disabled: Bool,
        size: CGFloat = 17,
        tinted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .frame(width: 44, height: 44)          // the minimum hit target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundStyle(tinted ? appearance.playhead : .primary)
        .accessibilityLabel(label)
    }

    // MARK: - Loop

    private func restartForLoopIfNeeded(wasPlaying: Bool, isPlaying playing: Bool) {
        defer { if !playing { suppressLoopRestart = false } }
        guard !suppressLoopRestart, let isLooping, isLooping.wrappedValue else { return }
        guard TransportBand.shouldRestartForLoop(
            wasPlaying: wasPlaying,
            isPlaying: playing,
            isLooping: isLooping.wrappedValue,
            current: currentTime.wrappedValue,
            duration: duration
        ) else { return }
        currentTime.wrappedValue = .zero
        self.isPlaying.wrappedValue = true
    }
}

// MARK: - The decisions, as pure functions
//
// Every judgement the band makes lives here rather than in the body, so it can
// be tested without a rendering host — and so a consumer building different
// chrome can reuse the reasoning instead of re-deriving it.

extension TransportBand {

    /// Seconds per skip. A nudge, not a scrub.
    public static let defaultSkipInterval: TimeInterval = 1.0

    /// The skip-back glyph.
    ///
    /// Unnumbered on purpose: SF Symbols' "go" family carries `.5` / `.10` /
    /// `.15` / `.30` / `.45` / `.60` / `.75` / `.90` and **no `.1`**, so a
    /// numbered name resolves to nothing and draws a placeholder.
    /// `Image(systemName:)` fails silently — it logs and renders a blank — and
    /// the compiler only ever sees a `String`, so nothing in a build catches a
    /// name that does not exist. Named here so a test can assert the running
    /// system actually vends it.
    public static let skipBackSymbol = "gobackward"

    /// The skip-forward glyph. Same rule, same reason for being named.
    public static let skipForwardSymbol = "goforward"

    /// The play/pause glyph size, in points. Larger than its neighbours because
    /// it is the primary control.
    public static let playGlyphSize: CGFloat = 26

    /// Tolerance for "the playhead is sitting on a bound", in seconds.
    ///
    /// Small enough that a scrub to 0.02s leaves skip-back live — it has real
    /// work to do — and only floating-point noise reads as *at* the bound.
    public static let boundEpsilon: Double = 0.001

    /// Tolerance for "playback ran out", in seconds.
    ///
    /// Deliberately looser than ``boundEpsilon``, because it answers a
    /// different question. A player's time observer ticks every 0.1s and
    /// compares against the *player item's* duration, which need not be
    /// bit-identical to the composition duration you computed; the last
    /// position it publishes can land just short. One and a half ticks of slack
    /// catches a real ending without reaching so far back that an ordinary
    /// pause looks like one.
    public static let endOfPlaybackTolerance: Double = 0.15

    /// `m:ss` — "0:01", "0:06", "1:05".
    ///
    /// Truncates rather than rounds. A playhead 900 ms into the first second is
    /// still in second zero, and a readout that says "0:01" before the playhead
    /// has reached one second reads as a bug. Indefinite and negative times
    /// clamp to "0:00".
    public static func timecode(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// `m:ss` for a *duration*, where the nearest second is the honest answer
    /// rather than the one the playhead has passed.
    public static func durationTimecode(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// Where a skip lands, clamped to the composition.
    public static func skipTarget(
        from current: CMTime,
        by delta: TimeInterval,
        duration: CMTime
    ) -> CMTime {
        let now = CMTimeGetSeconds(current)
        let end = CMTimeGetSeconds(duration)
        let ceiling = (end.isFinite && end > 0) ? end : 0
        let start = now.isFinite ? now : 0
        return CMTime(seconds: min(max(start + delta, 0), ceiling), preferredTimescale: 600)
    }

    /// The playhead is on the zero bound — skip-back has nowhere to go.
    public static func isAtStart(_ time: CMTime) -> Bool {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return true }
        return seconds <= boundEpsilon
    }

    /// The playhead is on the duration bound. A composition with no duration is
    /// both bounds at once.
    public static func isAtEnd(_ time: CMTime, duration: CMTime) -> Bool {
        let end = CMTimeGetSeconds(duration)
        guard end.isFinite, end > 0 else { return true }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return false }
        return seconds >= end - boundEpsilon
    }

    /// There is something to play. An empty composition gets a dead play button
    /// rather than one that appears to work.
    public static func canPlay(duration: CMTime) -> Bool {
        let end = CMTimeGetSeconds(duration)
        return end.isFinite && end > 0
    }

    /// Playback reached the end, within the observer's slack.
    ///
    /// Distinct from ``isAtEnd(_:duration:)``, which answers a *bound* question
    /// with a tight tolerance. This answers a *timing* question.
    public static func reachedEndOfPlayback(_ time: CMTime, duration: CMTime) -> Bool {
        let end = CMTimeGetSeconds(duration)
        guard end.isFinite, end > 0 else { return false }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return false }
        return seconds >= end - endOfPlaybackTolerance
    }

    /// Whether an `isPlaying` fall should be answered by starting over.
    ///
    /// Every clause earns its place: it has to be a *fall* (a rise is the
    /// restart's own echo), loop has to be on, and the playhead has to be at
    /// the end — otherwise the fall is a pause, not an ending.
    public static func shouldRestartForLoop(
        wasPlaying: Bool,
        isPlaying: Bool,
        isLooping: Bool,
        current: CMTime,
        duration: CMTime
    ) -> Bool {
        guard wasPlaying, !isPlaying, isLooping else { return false }
        return reachedEndOfPlayback(current, duration: duration)
    }

    // MARK: - Spoken copy
    //
    // Plain English. KadrUI ships no localisation; a consumer that localises
    // can supply its own labels around these controls, and these read
    // correctly to VoiceOver in the meantime.

    public static func playPauseLabel(isPlaying: Bool) -> String {
        isPlaying ? "Pause" : "Play"
    }

    public static var skipBackLabel: String { "Skip back" }
    public static var skipForwardLabel: String { "Skip forward" }
    public static var loopLabel: String { "Loop" }

    public static func loopValueLabel(isLooping: Bool) -> String {
        isLooping ? "On" : "Off"
    }

    public static func fullscreenLabel(isFullscreen: Bool) -> String {
        isFullscreen ? "Exit full screen" : "Full screen"
    }

    /// One spoken string for the readout, so VoiceOver says "1 minute 5 seconds
    /// of 2 minutes" rather than reading "1:05 / 2:00" as punctuation.
    public static func timeReadoutLabel(elapsed: String, total: String) -> String {
        "\(elapsed) of \(total)"
    }
}
