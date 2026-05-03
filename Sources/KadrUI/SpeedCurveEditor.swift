import SwiftUI
import CoreMedia
import Kadr

/// A 2D keyframe editor for ``Kadr/VideoClip/speed(curve:)``. Time runs along the
/// x-axis (clip-relative, anchored to the clip's `trimRange`); speed multiplier
/// runs along a log-scaled y-axis with `1.0` rendered as a baseline gridline.
/// Existing keyframes appear as draggable markers; tapping empty area adds one
/// at the current cursor; long-pressing a marker removes it.
///
/// **Read-only model.** The editor never mutates the clip directly — `Video` is
/// immutable. Edits surface through ``SpeedCurveEditor/init(clip:currentTime:height:onUpdate:)``'s
/// `onUpdate` callback as a fresh ``Kadr/Animation`` value (or `nil` to clear);
/// the consumer rebuilds the clip via `clip.speed(curve:)` or `clip.speed(_:)`.
///
/// **Bounds.** Multipliers clamp to `0.25...4.0` per kadr's documented range.
/// Out-of-range values entered programmatically clamp at the boundaries; the
/// editor never emits a curve carrying a value outside the range.
///
/// ```swift
/// SpeedCurveEditor(
///     clip: selectedVideoClip,
///     currentTime: $playheadTime,
///     onUpdate: { newCurve in
///         // Rebuild the Video with the new curve. `nil` means clear.
///         let updated = newCurve.map { selectedVideoClip.speed(curve: $0) }
///                       ?? selectedVideoClip.speed(1.0)
///     }
/// )
/// .frame(height: 80)
/// ```
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct SpeedCurveEditor: View {

    private let clip: VideoClip
    private let currentTime: Binding<CMTime>?
    private let height: CGFloat
    private let onUpdate: (Kadr.Animation<Double>?) -> Void

    /// In-flight drag deltas keyed by the keyframe's time-ms. `width` is the
    /// horizontal pixel delta (retime); `height` is the vertical pixel delta
    /// (rescale multiplier).
    @State private var dragOffsetByKey: [Int64: CGSize] = [:]

    /// Multiplier display range (matches kadr's documented bounds).
    nonisolated public static let minMultiplier: Double = 0.25
    nonisolated public static let maxMultiplier: Double = 4.0

    /// Create a speed-curve editor for `clip`.
    /// - Parameters:
    ///   - clip: The ``Kadr/VideoClip`` whose speed curve is being authored.
    ///     The editor reads ``Kadr/VideoClip/speedCurve`` for the current
    ///     keyframe set and ``Kadr/VideoClip/trimRange`` (falling back to
    ///     ``Kadr/Clip/duration``) for the time axis range.
    ///   - currentTime: Optional binding to a composition-relative playhead.
    ///     When non-`nil`, a vertical line marks the playhead's projection
    ///     onto the clip's local time.
    ///   - height: Editor surface height in points. Default `80`.
    ///   - onUpdate: Fired when the user adds, removes, retimes, or rescales
    ///     a keyframe — or changes the timing function. Receives a fresh
    ///     ``Kadr/Animation`` (or `nil` to clear). Consumer rebuilds the
    ///     clip via `clip.speed(curve:)` or `clip.speed(_:)`.
    public init(
        clip: VideoClip,
        currentTime: Binding<CMTime>? = nil,
        height: CGFloat = 80,
        onUpdate: @escaping (Kadr.Animation<Double>?) -> Void
    ) {
        self.clip = clip
        self.currentTime = currentTime
        self.height = height
        self.onUpdate = onUpdate
    }

    public var body: some View {
        VStack(spacing: 4) {
            header
            canvas
                .frame(height: height)
        }
    }

    // MARK: - Header (TimingFunction picker + clear)

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(SpeedCurveEditor.timingPresets, id: \.0) { (label, preset) in
                    Button(label) { applyTimingPreset(preset) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(SpeedCurveEditor.timingLabel(for: clip.speedCurve?.timing ?? .linear))
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onUpdate(nil)
            } label: {
                Text("Clear")
                    .font(.caption)
            }
            .disabled(clip.speedCurve == nil)
        }
    }

    // MARK: - Canvas (keyframe markers + curve baseline)

    @ViewBuilder
    private var canvas: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let durationSeconds = SpeedCurveEditor.editorDurationSeconds(for: clip)
            let curve = clip.speedCurve
            let keyframes = curve?.keyframes ?? []

            ZStack(alignment: .topLeading) {
                // Background — also the "tap empty area to add" target.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { tap in
                                addKeyframe(at: tap.location, in: size, durationSeconds: durationSeconds)
                            }
                    )

                // 1× gridline — the "neutral speed" reference.
                let baselineY = SpeedCurveEditor.normalizedY(forMultiplier: 1.0) * size.height
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: size.width, height: 1)
                    .offset(y: size.height - baselineY - 0.5)
                    .allowsHitTesting(false)

                // Playhead — projected onto clip-local time.
                if let phX = playheadX(in: size, durationSeconds: durationSeconds) {
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1, height: size.height)
                        .offset(x: phX)
                        .allowsHitTesting(false)
                }

                // Keyframe markers.
                ForEach(keyframes, id: \.time.value) { kf in
                    keyframeMarker(kf, size: size, durationSeconds: durationSeconds)
                }
            }
        }
    }

    @ViewBuilder
    private func keyframeMarker(
        _ kf: Kadr.Animation<Double>.Keyframe,
        size: CGSize,
        durationSeconds: Double
    ) -> some View {
        let key = kf.time.value
        let basePoint = SpeedCurveEditor.point(
            for: kf,
            in: size,
            durationSeconds: durationSeconds
        )
        let dragDelta = dragOffsetByKey[key] ?? .zero
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .position(
                x: basePoint.x + dragDelta.width,
                y: basePoint.y + dragDelta.height
            )
            .gesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in removeKeyframe(at: kf.time) }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        dragOffsetByKey[key] = value.translation
                    }
                    .onEnded { value in
                        let delta = value.translation
                        dragOffsetByKey[key] = nil
                        commitKeyframeDrag(
                            originalKeyframe: kf,
                            translation: delta,
                            size: size,
                            durationSeconds: durationSeconds
                        )
                    }
            )
    }

    // MARK: - Edit operations

    private func addKeyframe(at location: CGPoint, in size: CGSize, durationSeconds: Double) {
        guard durationSeconds > 0 else { return }
        let (time, multiplier) = SpeedCurveEditor.locationToKeyframe(
            location: location,
            in: size,
            durationSeconds: durationSeconds
        )
        let kf = Kadr.Animation<Double>.Keyframe(time: time, value: multiplier)
        let existing = clip.speedCurve?.keyframes ?? []
        let timing = clip.speedCurve?.timing ?? .linear
        let updated = SpeedCurveEditor.keyframesByAdding(kf, to: existing)
        onUpdate(Kadr.Animation<Double>.keyframes(updated, timing: timing))
    }

    private func removeKeyframe(at time: CMTime) {
        guard let curve = clip.speedCurve else { return }
        let updated = SpeedCurveEditor.keyframesByRemoving(at: time, from: curve.keyframes)
        if updated.isEmpty {
            onUpdate(nil)
        } else {
            onUpdate(Kadr.Animation<Double>.keyframes(updated, timing: curve.timing))
        }
    }

    private func commitKeyframeDrag(
        originalKeyframe kf: Kadr.Animation<Double>.Keyframe,
        translation: CGSize,
        size: CGSize,
        durationSeconds: Double
    ) {
        guard durationSeconds > 0, let curve = clip.speedCurve else { return }
        let (newTime, newValue) = SpeedCurveEditor.draggedKeyframe(
            original: kf,
            translation: translation,
            size: size,
            durationSeconds: durationSeconds
        )
        if CMTimeCompare(newTime, kf.time) == 0, newValue == kf.value { return }
        let replaced = SpeedCurveEditor.keyframesByReplacing(
            at: kf.time,
            with: Kadr.Animation<Double>.Keyframe(time: newTime, value: newValue),
            in: curve.keyframes
        )
        onUpdate(Kadr.Animation<Double>.keyframes(replaced, timing: curve.timing))
    }

    private func applyTimingPreset(_ timing: TimingFunction) {
        guard let curve = clip.speedCurve else {
            // Picking a timing function with no curve yet does nothing — user must add
            // at least one keyframe first.
            return
        }
        onUpdate(Kadr.Animation<Double>.keyframes(curve.keyframes, timing: timing))
    }

    // MARK: - Playhead projection

    private func playheadX(in size: CGSize, durationSeconds: Double) -> CGFloat? {
        guard durationSeconds > 0, let currentTime else { return nil }
        let phSec = CMTimeGetSeconds(currentTime.wrappedValue)
        guard phSec >= 0, phSec <= durationSeconds else { return nil }
        return CGFloat(phSec / durationSeconds) * size.width
    }
}

