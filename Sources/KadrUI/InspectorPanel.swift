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
public struct InspectorPanel: View {

    /// v0.13 — appearance tokens; defaults reproduce pre-0.13 rendering.
    @Environment(\.kadrAppearance) private var appearance

    private let video: Video
    private let selectedClipID: Binding<ClipID?>
    private let onTransform: ((ClipID, Transform) -> Void)?
    private let onOpacity: ((ClipID, Double) -> Void)?
    private let onFilterIntensity: ((ClipID, _ filterIndex: Int, _ intensity: Double) -> Void)?
    private let onFilterAdd: ((ClipID, Filter) -> Void)?
    private let onFilterRemove: ((ClipID, _ filterIndex: Int) -> Void)?
    private let onFilterMove: ((ClipID, _ from: IndexSet, _ to: Int) -> Void)?

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
    /// One group of controls in the panel.
    ///
    /// The approved design puts a Transform / Opacity / Filters segmented
    /// control above this panel, but there was nothing for it to drive: the
    /// panel stacked all three sections and exposed no notion of a current one,
    /// so a host could build the control and it would be inert chrome.
    public enum Section: String, CaseIterable, Hashable, Sendable, Identifiable {
        case transform
        case opacity
        case filters

        public var id: String { rawValue }

        /// The heading this panel already draws for the section.
        ///
        /// Exposed so a host's control and the panel cannot disagree about what
        /// a section is called.
        public var title: String {
            switch self {
            case .transform: return "Transform"
            case .opacity: return "Opacity"
            case .filters: return "Filters"
            }
        }
    }

    public init(
        _ video: Video,
        selectedClipID: Binding<ClipID?>,
        selectedSection: Binding<Section>? = nil,
        onTransform: ((ClipID, Transform) -> Void)? = nil,
        onOpacity: ((ClipID, Double) -> Void)? = nil,
        onFilterIntensity: ((ClipID, _ filterIndex: Int, _ intensity: Double) -> Void)? = nil,
        onFilterAdd: ((ClipID, Filter) -> Void)? = nil,
        onFilterRemove: ((ClipID, _ filterIndex: Int) -> Void)? = nil,
        onFilterMove: ((ClipID, _ from: IndexSet, _ to: Int) -> Void)? = nil
    ) {
        self.video = video
        self.selectedClipID = selectedClipID
        self.selectedSection = selectedSection
        self.onTransform = onTransform
        self.onOpacity = onOpacity
        self.onFilterIntensity = onFilterIntensity
        self.onFilterAdd = onFilterAdd
        self.onFilterRemove = onFilterRemove
        self.onFilterMove = onFilterMove
    }

    private let selectedSection: Binding<Section>?

    public var body: some View {
        if let id = selectedClipID.wrappedValue, let clip = InspectorPanel.clipFor(id: id, in: video) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // No binding means the pre-existing behaviour: everything
                    // stacked. A binding means the host owns which one shows.
                    if let selectedSection {
                        switch selectedSection.wrappedValue {
                        case .transform: transformSection(for: id, clip: clip)
                        case .opacity:   opacitySection(for: id, clip: clip)
                        case .filters:   filtersSection(for: id, clip: clip)
                        }
                    } else {
                        transformSection(for: id, clip: clip)
                        opacitySection(for: id, clip: clip)
                        filtersSection(for: id, clip: clip)
                    }
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
        let canAuthor = onFilterAdd != nil || onFilterRemove != nil || onFilterMove != nil

        if !filters.isEmpty || canAuthor {
            HStack {
                SectionHeader("Filters")
                Spacer()
                if onFilterAdd != nil { addFilterMenu(for: id) }
            }
        }

        if filters.isEmpty {
            if canAuthor {
                Text("No filters")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("No filters applied")
            }
        } else {
            // Plain rows rather than a `List`. The panel is documented as
            // something you embed — under a TimelineView, inside your own
            // ScrollView — and a List here would be a nested scroll view
            // propped up with a hard-coded height. Reorder is up/down buttons
            // for the same reason: `onMove` is a List primitive, and it is not
            // reachable by VoiceOver or by keyboard the way buttons are.
            ForEach(Array(filters.enumerated()), id: \.offset) { index, filter in
                filterRow(for: id, filter: filter, index: index, count: filters.count)
            }
        }
    }

    @ViewBuilder
    private func filterRow(for id: ClipID, filter: Filter, index: Int, count: Int) -> some View {
        HStack(spacing: 8) {
            if let scalar = InspectorPanel.scalar(of: filter),
               let range = InspectorPanel.range(of: filter) {
                SliderRow(
                    label: InspectorPanel.label(for: filter),
                    value: scalar,
                    range: range
                ) { newValue in
                    onFilterIntensity?(id, index, newValue)
                }
            } else {
                // .mono, .lut and .chromaKey have no scalar to vary. Before
                // v0.19 they rendered as nothing at all, so a filter the user
                // had applied was invisible in the panel — and unremovable,
                // because there was no row to act on.
                Text(InspectorPanel.label(for: filter))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if onFilterMove != nil {
                Button {
                    onFilterMove?(id, IndexSet(integer: index), index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                .accessibilityLabel("Move \(InspectorPanel.label(for: filter)) earlier")

                Button {
                    // SwiftUI's move semantics: the destination is an index in
                    // the list *before* the element is removed, so moving down
                    // by one is +2, not +1.
                    onFilterMove?(id, IndexSet(integer: index), index + 2)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == count - 1)
                .accessibilityLabel("Move \(InspectorPanel.label(for: filter)) later")
            }

            if onFilterRemove != nil {
                Button(role: .destructive) {
                    onFilterRemove?(id, index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .accessibilityLabel("Remove \(InspectorPanel.label(for: filter))")
            }
        }
        .buttonStyle(.borderless)
    }

    /// The add menu, built from ``Kadr/FilterKind`` rather than a hard-coded
    /// list — so a filter added to kadr appears here without kadr-ui changing.
    @ViewBuilder
    private func addFilterMenu(for id: ClipID) -> some View {
        Menu {
            ForEach(FilterKind.insertable, id: \.self) { kind in
                Button(kind.displayName) {
                    if let filter = kind.defaultFilter { onFilterAdd?(id, filter) }
                }
            }
        } label: {
            Image(systemName: "plus")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Add Filter")
    }
}

// MARK: - Pure helpers

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

    /// A display name for a filter.
    ///
    /// Delegates to ``Kadr/FilterKind/displayName`` rather than keeping a second
    /// list. kadr-ui carried its own copy until v0.19, which is one more place
    /// for a new filter to be missed — the exact drift `FilterKind` exists to
    /// stop.
    nonisolated static func label(for filter: Filter) -> String {
        filter.kind.displayName
    }
}

// MARK: - Subviews

private struct SectionHeader: View {
    @Environment(\.kadrAppearance) private var appearance
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(appearance.panelTitleFont)
    }
}

private struct SliderRow: View {
    @Environment(\.kadrAppearance) private var appearance
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 90, alignment: .leading)
                .font(appearance.panelSectionFont)
                .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { value.clamped(to: range) },
                    set: { onChange($0) }
                ),
                in: range
            )
            // v0.11 — the Slider is natively adjustable; give it the row's label and a
            // formatted value so VoiceOver speaks "Opacity, 0.50" instead of a bare
            // number. The flanking Text views are decorative duplicates.
            .accessibilityLabel(label)
            .accessibilityValue(formatted(value))
            Text(formatted(value))
                .frame(width: 56, alignment: .trailing)
                .font(appearance.panelValueFont)
                .accessibilityHidden(true)
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
