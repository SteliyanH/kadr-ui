import SwiftUI
import Kadr

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
/// **Layout contract.** `OverlayHost` assumes its own bounds equal the video's display
/// rectangle — i.e. the parent uses `.aspectRatio(...)` so the container matches the
/// composition's aspect ratio with no letterboxing. If the parent letterboxes, overlays
/// will appear in the letterbox bands, not aligned to the video.
///
/// **Overlays without explicit `size`.** Kadr's `Overlay.size` is optional. When `nil`,
/// `OverlayHost` uses a default frame of 30% × 30% of the canvas as a v1 placeholder.
/// This may not match the export — set `.size(...)` explicitly on the overlay if pixel
/// alignment matters in preview.
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct OverlayHost: View {

    private let video: Video
    private let customRenderer: ((any Overlay) -> AnyView?)?
    private var onTapHandler: ((LayerID) -> Void)?
    private var onDragChangedHandler: ((LayerID, CGSize) -> Void)?
    private var onDragEndedHandler: ((LayerID, CGSize) -> Void)?

    /// Create an overlay host for `video`.
    /// - Parameters:
    ///   - video: The Kadr composition whose ``Kadr/Video/overlays`` are rendered.
    ///   - customRenderer: Optional per-overlay renderer. Return a view to replace the
    ///     default rendering for that overlay; return `nil` to fall through to the
    ///     built-in renderer.
    public init(_ video: Video, customRenderer: ((any Overlay) -> AnyView?)? = nil) {
        self.video = video
        self.customRenderer = customRenderer
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(video.overlays.indices, id: \.self) { index in
                    overlayView(for: video.overlays[index], in: geometry.size)
                }
            }
        }
    }

    @ViewBuilder
    private func overlayView(for overlay: any Overlay, in containerSize: CGSize) -> some View {
        let frame = computeFrame(for: overlay, in: containerSize)
        let resolved = customRenderer?(overlay) ?? defaultView(for: overlay)
        let visual = resolved
            .frame(width: frame.width, height: frame.height)
            .opacity(overlay.opacity)

        Group {
            if let id = overlay.layerID, hasAnyGestureHandler {
                visual
                    .onTapGesture { onTapHandler?(id) }
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
        onTapHandler != nil || onDragChangedHandler != nil || onDragEndedHandler != nil
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
        let scaleX = containerSize.width / renderSize.width
        let scaleY = containerSize.height / renderSize.height
        return CGRect(
            x: renderFrame.origin.x * scaleX,
            y: renderFrame.origin.y * scaleY,
            width: renderFrame.size.width * scaleX,
            height: renderFrame.size.height * scaleY
        )
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
        let style = overlay.style
        Text(overlay.text)
            .font(font(for: style))
            .foregroundStyle(Color(platformColor: style.color))
            .multilineTextAlignment(textAlignment(for: style.alignment))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment(for: style.alignment))
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
