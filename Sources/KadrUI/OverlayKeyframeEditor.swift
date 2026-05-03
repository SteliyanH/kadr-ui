import SwiftUI
import CoreMedia
import Kadr

/// Identifies an animatable property surfaced as a row in
/// ``OverlayKeyframeEditor``. Property availability per overlay kind:
/// - ``Kadr/ImageOverlay`` — `.position`, `.size`
/// - ``Kadr/StickerOverlay`` — `.position`, `.size`
/// - ``Kadr/TextOverlay`` — none (kadr's text overlays use the enum-driven
///   ``Kadr/TextAnimation`` instead of keyframes)
/// - ``Kadr/Video/watermark(_:position:size:opacity:)`` — same as `ImageOverlay`
public enum OverlayProperty: Sendable, Hashable {
    case position
    case size
}

/// Per-property keyframe editor for a selected ``Kadr/Overlay``. Mirrors the
/// v0.6 ``KeyframeEditor`` (which targets clips) — same gesture model (tap
/// empty area to add at playhead, long-press a marker to remove, drag to
/// retime), different domain.
///
/// **Time mapping.** Overlay keyframes are *composition-relative* (kadr's
/// `Animation<Position>` and `Animation<Size>` evaluate against absolute
/// composition time, not clip-local time — see `Overlay.swift`). The editor
/// shows each row spanning `[0, compositionDuration]` rather than a clip range.
///
/// **Read-only model.** Edits surface through the three callbacks; the consumer
/// rebuilds the `Video` with the new animation.
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct OverlayKeyframeEditor: View {

    private let video: Video
    private let selectedOverlayID: Binding<LayerID?>
    private let currentTime: Binding<CMTime>
    private let rowHeight: CGFloat
    private let rowSpacing: CGFloat
    private let onAdd: ((LayerID, OverlayProperty, CMTime) -> Void)?
    private let onRemove: ((LayerID, OverlayProperty, CMTime) -> Void)?
    private let onRetime: ((LayerID, OverlayProperty, _ from: CMTime, _ to: CMTime) -> Void)?

    /// Drag offset for the in-flight retime drag, keyed by (overlay, property,
    /// keyframe time-ms).
    @State private var dragOffsetByKey: [KeyframeKey: CGFloat] = [:]

    private struct KeyframeKey: Hashable {
        let overlayID: LayerID
        let property: OverlayProperty
        let timeMs: Int64
    }

    public init(
        _ video: Video,
        selectedOverlayID: Binding<LayerID?>,
        currentTime: Binding<CMTime>,
        rowHeight: CGFloat = 24,
        rowSpacing: CGFloat = 4,
        onAdd: ((LayerID, OverlayProperty, CMTime) -> Void)? = nil,
        onRemove: ((LayerID, OverlayProperty, CMTime) -> Void)? = nil,
        onRetime: ((LayerID, OverlayProperty, _ from: CMTime, _ to: CMTime) -> Void)? = nil
    ) {
        self.video = video
        self.selectedOverlayID = selectedOverlayID
        self.currentTime = currentTime
        self.rowHeight = rowHeight
        self.rowSpacing = rowSpacing
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onRetime = onRetime
    }

    public var body: some View {
        if let id = selectedOverlayID.wrappedValue,
           let overlay = InspectorPanel.overlayFor(id: id, in: video) {
            let properties = OverlayKeyframeEditor.propertyOptions(for: overlay)
            VStack(spacing: rowSpacing) {
                ForEach(properties, id: \.self) { property in
                    propertyRow(overlayID: id, overlay: overlay, property: property)
                        .frame(height: rowHeight)
                }
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func propertyRow(
        overlayID: LayerID,
        overlay: any Overlay,
        property: OverlayProperty
    ) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let totalSeconds = max(0.0001, CMTimeGetSeconds(video.duration))
            let keyframes = OverlayKeyframeEditor.keyframesForProperty(property, on: overlay)
            let phSecs = CMTimeGetSeconds(currentTime.wrappedValue)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard phSecs >= 0, phSecs <= totalSeconds else { return }
                        onAdd?(overlayID, property, currentTime.wrappedValue)
                    }

                Text(OverlayKeyframeEditor.label(for: property))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)

                if phSecs >= 0, phSecs <= totalSeconds {
                    let x = CGFloat(phSecs / totalSeconds) * width
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1)
                        .position(x: x, y: rowHeight / 2)
                }

                ForEach(keyframes, id: \.value) { time in
                    let key = KeyframeKey(overlayID: overlayID, property: property, timeMs: time.value)
                    let baseX = CGFloat(CMTimeGetSeconds(time) / totalSeconds) * width
                    let dragX = dragOffsetByKey[key] ?? 0
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .position(x: baseX + dragX, y: rowHeight / 2)
                        .gesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in
                                    onRemove?(overlayID, property, time)
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { value in
                                    dragOffsetByKey[key] = value.translation.width
                                }
                                .onEnded { value in
                                    let dx = value.translation.width
                                    let deltaSec = Double(dx / width) * totalSeconds
                                    let from = time
                                    let toSec = max(0, min(totalSeconds, CMTimeGetSeconds(from) + deltaSec))
                                    let to = CMTime(seconds: toSec, preferredTimescale: 600)
                                    dragOffsetByKey[key] = nil
                                    if CMTimeCompare(from, to) != 0 {
                                        onRetime?(overlayID, property, from, to)
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
extension OverlayKeyframeEditor {

    /// The keyframe-able properties for an overlay. Pure, testable. Returns an
    /// empty array for ``Kadr/TextOverlay`` (not keyframe-able in kadr v0.10)
    /// and for any conformer kadr-ui doesn't recognize.
    nonisolated public static func propertyOptions(for overlay: any Overlay) -> [OverlayProperty] {
        if overlay is ImageOverlay || overlay is StickerOverlay {
            return [.position, .size]
        }
        return []
    }

    /// Keyframe times (composition-relative) for a property on an overlay.
    /// Returns an empty array when the overlay carries no animation for the
    /// property. Pure, testable.
    nonisolated public static func keyframesForProperty(
        _ property: OverlayProperty,
        on overlay: any Overlay
    ) -> [CMTime] {
        switch property {
        case .position:
            return overlay.positionAnimation?.keyframes.map(\.time) ?? []
        case .size:
            return overlay.sizeAnimation?.keyframes.map(\.time) ?? []
        }
    }

    nonisolated public static func label(for property: OverlayProperty) -> String {
        switch property {
        case .position: return "Position"
        case .size:     return "Size"
        }
    }
}
