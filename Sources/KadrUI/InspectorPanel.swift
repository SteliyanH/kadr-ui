import SwiftUI
import Kadr

/// A read-only-style property panel for the clip currently selected on a ``TimelineView``.
///
/// Tap a clip on the timeline (binding `selectedClipID` shared between both views) and the
/// inspector populates with sliders for the v0.8 surface: ``Kadr/Transform`` (center X/Y,
/// rotation, scale, anchor), ``Kadr/Clip/opacity``, and per-filter intensity. Slider edits
/// fire callbacks that mirror ``TimelineView/onReorder`` / ``TimelineView/onTrim``: the
/// panel does not mutate the `Video` (it can't — `Video` is immutable). The consumer
/// rebuilds the composition with the new value.
///
/// ```swift
/// VStack {
///     TimelineView(video, selectedClipID: $selectedID)
///     InspectorPanel(
///         video,
///         selectedClipID: $selectedID,
///         onTransform: { id, t in /* rebuild Video, applying t to clip(id) */ },
///         onOpacity: { id, o in /* rebuild with .opacity(o) */ },
///         onFilterIntensity: { id, idx, v in /* rebuild filters[idx] withScalar(v) */ }
///     )
/// }
/// ```
///
/// **No selection.** When `selectedClipID` is `nil` or resolves to a clip the inspector
/// can't address (a transition, or a `ClipID` that doesn't appear in `video.clips`), the
/// panel renders an empty placeholder. Apps typically hide it with `.opacity` / `.frame`
/// based on their own state.
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct InspectorPanel: View {

    private let video: Video
    private let selectedClipID: Binding<ClipID?>
    private let onTransform: ((ClipID, Transform) -> Void)?
    private let onOpacity: ((ClipID, Double) -> Void)?
    private let onFilterIntensity: ((ClipID, _ filterIndex: Int, _ intensity: Double) -> Void)?

    /// Create an inspector panel.
    /// - Parameters:
    ///   - video: The composition. Read-only — re-look-up happens through `selectedClipID`.
    ///   - selectedClipID: Binding shared with a ``TimelineView`` so the two stay in sync.
    ///   - onTransform: Fires when the user edits any Transform slider. Receives the full
    ///     resulting ``Kadr/Transform`` (the panel always emits a complete value, never a
    ///     partial delta). Consumer rebuilds the `Video` with the new transform on the
    ///     identified clip.
    ///   - onOpacity: Fires when the user moves the opacity slider. Receives a value in
    ///     `0...1`.
    ///   - onFilterIntensity: Fires when the user edits a per-filter intensity slider.
    ///     Receives the clip's `ClipID`, the index into ``Kadr/VideoClip/filters``, and
    ///     the new scalar in the filter's natural range. Consumer rebuilds the filter via
    ///     ``Kadr/Filter/withScalar(_:)`` (or however they prefer).
    public init(
        _ video: Video,
        selectedClipID: Binding<ClipID?>,
        onTransform: ((ClipID, Transform) -> Void)? = nil,
        onOpacity: ((ClipID, Double) -> Void)? = nil,
        onFilterIntensity: ((ClipID, _ filterIndex: Int, _ intensity: Double) -> Void)? = nil
    ) {
        self.video = video
        self.selectedClipID = selectedClipID
        self.onTransform = onTransform
        self.onOpacity = onOpacity
        self.onFilterIntensity = onFilterIntensity
    }

    public var body: some View {
        if let id = selectedClipID.wrappedValue, let clip = InspectorPanel.clipFor(id: id, in: video) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    transformSection(for: id, clip: clip)
                    opacitySection(for: id, clip: clip)
                    filtersSection(for: id, clip: clip)
                }
                .padding(12)
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func transformSection(for id: ClipID, clip: any Clip) -> some View {
        let base = clip.transform ?? .identity
        let (nx, ny) = InspectorPanel.normalizedXY(of: base.center)

        SectionHeader("Transform")

        SliderRow(label: "Position X", value: nx, range: 0...1) { newX in
            let next = Transform(
                center: .normalized(x: newX, y: ny),
                rotation: base.rotation,
                scale: base.scale,
                anchor: base.anchor
            )
            onTransform?(id, next)
        }
        SliderRow(label: "Position Y", value: ny, range: 0...1) { newY in
            let next = Transform(
                center: .normalized(x: nx, y: newY),
                rotation: base.rotation,
                scale: base.scale,
                anchor: base.anchor
            )
            onTransform?(id, next)
        }
        SliderRow(label: "Rotation", value: base.rotation, range: -.pi ... .pi) { newR in
            let next = Transform(
                center: base.center,
                rotation: newR,
                scale: base.scale,
                anchor: base.anchor
            )
            onTransform?(id, next)
        }
        SliderRow(label: "Scale", value: base.scale, range: 0.1...4.0) { newS in
            let next = Transform(
                center: base.center,
                rotation: base.rotation,
                scale: newS,
                anchor: base.anchor
            )
            onTransform?(id, next)
        }

        Picker("Anchor", selection: Binding(
            get: { InspectorPanel.allAnchors.firstIndex(of: base.anchor) ?? 4 },
            set: { newIndex in
                let next = Transform(
                    center: base.center,
                    rotation: base.rotation,
                    scale: base.scale,
                    anchor: InspectorPanel.allAnchors[newIndex]
                )
                onTransform?(id, next)
            }
        )) {
            ForEach(InspectorPanel.allAnchors.indices, id: \.self) { index in
                Text(InspectorPanel.label(for: InspectorPanel.allAnchors[index])).tag(index)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func opacitySection(for id: ClipID, clip: any Clip) -> some View {
        SectionHeader("Opacity")
        SliderRow(label: "Opacity", value: clip.opacity ?? 1.0, range: 0...1) { newO in
            onOpacity?(id, newO)
        }
    }

    @ViewBuilder
    private func filtersSection(for id: ClipID, clip: any Clip) -> some View {
        let filters = (clip as? VideoClip)?.filters ?? []
        if !filters.isEmpty {
            SectionHeader("Filters")
            ForEach(Array(filters.enumerated()), id: \.offset) { index, filter in
                if let scalar = InspectorPanel.scalar(of: filter),
                   let range = InspectorPanel.range(of: filter) {
                    SliderRow(
                        label: InspectorPanel.label(for: filter),
                        value: scalar,
                        range: range
                    ) { newValue in
                        onFilterIntensity?(id, index, newValue)
                    }
                }
            }
        }
    }
}

// MARK: - Pure helpers

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension InspectorPanel {

    /// Look up a clip in a composition by ``Kadr/ClipID``. Searches the top-level chain
    /// and inside any ``Kadr/Track`` blocks. Returns the first match, or `nil` if no clip
    /// with that ID exists. Pure — exposed for testing and for callers who want to read
    /// the same clip the inspector is showing.
    public static func clipFor(id: ClipID, in video: Video) -> (any Clip)? {
        for clip in video.clips {
            if clip.clipID == id { return clip }
            if let track = clip as? Track {
                for inner in track.clips where inner.clipID == id {
                    return inner
                }
            }
        }
        return nil
    }

    /// Project a ``Kadr/Position`` onto a `(x, y)` pair in `0...1`. `.normalized` passes
    /// through; `.percent` divides by 100; `.pixels` falls back to canvas-center `(0.5,
    /// 0.5)` since the panel doesn't know the render size. Pure helper, exposed for
    /// testing.
    nonisolated static func normalizedXY(of position: Position) -> (Double, Double) {
        switch position {
        case .normalized(let x, let y): return (x, y)
        case .percent(let x, let y): return (x / 100.0, y / 100.0)
        case .pixels: return (0.5, 0.5)
        }
    }

    /// All nine ``Kadr/Anchor`` cases in display order (top row L-C-R, middle, bottom).
    nonisolated static let allAnchors: [Kadr.Anchor] = [
        .topLeft, .top, .topRight,
        .left, .center, .right,
        .bottomLeft, .bottom, .bottomRight,
    ]

    nonisolated static func label(for anchor: Kadr.Anchor) -> String {
        switch anchor {
        case .topLeft: return "Top-Left"
        case .top: return "Top"
        case .topRight: return "Top-Right"
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        case .bottomLeft: return "Bottom-Left"
        case .bottom: return "Bottom"
        case .bottomRight: return "Bottom-Right"
        }
    }

    /// The animatable scalar of a filter, or `nil` for filters without one
    /// (`.mono`, `.lut`, `.chromaKey`). Mirrors ``Kadr/Filter/withScalar(_:)``'s contract:
    /// these are the filters the inspector exposes a slider for. Pure, testable.
    nonisolated static func scalar(of filter: Filter) -> Double? {
        switch filter {
        case .brightness(let v): return v
        case .contrast(let v): return v
        case .saturation(let v): return v
        case .exposure(let v): return v
        case .sepia(let intensity): return intensity
        case .gaussianBlur(let radius): return radius
        case .vignette(let intensity): return intensity
        case .sharpen(let amount): return amount
        case .zoomBlur(let amount): return amount
        case .glow(let intensity): return intensity
        case .mono, .lut, .chromaKey: return nil
        }
    }

    /// The natural slider range for a filter's primary scalar. `nil` for filters without
    /// a scalar parameter. Each range follows the underlying CIFilter conventions —
    /// values outside clamp at the slider edges. Pure, testable.
    nonisolated static func range(of filter: Filter) -> ClosedRange<Double>? {
        switch filter {
        case .brightness:   return -1.0...1.0
        case .contrast:     return 0.0...4.0
        case .saturation:   return 0.0...2.0
        case .exposure:     return -2.0...2.0
        case .sepia:        return 0.0...1.0
        case .gaussianBlur: return 0.0...50.0
        case .vignette:     return 0.0...1.0
        case .sharpen:      return 0.0...2.0
        case .zoomBlur:     return 0.0...100.0
        case .glow:         return 0.0...1.0
        case .mono, .lut, .chromaKey: return nil
        }
    }

    nonisolated static func label(for filter: Filter) -> String {
        switch filter {
        case .brightness:   return "Brightness"
        case .contrast:     return "Contrast"
        case .saturation:   return "Saturation"
        case .exposure:     return "Exposure"
        case .sepia:        return "Sepia"
        case .mono:         return "Mono"
        case .lut:          return "LUT"
        case .chromaKey:    return "Chroma Key"
        case .gaussianBlur: return "Gaussian Blur"
        case .vignette:     return "Vignette"
        case .sharpen:      return "Sharpen"
        case .zoomBlur:     return "Zoom Blur"
        case .glow:         return "Glow"
        }
    }
}

// MARK: - Subviews

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.headline)
    }
}

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
private struct SliderRow: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 90, alignment: .leading)
                .font(.subheadline)
            Slider(
                value: Binding(
                    get: { value.clamped(to: range) },
                    set: { onChange($0) }
                ),
                in: range
            )
            Text(formatted(value))
                .frame(width: 56, alignment: .trailing)
                .font(.caption.monospacedDigit())
        }
    }

    private func formatted(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
