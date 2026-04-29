import SwiftUI
import CoreMedia
import Kadr

/// Identifies an animatable property surfaced as a row in ``KeyframeEditor``.
public enum KeyframeProperty: Sendable, Hashable {
    /// The clip's ``Kadr/Clip/transform``. Drives ``Kadr/Clip/transformAnimation``.
    case transform
    /// The clip's ``Kadr/Clip/opacity``. Drives ``Kadr/Clip/opacityAnimation``.
    case opacity
    /// A ``Kadr/VideoClip/filters`` entry by index. Drives the matching
    /// ``Kadr/VideoClip/filterAnimations`` entry. Out-of-range indices are dropped at
    /// render time.
    case filter(index: Int)
}

/// A keyframe-track surface paired with a ``TimelineView`` and an
/// ``InspectorPanel``: shows one row per animatable property of the selected clip,
/// each row spans the clip's full lifetime, and existing keyframes render as
/// markers placed by clip-relative time.
///
/// **Gestures.** Tap an empty area on a row to add a keyframe at the current playhead
/// (the playhead is mapped to clip-relative time via the clip's start in the
/// composition). Long-press a marker to remove it. Drag a marker horizontally to
/// retime — the editor reports the new time via `onRetime` on release.
///
/// **Read-only model.** Like ``TimelineView``, the editor never mutates the `Video` —
/// `Video` is immutable. All edits surface through callbacks; the consumer rebuilds
/// the composition.
///
/// ```swift
/// VStack(spacing: 8) {
///     TimelineView(video, currentTime: $time, selectedClipID: $selectedID)
///     KeyframeEditor(
///         video,
///         selectedClipID: $selectedID,
///         currentTime: $time,
///         onAdd: { id, prop, t in /* rebuild Video */ },
///         onRemove: { id, prop, t in /* rebuild Video */ },
///         onRetime: { id, prop, from, to in /* rebuild Video */ }
///     )
/// }
/// ```
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct KeyframeEditor: View {

    private let video: Video
    private let selectedClipID: Binding<ClipID?>
    private let currentTime: Binding<CMTime>
    private let rowHeight: CGFloat
    private let rowSpacing: CGFloat
    private let onAdd: ((ClipID, KeyframeProperty, CMTime) -> Void)?
    private let onRemove: ((ClipID, KeyframeProperty, CMTime) -> Void)?
    private let onRetime: ((ClipID, KeyframeProperty, _ from: CMTime, _ to: CMTime) -> Void)?

    /// Pixel offset of the in-flight retime drag, keyed by the keyframe being dragged.
    @State private var dragOffsetByKey: [KeyframeKey: CGFloat] = [:]

    /// A drag-target identity: which clip's which property's which keyframe time.
    private struct KeyframeKey: Hashable {
        let clipID: ClipID
        let property: KeyframeProperty
        let timeMs: Int64
    }

    /// Create a keyframe editor.
    /// - Parameters:
    ///   - video: The composition. Read-only.
    ///   - selectedClipID: Binding shared with ``TimelineView`` / ``InspectorPanel``.
    ///   - currentTime: Binding to composition-relative playhead time. Used to compute
    ///     the clip-relative tap-to-add time.
    ///   - rowHeight: Per-property row height in points. Default `24`.
    ///   - rowSpacing: Vertical spacing between rows. Default `4`.
    ///   - onAdd: Fires when the user taps an empty area on a row. Receives the clip
    ///     ID, the property, and the **clip-relative** time.
    ///   - onRemove: Fires on long-press of a marker. Receives the clip-relative time
    ///     of the marker.
    ///   - onRetime: Fires on release of a marker drag. Receives the previous and new
    ///     clip-relative times.
    public init(
        _ video: Video,
        selectedClipID: Binding<ClipID?>,
        currentTime: Binding<CMTime>,
        rowHeight: CGFloat = 24,
        rowSpacing: CGFloat = 4,
        onAdd: ((ClipID, KeyframeProperty, CMTime) -> Void)? = nil,
        onRemove: ((ClipID, KeyframeProperty, CMTime) -> Void)? = nil,
        onRetime: ((ClipID, KeyframeProperty, _ from: CMTime, _ to: CMTime) -> Void)? = nil
    ) {
        self.video = video
        self.selectedClipID = selectedClipID
        self.currentTime = currentTime
        self.rowHeight = rowHeight
        self.rowSpacing = rowSpacing
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onRetime = onRetime
    }

    public var body: some View {
        if let id = selectedClipID.wrappedValue,
           let clip = InspectorPanel.clipFor(id: id, in: video) {
            let properties = KeyframeEditor.propertyOptions(for: clip)
            VStack(spacing: rowSpacing) {
                ForEach(properties, id: \.self) { property in
                    propertyRow(clipID: id, clip: clip, property: property)
                        .frame(height: rowHeight)
                }
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func propertyRow(clipID: ClipID, clip: any Clip, property: KeyframeProperty) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let clipDurSecs = max(0.0001, CMTimeGetSeconds(clip.duration))
            let keyframes = KeyframeEditor.keyframesForProperty(property, on: clip)
            let clipStart = KeyframeEditor.clipStartTime(for: clipID, in: video) ?? .zero
            let playheadClipRel = CMTimeSubtract(currentTime.wrappedValue, clipStart)

            ZStack(alignment: .leading) {
                // Row background — tap target for "add at playhead".
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let secs = CMTimeGetSeconds(playheadClipRel)
                        guard secs >= 0, secs <= clipDurSecs else { return }
                        onAdd?(clipID, property, playheadClipRel)
                    }

                // Property label.
                Text(KeyframeEditor.label(for: property))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)

                // Playhead indicator on this row (clip-relative).
                let phSecs = CMTimeGetSeconds(playheadClipRel)
                if phSecs >= 0, phSecs <= clipDurSecs {
                    let x = CGFloat(phSecs / clipDurSecs) * width
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1)
                        .position(x: x, y: rowHeight / 2)
                }

                // Keyframe markers.
                ForEach(keyframes, id: \.value) { time in
                    let key = KeyframeKey(clipID: clipID, property: property, timeMs: time.value)
                    let baseX = CGFloat(CMTimeGetSeconds(time) / clipDurSecs) * width
                    let dragX = dragOffsetByKey[key] ?? 0
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .position(x: baseX + dragX, y: rowHeight / 2)
                        .gesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in
                                    onRemove?(clipID, property, time)
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { value in
                                    dragOffsetByKey[key] = value.translation.width
                                }
                                .onEnded { value in
                                    let dx = value.translation.width
                                    let deltaSec = Double(dx / width) * clipDurSecs
                                    let from = time
                                    let toSecRaw = CMTimeGetSeconds(from) + deltaSec
                                    let toSec = max(0, min(clipDurSecs, toSecRaw))
                                    let to = CMTime(seconds: toSec, preferredTimescale: 600)
                                    dragOffsetByKey[key] = nil
                                    if CMTimeCompare(from, to) != 0 {
                                        onRetime?(clipID, property, from, to)
                                    }
                                }
                        )
                }
            }
        }
    }
}

