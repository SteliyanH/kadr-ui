import SwiftUI
import CoreMedia
import Kadr

/// One of the four built-in overlay-targeted text animations exposed in the
/// inspector picker. Maps onto Kadr's concrete ``Kadr/TextAnimation`` types
/// (`FadeIn`, `SlideIn`, `ScaleUp`); a custom-built `TextAnimation` round-trips
/// as ``OverlayTextAnimationKind/custom`` and can't be edited via the picker —
/// only cleared.
public enum OverlayTextAnimationKind: Sendable, Equatable {
    case none
    case fadeIn(durationSeconds: TimeInterval)
    case slideIn(direction: SlideIn.Direction, durationSeconds: TimeInterval)
    case scaleUp(durationSeconds: TimeInterval)
    /// A consumer-built `TextAnimation` the picker can't render. Reset via the
    /// "None" picker option.
    case custom
}

/// Pure helpers used by ``OverlayInspectorPanel``. Separated so they're
/// testable without driving SwiftUI.
extension InspectorPanel {

    /// Look up an overlay in a composition by ``Kadr/LayerID``. Returns the
    /// first match, or `nil` if no overlay with that ID is set. Pure, testable.
    nonisolated public static func overlayFor(id: LayerID, in video: Video) -> (any Overlay)? {
        video.overlays.first(where: { $0.layerID == id })
    }

    /// Map a Kadr ``Kadr/TextAnimation`` (any concrete conformer) onto the
    /// inspector's ``OverlayTextAnimationKind`` picker case. Falls back to
    /// ``OverlayTextAnimationKind/custom`` for consumer-built animations.
    nonisolated public static func textAnimationKind(for animation: (any TextAnimation)?) -> OverlayTextAnimationKind {
        guard let animation else { return .none }
        if let fade = animation as? FadeIn {
            return .fadeIn(durationSeconds: CMTimeGetSeconds(fade.duration))
        }
        if let slide = animation as? SlideIn {
            return .slideIn(direction: slide.direction, durationSeconds: CMTimeGetSeconds(slide.duration))
        }
        if let scale = animation as? ScaleUp {
            return .scaleUp(durationSeconds: CMTimeGetSeconds(scale.duration))
        }
        return .custom
    }

    /// Build a concrete Kadr ``Kadr/TextAnimation`` for a picker selection.
    /// Returns `nil` for ``OverlayTextAnimationKind/none`` and
    /// ``OverlayTextAnimationKind/custom`` (custom animations the picker can't
    /// re-author — the consumer's responsibility).
    nonisolated public static func textAnimation(forKind kind: OverlayTextAnimationKind) -> (any TextAnimation)? {
        switch kind {
        case .none, .custom: return nil
        case .fadeIn(let dur):
            return FadeIn(duration: dur)
        case .slideIn(let direction, let dur):
            return SlideIn(from: direction, duration: dur)
        case .scaleUp(let dur):
            return ScaleUp(duration: dur)
        }
    }
}

// MARK: - OverlayInspectorPanel (public surface)

/// Inspector for a selected ``Kadr/Overlay``. Sibling to ``InspectorPanel``
/// (which targets clips) — same callback shape, different domain.
///
/// Surfaces the common ``Kadr/Overlay`` properties (position / anchor / opacity)
/// plus type-specific affordances:
/// - ``Kadr/TextOverlay`` — text field, text-animation picker
/// - ``Kadr/StickerOverlay`` — rotation slider
/// - ``Kadr/ImageOverlay`` — common only (covers
///   ``Kadr/Video/watermark(_:position:size:opacity:)`` instances; their
///   ``Kadr/Overlay/layerID`` is `"watermark"`)
///
/// **Read-only model.** Edits surface through callbacks; the consumer rebuilds
/// the `Video`. Pair with a parent state container the same way ``InspectorPanel``
/// is wired to a clip-selection binding.
public struct OverlayInspectorPanel: View {

    /// v0.13 — appearance tokens; defaults reproduce pre-0.13 rendering.
    @Environment(\.kadrAppearance) private var appearance

    private let video: Video
    private let selectedOverlayID: Binding<LayerID?>
    private let onPosition: ((LayerID, Position) -> Void)?
    private let onSize: ((LayerID, Size?) -> Void)?
    private let onAnchor: ((LayerID, Kadr.Anchor) -> Void)?
    private let onOpacity: ((LayerID, Double) -> Void)?
    private let onText: ((LayerID, String) -> Void)?
    private let onTextAnimation: ((LayerID, OverlayTextAnimationKind) -> Void)?
    private let onRotation: ((LayerID, Double) -> Void)?
    private let onTextStroke: ((LayerID, TextStroke?) -> Void)?
    private let onTextShadow: ((LayerID, TextShadow?) -> Void)?