// MARK: - Pure helpers

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension SpeedCurveEditor {

    /// Time-axis duration in seconds for a clip's speed-curve editor. Prefers
    /// `trimRange.duration` (the authoring domain per kadr v0.9 docs); falls
    /// back to the clip's reported `duration` when no trim is set. Returns
    /// `0` when neither is available — the editor renders an empty surface.
    nonisolated public static func editorDurationSeconds(for clip: VideoClip) -> Double {
        if let range = clip.trimRange {
            return CMTimeGetSeconds(range.duration)
        }
        let dur = CMTimeGetSeconds(clip.duration)
        return dur.isFinite && dur > 0 ? dur : 0
    }

    /// Clamp a multiplier to the documented `0.25...4.0` range. Out-of-range
    /// values pin at the nearest boundary rather than throwing.
    nonisolated public static func clampMultiplier(_ value: Double) -> Double {
        max(minMultiplier, min(maxMultiplier, value))
    }

    /// Map a multiplier to a normalized `[0, 1]` y-coordinate using a log2
    /// scale so that `0.5×` and `2×` are equidistant from the `1.0` baseline.
    /// Bottom of the canvas (y = 0) is the slowest playback (`0.25×`); top
    /// (y = 1) is the fastest (`4.0×`).
    nonisolated public static func normalizedY(forMultiplier multiplier: Double) -> Double {
        let clamped = clampMultiplier(multiplier)
        let logVal = log2(clamped) // -2 ... +2
        return (logVal + 2) / 4    // 0 ... 1
    }

    /// Inverse of ``normalizedY(forMultiplier:)``. Maps a normalized y
    /// coordinate back to a multiplier, clamped to the documented range.
    nonisolated public static func multiplier(forNormalizedY y: Double) -> Double {
        let clamped = max(0, min(1, y))
        let logVal = clamped * 4 - 2  // -2 ... +2
        return clampMultiplier(pow(2, logVal))
    }

    /// Project a keyframe to a point inside the editor canvas.
    nonisolated public static func point(
        for kf: Kadr.Animation<Double>.Keyframe,
        in size: CGSize,
        durationSeconds: Double
    ) -> CGPoint {
        guard durationSeconds > 0 else { return .zero }
        let timeSec = CMTimeGetSeconds(kf.time)
        let xN = max(0, min(1, timeSec / durationSeconds))
        let yN = normalizedY(forMultiplier: kf.value)
        return CGPoint(
            x: CGFloat(xN) * size.width,
            // Flip y so larger multipliers render *higher*.
            y: size.height - CGFloat(yN) * size.height
        )
    }

    /// Map a tap or drop location inside the canvas back to a `(time, multiplier)`
    /// pair. Time is clipped to `0...durationSeconds`; multiplier to the
    /// documented multiplier range.
    nonisolated public static func locationToKeyframe(
        location: CGPoint,
        in size: CGSize,
        durationSeconds: Double
    ) -> (time: CMTime, multiplier: Double) {
        guard size.width > 0, size.height > 0, durationSeconds > 0 else {
            return (.zero, 1.0)
        }
        let xN = max(0, min(1, Double(location.x / size.width)))
        let timeSec = xN * durationSeconds
        let time = CMTime(seconds: timeSec, preferredTimescale: 600)
        let yN = max(0, min(1, 1.0 - Double(location.y / size.height)))
        let multiplier = multiplier(forNormalizedY: yN)
        return (time, multiplier)
    }

    /// Apply a drag translation to a keyframe and return its new `(time, value)`.
    nonisolated public static func draggedKeyframe(
        original: Kadr.Animation<Double>.Keyframe,
        translation: CGSize,
        size: CGSize,
        durationSeconds: Double
    ) -> (time: CMTime, value: Double) {
        guard durationSeconds > 0, size.width > 0, size.height > 0 else {
            return (original.time, original.value)
        }
        let basePoint = point(for: original, in: size, durationSeconds: durationSeconds)
        let newPoint = CGPoint(
            x: basePoint.x + translation.width,
            y: basePoint.y + translation.height
        )
        let resolved = locationToKeyframe(
            location: newPoint,
            in: size,
            durationSeconds: durationSeconds
        )
        return (resolved.time, resolved.multiplier)
    }

    /// Insert a keyframe into the array, sorted by time. If a keyframe already
    /// exists at the same time-ms, it is replaced (last-write-wins).
    nonisolated public static func keyframesByAdding(
        _ kf: Kadr.Animation<Double>.Keyframe,
        to existing: [Kadr.Animation<Double>.Keyframe]
    ) -> [Kadr.Animation<Double>.Keyframe] {
        var result = existing.filter { $0.time.value != kf.time.value }
        result.append(Kadr.Animation<Double>.Keyframe(
            time: kf.time,
            value: clampMultiplier(kf.value)
        ))
        result.sort { CMTimeCompare($0.time, $1.time) < 0 }
        return result
    }

    /// Remove every keyframe matching `time` (by time-ms equality).
    nonisolated public static func keyframesByRemoving(
        at time: CMTime,
        from existing: [Kadr.Animation<Double>.Keyframe]
    ) -> [Kadr.Animation<Double>.Keyframe] {
        existing.filter { $0.time.value != time.value }
    }

    /// Replace the keyframe at `time` with `replacement`, preserving sort order.
    /// If the replacement collides with another keyframe's time, the other one
    /// is dropped (the dragged marker wins).
    nonisolated public static func keyframesByReplacing(
        at time: CMTime,
        with replacement: Kadr.Animation<Double>.Keyframe,
        in existing: [Kadr.Animation<Double>.Keyframe]
    ) -> [Kadr.Animation<Double>.Keyframe] {
        var result = existing.filter {
            $0.time.value != time.value && $0.time.value != replacement.time.value
        }
        result.append(Kadr.Animation<Double>.Keyframe(
            time: replacement.time,
            value: clampMultiplier(replacement.value)
        ))
        result.sort { CMTimeCompare($0.time, $1.time) < 0 }
        return result
    }

    // MARK: - TimingFunction labels & presets

    /// Human-readable label for a `TimingFunction`. Custom / cubicBezier render
    /// as generic strings — the picker only emits the four named presets.
    nonisolated public static func timingLabel(for timing: TimingFunction) -> String {
        switch timing {
        case .linear:        return "Linear"
        case .easeIn:        return "Ease In"
        case .easeOut:       return "Ease Out"
        case .easeInOut:     return "Ease In Out"
        case .cubicBezier:   return "Cubic Bézier"
        case .custom:        return "Custom"
        }
    }

    /// Preset list rendered in the timing-function picker. Cubic Bézier and
    /// Custom are intentionally absent — consumers wanting either build the
    /// `TimingFunction` themselves and pass via `clip.speed(curve:)`.
    nonisolated public static let timingPresets: [(String, TimingFunction)] = [
        ("Linear",        .linear),
        ("Ease In",       .easeIn),
        ("Ease Out",      .easeOut),
        ("Ease In Out",   .easeInOut),
    ]
}