// MARK: - Pure helpers

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension KeyframeEditor {

    /// The properties to surface as rows for a clip. Always emits `.transform` and
    /// `.opacity` (every Kadr clip type carries the surface). Adds a `.filter(index:)`
    /// row for each entry in ``Kadr/VideoClip/filters`` that has an animatable scalar
    /// (matches ``InspectorPanel/scalar(of:)`` returning non-`nil`). Pure, testable.
    public static func propertyOptions(for clip: any Clip) -> [KeyframeProperty] {
        var rows: [KeyframeProperty] = [.transform, .opacity]
        if let video = clip as? VideoClip {
            for (index, filter) in video.filters.enumerated() where InspectorPanel.scalar(of: filter) != nil {
                rows.append(.filter(index: index))
            }
        }
        return rows
    }

    /// Keyframe times (clip-relative) for a property on a clip. Returns an empty array
    /// when the clip carries no animation for the property. Pure, testable.
    public static func keyframesForProperty(_ property: KeyframeProperty, on clip: any Clip) -> [CMTime] {
        switch property {
        case .transform:
            return clip.transformAnimation?.keyframes.map(\.time) ?? []
        case .opacity:
            return clip.opacityAnimation?.keyframes.map(\.time) ?? []
        case .filter(let index):
            guard let video = clip as? VideoClip else { return [] }
            guard index >= 0, index < video.filterAnimations.count else { return [] }
            return video.filterAnimations[index]?.keyframes.map(\.time) ?? []
        }
    }

    /// Best-effort composition-relative start time of `clipID`. Walks the top-level
    /// `video.clips`: chain clips accumulate cumulative duration; clips with a
    /// non-`nil` `startTime` (free-floaters) report it directly. Track-inner clips
    /// fall back to the track's own `startTime` (no per-inner accumulation). Returns
    /// `nil` when the ID isn't present. Pure, testable.
    public static func clipStartTime(for clipID: ClipID, in video: Video) -> CMTime? {
        var cursor = CMTime.zero
        for clip in video.clips {
            // Free-floater (or any clip with explicit startTime).
            if let pinned = clip.startTime {
                if clip.clipID == clipID { return pinned }
                if let track = clip as? Track {
                    for inner in track.clips where inner.clipID == clipID {
                        return pinned
                    }
                }
                continue  // Pinned clips don't advance the chain cursor.
            }
            if clip.clipID == clipID { return cursor }
            if let track = clip as? Track {
                for inner in track.clips where inner.clipID == clipID {
                    return cursor
                }
            }
            cursor = CMTimeAdd(cursor, clip.duration)
        }
        return nil
    }

    nonisolated static func label(for property: KeyframeProperty) -> String {
        switch property {
        case .transform: return "Transform"
        case .opacity:   return "Opacity"
        case .filter(let i): return "Filter \(i + 1)"
        }
    }
}