    public init(
        _ video: Video,
        selectedOverlayID: Binding<LayerID?>,
        onPosition: ((LayerID, Position) -> Void)? = nil,
        onSize: ((LayerID, Size?) -> Void)? = nil,
        onAnchor: ((LayerID, Kadr.Anchor) -> Void)? = nil,
        onOpacity: ((LayerID, Double) -> Void)? = nil,
        onText: ((LayerID, String) -> Void)? = nil,
        onTextAnimation: ((LayerID, OverlayTextAnimationKind) -> Void)? = nil,
        onRotation: ((LayerID, Double) -> Void)? = nil,
        onTextStroke: ((LayerID, TextStroke?) -> Void)? = nil,
        onTextShadow: ((LayerID, TextShadow?) -> Void)? = nil
    ) {
        self.video = video
        self.selectedOverlayID = selectedOverlayID
        self.onPosition = onPosition
        self.onSize = onSize
        self.onAnchor = onAnchor
        self.onOpacity = onOpacity
        self.onText = onText
        self.onTextAnimation = onTextAnimation
        self.onRotation = onRotation
        self.onTextStroke = onTextStroke
        self.onTextShadow = onTextShadow
    }

    public var body: some View {
        if let id = selectedOverlayID.wrappedValue,
           let overlay = InspectorPanel.overlayFor(id: id, in: video) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    commonSection(id: id, overlay: overlay)
                    typeSpecificSection(id: id, overlay: overlay)
                }
                .padding(12)
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Common section (every overlay)

    @ViewBuilder
    private func commonSection(id: LayerID, overlay: any Overlay) -> some View {
        let (nx, ny) = InspectorPanel.normalizedXY(of: overlay.position)

        OverlaySectionHeader("Position")
        OverlaySliderRow(label: "X", value: nx, range: 0...1) { newX in
            onPosition?(id, .normalized(x: newX, y: ny))
        }
        OverlaySliderRow(label: "Y", value: ny, range: 0...1) { newY in
            onPosition?(id, .normalized(x: nx, y: newY))
        }

        OverlaySectionHeader("Anchor")
        Picker("Anchor", selection: Binding(
            get: { InspectorPanel.allAnchors.firstIndex(of: overlay.anchor) ?? 4 },
            set: { newIndex in
                onAnchor?(id, InspectorPanel.allAnchors[newIndex])
            }
        )) {
            ForEach(InspectorPanel.allAnchors.indices, id: \.self) { index in
                Text(InspectorPanel.label(for: InspectorPanel.allAnchors[index])).tag(index)
            }
        }
        .pickerStyle(.menu)

        OverlaySectionHeader("Opacity")
        OverlaySliderRow(label: "Opacity", value: overlay.opacity, range: 0...1) { newO in
            onOpacity?(id, newO)
        }
    }

    // MARK: - Type-specific section

    @ViewBuilder
    private func typeSpecificSection(id: LayerID, overlay: any Overlay) -> some View {
        if let text = overlay as? TextOverlay {
            textSection(id: id, text: text)
        } else if let sticker = overlay as? StickerOverlay {
            stickerSection(id: id, sticker: sticker)
        }
        // ImageOverlay (and Watermark sugar) — common-only.
    }

    @ViewBuilder
    private func textSection(id: LayerID, text: TextOverlay) -> some View {
        OverlaySectionHeader("Text")
        OverlayTextField(text: text.text) { newText in
            onText?(id, newText)
        }

        OverlaySectionHeader("Animation")
        let kind = InspectorPanel.textAnimationKind(for: text.textAnimation)
        Picker("Animation", selection: Binding(
            get: { OverlayInspectorPanel.animationPickerIndex(for: kind) },
            set: { idx in
                let preset = OverlayInspectorPanel.animationPresets[idx]
                onTextAnimation?(id, preset.kind)
            }
        )) {
            ForEach(OverlayInspectorPanel.animationPresets.indices, id: \.self) { idx in
                Text(OverlayInspectorPanel.animationPresets[idx].label).tag(idx)
            }
        }
        .pickerStyle(.menu)

        // kadr v0.12 put stroke and shadow on TextStyle so copy stays legible
        // over busy footage. This panel never surfaced either, so a consumer
        // wanting them had to build the whole section itself.
        if onTextStroke != nil {
            OverlaySectionHeader("Stroke")
            let stroke = text.style.stroke
            OverlaySliderRow(
                label: "Width",
                value: stroke?.width ?? 0,
                range: 0...12
            ) { width in
                // Width 0 means "no stroke" in the renderer, so send nil rather
                // than a zero-width stroke — otherwise a caller storing the
                // value cannot tell "off" from "on but invisible".
                onTextStroke?(id, width <= 0 ? nil : TextStroke(width: width, color: stroke?.color ?? .black))
            }
        }

        if onTextShadow != nil {
            OverlaySectionHeader("Shadow")
            let shadow = text.style.shadow
            OverlaySliderRow(
                label: "Blur",
                value: shadow?.blur ?? 0,
                range: 0...24
            ) { blur in
                onTextShadow?(id, OverlayInspectorPanel.shadow(from: shadow, blur: blur))
            }
            OverlaySliderRow(
                label: "Offset X",
                value: Double(shadow?.offset.width ?? 0),
                range: -24...24
            ) { dx in
                onTextShadow?(id, OverlayInspectorPanel.shadow(from: shadow, offsetX: dx))
            }
            OverlaySliderRow(
                label: "Offset Y",
                value: Double(shadow?.offset.height ?? 0),
                range: -24...24
            ) { dy in
                onTextShadow?(id, OverlayInspectorPanel.shadow(from: shadow, offsetY: dy))
            }
        }
    }

