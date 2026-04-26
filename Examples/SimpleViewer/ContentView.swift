// SimpleViewer — Minimal SwiftUI app demonstrating KadrUI
//
// To run this example:
// 1. Create a new Xcode project (iOS App or macOS App, SwiftUI lifecycle)
// 2. Add `kadr-ui` as a local Swift package dependency (Kadr is pulled transitively)
// 3. Copy this file into your project and use `SimpleViewerView` as your root view
//
// No external resources. The demo composition is built entirely from system symbols
// rendered into ImageClips, plus a TextOverlay and a StickerOverlay so the
// OverlayHost has something to draw.

#if canImport(SwiftUI)
import SwiftUI
import Kadr
import KadrUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
struct SimpleViewerView: View {
    @State private var selectedLayerID: LayerID?
    @State private var liveDragOffsets: [String: CGSize] = [:]

    private let video: Video

    init() {
        self.video = Self.makeDemoVideo()
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            ZStack {
                VideoPreview(video)
                OverlayHost(video) { overlay in
                    // Cherry-pick: render the title with a coloured background so its
                    // hit-region is visible. Fall through to defaults for everything else.
                    if let text = overlay as? TextOverlay, text.layerID?.rawValue == "title" {
                        return AnyView(
                            Text(text.text)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.5), in: .rect(cornerRadius: 8))
                        )
                    }
                    return nil
                }
                .onLayerTap { id in
                    selectedLayerID = id
                }
                .onLayerDrag(
                    onChanged: { id, t in
                        liveDragOffsets[id.rawValue] = t
                    },
                    onEnded: { id, _ in
                        liveDragOffsets[id.rawValue] = nil
                    }
                )
                // Highlight the selected layer with a thin outline at its resolved frame.
                if let selected = selectedLayerID,
                   let overlay = video.overlays.first(where: { $0.layerID == selected }) {
                    selectionOutline(for: overlay)
                }
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .background(.black)
            .clipShape(.rect(cornerRadius: 12))

            ThumbnailStrip(video, count: 8)
                .frame(height: 56)
                .clipShape(.rect(cornerRadius: 8))

            footer
        }
        .padding()
    }

    // MARK: - Pieces

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 4) {
            Text("KadrUI Sample").font(.title2.bold())
            Text("Tap an overlay to select. Drag to inspect translation values.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Selected layer:")
                Text(selectedLayerID?.rawValue ?? "—")
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
            if !liveDragOffsets.isEmpty {
                ForEach(liveDragOffsets.keys.sorted(), id: \.self) { id in
                    let t = liveDragOffsets[id, default: .zero]
                    Text("dragging \(id): Δ(\(Int(t.width)), \(Int(t.height)))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func selectionOutline(for overlay: any Overlay) -> some View {
        GeometryReader { geo in
            let render = video.preset.resolution
            let frame = Kadr.Layout.resolveFrame(
                position: overlay.position,
                size: overlay.size ?? .normalized(width: 0.3, height: 0.3),
                anchor: overlay.anchor,
                in: render
            )
            let scaleX = geo.size.width / render.width
            let scaleY = geo.size.height / render.height
            RoundedRectangle(cornerRadius: 4)
                .stroke(.yellow, lineWidth: 2)
                .frame(width: frame.width * scaleX, height: frame.height * scaleY)
                .position(x: frame.midX * scaleX, y: frame.midY * scaleY)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Demo composition

    private static func makeDemoVideo() -> Video {
        let bg = symbol("photo.fill", size: 400, tint: .systemBlue)
        let sticker = symbol("star.fill", size: 200, tint: .systemYellow)

        return Video {
            ImageClip(bg, duration: 4.0)
        }
        .preset(.reelsAndShorts)
        .overlay(
            TextOverlay("KadrUI",
                        style: TextStyle(fontSize: 80, color: .white, alignment: .center, weight: .bold))
                .position(.top)
                .anchor(.top)
                .size(.normalized(width: 0.8, height: 0.12))
                .id("title")
        )
        .overlay(
            StickerOverlay(sticker)
                .position(.center)
                .size(.normalized(width: 0.3, height: 0.3))
                .rotation(degrees: -15)
                .id("sticker")
        )
    }

    private static func symbol(_ name: String, size: CGFloat, tint: PlatformColor) -> PlatformImage {
        #if canImport(UIKit)
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        let img = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        return img ?? UIImage()
        #elseif canImport(AppKit)
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            return img.withSymbolConfiguration(config) ?? img
        }
        return NSImage()
        #endif
    }
}

#Preview {
    SimpleViewerView()
}

#endif
