// SimpleViewer — Minimal SwiftUI app demonstrating KadrUI
//
// To run this example:
// 1. Create a new Xcode project (iOS App or macOS App, SwiftUI lifecycle)
// 2. Add `kadr-ui` as a local Swift package dependency (Kadr is pulled transitively)
// 3. Copy this file into your project and use `SimpleViewerView` as your root view
//
// No external resources. The demo composition is built entirely from system symbols
// rendered into ImageClips, plus a TextOverlay and a StickerOverlay so the
// OverlayHost has something to draw, plus a TimelineView demoing v0.4.1's
// selection / reorder / trim.

#if canImport(SwiftUI)
import SwiftUI
import CoreMedia
import Kadr
import KadrUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
struct SimpleViewerView: View {
    @State private var clips: [any Clip] = SimpleViewerView.makeDemoClips()
    @State private var selectedLayerID: LayerID?
    @State private var selectedClipID: ClipID?
    @State private var playheadTime: CMTime = .zero
    @State private var liveDragOffsets: [String: CGSize] = [:]

    /// Rebuild the Video from current clips state on every render. The result-builder
    /// `for` loop in VideoBuilder accepts a heterogeneous [any Clip].
    private var video: Video {
        Video {
            for clip in clips { clip }
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
            StickerOverlay(Self.symbol("star.fill", size: 200, tint: .systemYellow))
                .position(.center)
                .size(.normalized(width: 0.3, height: 0.3))
                .rotation(degrees: -15)
                .id("sticker")
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            ZStack {
                VideoPreview(video)
                OverlayHost(video) { overlay in
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
                .onLayerTap { id in selectedLayerID = id }
                .onLayerDrag(
                    onChanged: { id, t in liveDragOffsets[id.rawValue] = t },
                    onEnded:   { id, _ in liveDragOffsets[id.rawValue] = nil }
                )
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

            TimelineView(
                video,
                currentTime: $playheadTime,
                selectedClipID: $selectedClipID,
                onReorder: { _, _, newClips in
                    clips = newClips
                },
                onTrim: { index, leading, trailing in
                    clips[index] = Self.applyTrim(to: clips[index], leading: leading, trailing: trailing)
                }
            )
            .frame(height: 78)   // 14 (scrub strip) + 4 (spacing) + 40 (clips) + 4 + 12 (audio) ≈ 74
            .padding(8)
            .background(.gray.opacity(0.15), in: .rect(cornerRadius: 8))

            footer
        }
        .padding()
    }

    // MARK: - Pieces

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 4) {
            Text("KadrUI Sample").font(.title2.bold())
            Text("Tap overlays / clips to select. Drag clips to reorder, drag clip edges to trim. Tap the scrub strip above the timeline to seek.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Selected overlay:")
                Text(selectedLayerID?.rawValue ?? "—")
                    .foregroundStyle(.secondary).monospaced()
            }
            HStack {
                Text("Selected clip:")
                Text(selectedClipID?.rawValue ?? "—")
                    .foregroundStyle(.secondary).monospaced()
            }
            HStack {
                Text("Playhead:")
                Text(String(format: "%.2fs", CMTimeGetSeconds(playheadTime)))
                    .foregroundStyle(.secondary).monospaced()
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

    private static func makeDemoClips() -> [any Clip] {
        let blue   = symbol("photo.fill",     size: 400, tint: .systemBlue)
        let purple = symbol("rectangle.fill", size: 400, tint: .systemPurple)
        let green  = symbol("circle.fill",    size: 400, tint: .systemGreen)
        return [
            ImageClip(blue,   duration: 2.0).id("intro"),
            Kadr.Transition.dissolve(duration: 0.5),
            ImageClip(purple, duration: 2.0).id("body"),
            Kadr.Transition.fade(duration: 0.5),
            ImageClip(green,  duration: 2.0).id("outro"),
        ]
    }

    /// Apply a trim delta from `TimelineView.onTrim` to a clip. Demonstrates the
    /// per-type mapping documented in `TimelineView.init`.
    private static func applyTrim(to clip: any Clip, leading: CMTime, trailing: CMTime) -> any Clip {
        // For ImageClip / TitleSequence, only the back handle normally moves; treat
        // both deltas as duration changes by subtracting their sum from current duration.
        if let img = clip as? ImageClip {
            let newDuration = CMTimeSubtract(img.duration, CMTimeAdd(leading, trailing))
            // Clamp to a sane minimum so the sample doesn't crash on over-trim.
            let minDuration = CMTime(seconds: 0.1, preferredTimescale: 600)
            return img.duration(CMTimeMaximum(newDuration, minDuration))
        }
        if let title = clip as? TitleSequence {
            let newDuration = CMTimeSubtract(title.duration, CMTimeAdd(leading, trailing))
            let minDuration = CMTime(seconds: 0.1, preferredTimescale: 600)
            // TitleSequence has no `.duration(_:)` modifier, so we'd need to rebuild from
            // scratch. Out of scope for this sample — TitleSequence isn't in our demo.
            _ = (newDuration, minDuration)
            return title
        }
        // VideoClip: shift trimRange by (leading, -trailing). Out of scope for this
        // demo (we only use ImageClips); shown here as a comment for future readers.
        return clip
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
