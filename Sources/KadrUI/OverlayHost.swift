import SwiftUI
import Kadr
import CoreMedia

/// A SwiftUI overlay layer that renders a Kadr ``Kadr/Video``'s overlays over preview content.
///
/// Why this exists: Kadr 0.4.0 intentionally does **not** bake overlays into the preview
/// surface (`AVVideoCompositionCoreAnimationTool` is export-only). To preview overlays —
/// and especially to hit-test them with SwiftUI gestures — they must be rendered as
/// SwiftUI views layered over the player. `OverlayHost` does that, using
/// ``Kadr/Layout/resolveFrame(position:size:anchor:in:)`` so positions match the engine
/// pixel-for-pixel.
///
/// ```swift
/// ZStack {
///     VideoPreview(video)
///     OverlayHost(video)
/// }
/// .aspectRatio(9.0 / 16.0, contentMode: .fit)
/// ```
///
/// **Hybrid rendering.** Built-in renderers cover the three concrete overlay types
/// (`ImageOverlay`, `TextOverlay`, `StickerOverlay`) — close to the engine's CALayer
/// rendering, within SwiftUI's primitives. Pass a `customRenderer` to override on a
/// per-overlay basis: returning a non-`nil` view replaces the default; returning `nil`
/// (or omitting the closure) falls back to the default.
///
/// **Layout contract.** Overlays are positioned inside the video's display rectangle,
/// which is derived from the host's bounds and the chosen `contentMode` (default `.fit`).
/// Use `.fit` (default) for letterboxed parents, `.fill` for fill-and-crop parents, or
/// `.stretch` for parents that pin the aspect ratio with `.aspectRatio(...)`. With
/// `.stretch`, overlays scale x/y independently — matching the pre-v0.4.4 behavior.
///
/// **Time-aware visibility.** Pass `currentTime` to honor each overlay's
/// ``Kadr/Overlay/visibilityRange``. Overlays with a non-`nil` range render only while
/// `currentTime` is inside the range. Overlays without a range always render. Without
/// `currentTime`, all overlays render unconditionally (preview matches export of an
/// untimed composition).
///
/// **Overlays without explicit `size`.** Kadr's `Overlay.size` is optional. When `nil`,
/// `OverlayHost` uses a default frame of 30% × 30% of the canvas as a v1 placeholder.
/// This may not match the export — set `.size(...)` explicitly on the overlay if pixel
/// alignment matters in preview.
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct OverlayHost: View {

    /// Strategy for fitting the composition's display rectangle inside the host's bounds.
    public enum ContentMode: Sendable {
        /// Match the composition's aspect ratio inside the bounds, letterboxing on the
        /// short axis. Overlays render only inside the letterboxed display rect.
        case fit
        /// Fill the bounds, cropping the long axis of the composition. Overlays still
        /// render in composition coordinates; parts outside the host bounds are clipped.
        case fill
        /// Scale x and y independently to fill the bounds. Matches pre-v0.4.4 behavior.
        /// Use this when the parent pins the aspect ratio with `.aspectRatio(...)`.
        case stretch
    }

    private let video: Video
    private let contentMode: ContentMode
    private let currentTime: CMTime?
    private let customRenderer: ((any Overlay) -> AnyView?)?
    private var onTapHandler: ((LayerID) -> Void)?
    private var onDragChangedHandler: ((LayerID, CGSize) -> Void)?
    private var onDragEndedHandler: ((LayerID, CGSize) -> Void)?

    /// Optional binding for single-overlay selection. When bound, tapping
    /// an overlay writes its `LayerID` here. Render sites union-check
    /// against ``selectedLayerIDs`` via ``overlayMatchesSelection(id:single:set:)``
    /// and draw a selection ring on every matching overlay. Added in v0.10.
    private let selectedLayerID: Binding<LayerID?>?

    /// Optional binding for multi-overlay selection. Coexists with
    /// ``selectedLayerID``; render sites union-check both bindings. The
    /// consumer manages set membership (taps don't auto-toggle membership —
    /// taps write the single binding instead). Added in v0.10.
    private let selectedLayerIDs: Binding<Set<LayerID>>?

    /// Create an overlay host for `video`.
    /// - Parameters:
    ///   - video: The Kadr composition whose ``Kadr/Video/overlays`` are rendered.
    ///   - contentMode: How the composition's display rectangle fits inside the host's
    ///     bounds. Defaults to `.fit`.
    ///   - currentTime: Composition time used to honor each overlay's
    ///     ``Kadr/Overlay/visibilityRange``. When `nil` (the default), all overlays render
    ///     unconditionally.
    ///   - customRenderer: Optional per-overlay renderer. Return a view to replace the
    ///     default rendering for that overlay; return `nil` to fall through to the
    ///     built-in renderer.
    public init(
        _ video: Video,
        contentMode: ContentMode = .fit,
        currentTime: CMTime? = nil,
        selectedLayerID: Binding<LayerID?>? = nil,
        selectedLayerIDs: Binding<Set<LayerID>>? = nil,
        customRenderer: ((any Overlay) -> AnyView?)? = nil
    ) {
        self.video = video
        self.contentMode = contentMode
        self.currentTime = currentTime
        self.selectedLayerID = selectedLayerID
        self.selectedLayerIDs = selectedLayerIDs
        self.customRenderer = customRenderer
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(video.overlays.indices, id: \.self) { index in
                    let overlay = video.overlays[index]
                    if Self.isVisible(overlay: overlay, at: currentTime) {
                        overlayView(for: overlay, in: geometry.size)
                    }
                }
            }
        }
    }

    /// Returns `true` if `overlay` should render at composition time `time`. Pure helper
    /// for unit tests. Untimed overlays (no `visibilityRange`) always return `true`.
    /// When `time` is `nil`, returns `true` regardless of `visibilityRange`.
    static func isVisible(overlay: any Overlay, at time: CMTime?) -> Bool {
        guard let range = overlay.visibilityRange else { return true }
        guard let t = time else { return true }
        return range.containsTime(t)
    }

    @ViewBuilder
    private func overlayView(for overlay: any Overlay, in containerSize: CGSize) -> some View {
        let frame = computeFrame(for: overlay, in: containerSize)
        let resolved = customRenderer?(overlay) ?? defaultView(for: overlay)
        let isSelected = OverlayHost.overlayMatchesSelection(
            id: overlay.layerID,
            single: selectedLayerID?.wrappedValue,
            set: selectedLayerIDs?.wrappedValue
        )
        let visual = resolved
            .frame(width: frame.width, height: frame.height)
            .opacity(overlay.opacity)
            // v0.10 — selection ring matches TimelineView's clip-selection
            // visual: white stroke, 2pt, slight corner radius. Rendered
            // outside the opacity so the ring stays fully visible even
            // when the overlay itself is partially transparent.
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.white : .clear, lineWidth: 2)
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])

        Group {
            if let id = overlay.layerID, hasAnyGestureHandler {
                visual
                    .onTapGesture {
                        // v0.10 — when `selectedLayerID` is bound, tapping
                        // writes the id (matching TimelineView's pattern).
                        // Tapping the already-selected overlay clears it,
                        // mirroring chain-clip tap-to-deselect.
                        if let binding = selectedLayerID {
                            binding.wrappedValue = (binding.wrappedValue == id) ? nil : id
                        }
                        onTapHandler?(id)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                onDragChangedHandler?(id, value.translation)
                            }
                            .onEnded { value in
                                onDragEndedHandler?(id, value.translation)
                            }
                    )
            } else {
                visual
            }
        }
        .position(x: frame.midX, y: frame.midY)
    }

    private var hasAnyGestureHandler: Bool {
        onTapHandler != nil || onDragChangedHandler != nil ||
        onDragEndedHandler != nil || selectedLayerID != nil
    }

    /// Whether an overlay with `id` should render as selected, given the
    /// union of the single-binding and set-binding selection state. Used
    /// by ``overlayView(for:in:)`` so the rule has a single seam.
    ///
    /// Mirrors v0.9.2's ``TimelineView/clipMatchesSelection(id:single:set:)``.
    /// `nonisolated` for testability.
    public nonisolated static func overlayMatchesSelection(
        id: LayerID?,
        single: LayerID?,
        set: Set<LayerID>?
    ) -> Bool {
        guard let id else { return false }
        if single == id { return true }
        if let set, set.contains(id) { return true }
        return false
    }

    private func computeFrame(for overlay: any Overlay, in containerSize: CGSize) -> CGRect {
        let renderSize = video.preset.resolution
        guard renderSize.width > 0, renderSize.height > 0 else { return .zero }

        let renderFrame = Kadr.Layout.resolveFrame(
            position: overlay.position,
            size: overlay.size ?? .normalized(width: 0.3, height: 0.3),
            anchor: overlay.anchor,
            in: renderSize
        )
        return Self.containerFrame(
            renderFrame: renderFrame,
            renderSize: renderSize,
            containerSize: containerSize,
            contentMode: contentMode
        )
    }

    /// Maps a frame from composition coordinates (`renderSize`) into host coordinates
    /// (`containerSize`) under the given `contentMode`. Pure helper for unit tests.
    static func containerFrame(
        renderFrame: CGRect,
        renderSize: CGSize,
        containerSize: CGSize,
        contentMode: ContentMode
    ) -> CGRect {
        guard renderSize.width > 0, renderSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }

        switch contentMode {
        case .stretch:
            let scaleX = containerSize.width / renderSize.width
            let scaleY = containerSize.height / renderSize.height
            return CGRect(
                x: renderFrame.origin.x * scaleX,
                y: renderFrame.origin.y * scaleY,
                width: renderFrame.size.width * scaleX,
                height: renderFrame.size.height * scaleY
            )

        case .fit, .fill:
            let aspectComp = renderSize.width / renderSize.height
            let aspectCont = containerSize.width / containerSize.height
            let widthDominates = (contentMode == .fit) ? (aspectComp > aspectCont) : (aspectComp < aspectCont)
            let scale: CGFloat
            let displaySize: CGSize
            if widthDominates {
                scale = containerSize.width / renderSize.width
                displaySize = CGSize(width: containerSize.width, height: renderSize.height * scale)
            } else {
                scale = containerSize.height / renderSize.height
                displaySize = CGSize(width: renderSize.width * scale, height: containerSize.height)
            }
            let offsetX = (containerSize.width - displaySize.width) / 2
            let offsetY = (containerSize.height - displaySize.height) / 2
            return CGRect(
                x: renderFrame.origin.x * scale + offsetX,
                y: renderFrame.origin.y * scale + offsetY,
                width: renderFrame.size.width * scale,
                height: renderFrame.size.height * scale
            )
        }
    }

    private func defaultView(for overlay: any Overlay) -> AnyView {
        if let img = overlay as? ImageOverlay {
            return AnyView(
                Image(platformImage: img.image)
                    .resizable()
                    .scaledToFit()
            )
        }
        if let text = overlay as? TextOverlay {
            return AnyView(textOverlayView(text))
        }
        if let sticker = overlay as? StickerOverlay {
            return AnyView(stickerOverlayView(sticker))
        }
        return AnyView(EmptyView())
    }

    @ViewBuilder
    private func textOverlayView(_ overlay: TextOverlay) -> some View {
        if overlay.textAnimation != nil {
            AnimatedTextLayerView(overlay: overlay)
        } else {
            let style = overlay.style
            Text(overlay.text)
                .font(font(for: style))
                .foregroundStyle(Color(platformColor: style.color))
                .multilineTextAlignment(textAlignment(for: style.alignment))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment(for: style.alignment))
        }
    }

    @ViewBuilder
    private func stickerOverlayView(_ overlay: StickerOverlay) -> some View {
        let view = Image(platformImage: overlay.image)
            .resizable()
            .scaledToFit()
            .rotationEffect(.radians(overlay.rotation))
        if let shadow = overlay.shadow {
            view.shadow(
                color: Color(platformColor: shadow.color).opacity(shadow.opacity),
                radius: CGFloat(shadow.radius),
                x: shadow.offset.width,
                y: shadow.offset.height
            )
        } else {
            view
        }
    }

    // MARK: - TextStyle bridges

    private func font(for style: TextStyle) -> Font {
        let size = CGFloat(style.fontSize)
        if let name = style.fontName {
            return .custom(name, size: size)
        }
        switch style.weight {
        case .regular: return .system(size: size, weight: .regular)
        case .medium:  return .system(size: size, weight: .medium)
        case .bold:    return .system(size: size, weight: .bold)
        }
    }

    private func textAlignment(for alignment: TextStyle.Alignment) -> TextAlignment {
        switch alignment {
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }

    private func frameAlignment(for alignment: TextStyle.Alignment) -> Alignment {
        switch alignment {
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Gesture modifiers

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension OverlayHost {

    /// Attach a tap handler that fires with the tapped overlay's ``Kadr/LayerID``.
    ///
    /// Only overlays with a non-`nil` ``Kadr/LayerID/`` participate. The handler is
    /// invoked on `MainActor`; it's safe to mutate `@State` from inside.
    ///
    /// ```swift
    /// OverlayHost(video)
    ///     .onLayerTap { id in selectedLayerID = id }
    /// ```
    public func onLayerTap(_ action: @escaping (LayerID) -> Void) -> OverlayHost {
        var copy = self
        copy.onTapHandler = action
        return copy
    }

    /// Attach drag handlers that fire with the dragged overlay's ``Kadr/LayerID`` and
    /// the cumulative translation in the host's coordinate space.
    ///
    /// Use `onChanged` to track movement during the drag (e.g. update a preview transform);
    /// use `onEnded` to commit the final position. Both are optional; pass `nil` to skip
    /// either phase. Only overlays with a non-`nil` ``Kadr/LayerID`` participate.
    /// Drag uses a 5-pt minimum distance so taps and drags don't conflict.
    ///
    /// ```swift
    /// OverlayHost(video)
    ///     .onLayerDrag(
    ///         onChanged: { id, t in livePreviewOffset[id] = t },
    ///         onEnded:   { id, t in commit(id, finalOffset: t) }
    ///     )
    /// ```
    public func onLayerDrag(
        onChanged: ((LayerID, CGSize) -> Void)? = nil,
        onEnded: ((LayerID, CGSize) -> Void)? = nil
    ) -> OverlayHost {
        var copy = self
        copy.onDragChangedHandler = onChanged
        copy.onDragEndedHandler = onEnded
        return copy
    }
}