    /// Rebuilds a shadow with one field replaced.
    ///
    /// Pure and `nonisolated` so the "is this still a shadow at all?" rule is
    /// testable: a shadow with no blur and no offset is indistinguishable from
    /// none, and reporting it as `nil` keeps a caller's stored state honest.
    nonisolated static func shadow(
        from existing: TextShadow?,
        blur: Double? = nil,
        offsetX: Double? = nil,
        offsetY: Double? = nil
    ) -> TextShadow? {
        let base = existing ?? TextShadow(offset: .zero, blur: 0)
        let newBlur = blur ?? base.blur
        let newX = offsetX ?? Double(base.offset.width)
        let newY = offsetY ?? Double(base.offset.height)
        if newBlur <= 0, newX == 0, newY == 0 { return nil }
        return TextShadow(
            offset: CGSize(width: newX, height: newY),
            blur: max(0, newBlur),
            color: base.color
        )
    }

    @ViewBuilder
    private func stickerSection(id: LayerID, sticker: StickerOverlay) -> some View {
        OverlaySectionHeader("Rotation")
        OverlaySliderRow(label: "Rotation", value: sticker.rotation, range: -.pi ... .pi) { newR in
            onRotation?(id, newR)
        }
    }
}

// MARK: - Pickerable animation presets

extension OverlayInspectorPanel {

    nonisolated public static let animationPresets: [(label: String, kind: OverlayTextAnimationKind)] = [
        ("None",            .none),
        ("Fade In (0.5s)",  .fadeIn(durationSeconds: 0.5)),
        ("Slide In ←",      .slideIn(direction: .fromLeft, durationSeconds: 0.5)),
        ("Slide In →",      .slideIn(direction: .fromRight, durationSeconds: 0.5)),
        ("Slide In ↑",      .slideIn(direction: .fromTop, durationSeconds: 0.5)),
        ("Slide In ↓",      .slideIn(direction: .fromBottom, durationSeconds: 0.5)),
        ("Scale Up (0.5s)", .scaleUp(durationSeconds: 0.5)),
    ]

    nonisolated public static func animationPickerIndex(for kind: OverlayTextAnimationKind) -> Int {
        switch kind {
        case .none:
            return 0
        case .fadeIn:
            return 1
        case .slideIn(let direction, _):
            switch direction {
            case .fromLeft:   return 2
            case .fromRight:  return 3
            case .fromTop:    return 4
            case .fromBottom: return 5
            }
        case .scaleUp:
            return 6
        case .custom:
            return 0  // picker can't re-author custom animations
        }
    }
}

// MARK: - Internal subviews (overlay-specific to keep clip-side untouched)

private struct OverlaySectionHeader: View {
    @Environment(\.kadrAppearance) private var appearance
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(appearance.panelTitleFont)
    }
}

private struct OverlaySliderRow: View {
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
                    get: { min(max(value, range.lowerBound), range.upperBound) },
                    set: { onChange($0) }
                ),
                in: range
            )
            // v0.11 — label + formatted value on the natively-adjustable Slider.
            .accessibilityLabel(label)
            .accessibilityValue(String(format: "%.2f", value))
            Text(String(format: "%.2f", value))
                .frame(width: 56, alignment: .trailing)
                .font(appearance.panelValueFont)
                .accessibilityHidden(true)
        }
    }
}

private struct OverlayTextField: View {
    @Environment(\.kadrAppearance) private var appearance
    let text: String
    let onCommit: (String) -> Void

    @State private var draft: String

    init(text: String, onCommit: @escaping (String) -> Void) {
        self.text = text
        self.onCommit = onCommit
        self._draft = State(initialValue: text)
    }

    var body: some View {
        TextField("Text", text: $draft, axis: .vertical)
            .lineLimit(1...3)
            .onChange(of: text) { _, newValue in
                if draft != newValue { draft = newValue }
            }
            .onSubmit {
                if draft != text { onCommit(draft) }
            }
            .accessibilityLabel("Overlay text")
    }
}
