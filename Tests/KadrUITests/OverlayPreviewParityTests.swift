import Testing
import SwiftUI
import CoreText
import Kadr
@testable import KadrUI
#if canImport(AppKit)
import AppKit
#endif

/// `OverlayHost` lays overlays out as kadr's export does.
///
/// Before kadr 1.2 the export placed un-sized text in a full-canvas box, so the
/// preview's 30% × 30% guess was no worse. kadr 1.2 sizes that box to the text,
/// and these tests hold the preview to the same rule: the same default size, the
/// same font, the same scale.
@Suite struct OverlayPreviewParityTests {

    private let canvas = CGSize(width: 1920, height: 1080)

    private func pixels(_ size: Kadr.Size) -> CGSize? {
        if case let .pixels(width, height) = size { return CGSize(width: width, height: height) }
        return nil
    }

    // MARK: - Default size

    @Test func unsizedTextHugsItsText() throws {
        let overlay = TextOverlay("Hello", style: TextStyle(fontSize: 64, weight: .bold))
        let size = try #require(pixels(OverlayHost.naturalSize(of: overlay, in: canvas)))
        #expect(size == overlay.naturalSize(in: canvas), "the box kadr's export uses")
        #expect(size.height < 64 * 2, "one line, not 30% of the canvas: \(size.height)")
    }

    @Test func unsizedOverlayWithoutAnImageTakesAQuarterOfTheCanvas() {
        let size = OverlayHost.naturalSize(of: StickerOverlay(PlatformImage()), in: canvas)
        guard case let .normalized(width, height) = size else {
            Issue.record("expected a normalized size, got \(size)")
            return
        }
        #expect(width == 0.25 && height == 0.25)
    }

    #if os(macOS)
    @Test func unsizedImageTakesItsPixelSize() throws {
        let context = try #require(CGContext(
            data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = NSImage(cgImage: try #require(context.makeImage()), size: NSSize(width: 200, height: 100))
        #expect(pixels(OverlayHost.naturalSize(of: ImageOverlay(image), in: canvas)) == CGSize(width: 200, height: 100))
        #expect(pixels(OverlayHost.naturalSize(of: StickerOverlay(image), in: canvas)) == CGSize(width: 200, height: 100))
    }
    #endif

    // MARK: - Font

    /// The animated text path draws with the font the export draws with. It used to
    /// ask for a bare bold trait, which matched no family and gave Helvetica.
    @Test(arguments: [(TextStyle.Weight.regular, 0.0), (.medium, 0.23), (.bold, 0.4)])
    func animatedTextUsesTheSystemFontAtItsWeight(_ weight: TextStyle.Weight, _ expected: Double) {
        let font = AnimatedTextLayerView.ctFont(for: TextStyle(fontSize: 40, weight: weight))
        let traits = CTFontCopyTraits(font) as NSDictionary
        let actual = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? -1
        #expect(abs(actual - expected) < 0.05, "weight \(weight) rendered at \(actual)")
        #expect(!(CTFontCopyFamilyName(font) as String).contains("Helvetica"))
    }

    @Test func namedFontIsKept() {
        let font = AnimatedTextLayerView.ctFont(for: TextStyle(fontName: "Courier", fontSize: 30))
        #expect((CTFontCopyFamilyName(font) as String) == "Courier")
    }

    // MARK: - Opacity

    @Test func opacityIsAppliedOnce() {
        let animated = TextOverlay("A").opacity(0.5).animation(.fadeIn(duration: 1))
        let still = TextOverlay("A").opacity(0.5)
        #expect(OverlayHost.hostOpacity(for: animated, customRendered: false) == 1,
                "the animated renderer's layer already carries 0.5")
        #expect(OverlayHost.hostOpacity(for: still, customRendered: false) == 0.5)
        #expect(OverlayHost.hostOpacity(for: animated, customRendered: true) == 0.5,
                "a custom view gets the host's opacity")
    }

    // MARK: - Rendered

    #if os(macOS)
    /// Bounding box of the bright pixels, as fractions of the image (top-left origin).
    @MainActor
    private func brightBox(_ video: Video, container: CGSize) throws -> CGRect {
        let view = OverlayHost(video)
            .frame(width: container.width, height: container.height)
            .background(Color.black)
        let image = renderForSnapshot(view, size: container)
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try #require(CGContext(
            data: &data, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<cg.height {
            for x in 0..<cg.width where data[(y * cg.width + x) * 4] > 160 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        try #require(maxX >= 0, "no text pixels found")
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        return CGRect(x: CGFloat(minX) / w, y: CGFloat(minY) / h,
                      width: CGFloat(maxX - minX + 1) / w, height: CGFloat(maxY - minY + 1) / h)
    }

    private func titleVideo(animated: Bool) -> Video {
        var title = TextOverlay("Jumpy", style: TextStyle(fontSize: 96, color: .white, weight: .bold))
            .position(.bottom)
            .anchor(.bottom)
        if animated { title = title.animation(.fadeIn(duration: 0)) }
        return Video { ImageClip(PlatformImage(), duration: 1) }
            .preset(.custom(width: 1920, height: 1080, frameRate: 30, codec: .h264))
            .overlay(title)
    }

    /// In a quarter-size preview, bottom-anchored text sits at the bottom at a
    /// quarter of its export size. Before, it was centred in a 30%-tall box and drawn
    /// at the full 96 pt, so it filled a third of the preview.
    @MainActor
    @Test(arguments: [false, true])
    func bottomAnchoredTextMatchesTheExport(animated: Bool) throws {
        let box = try brightBox(titleVideo(animated: animated), container: CGSize(width: 480, height: 270))
        let natural = TextOverlay("Jumpy", style: TextStyle(fontSize: 96, weight: .bold)).naturalSize(in: canvas)
        #expect(box.maxY > 0.93, "text bottom at \(box.maxY) of the preview")
        #expect(box.height < natural.height / canvas.height,
                "text \(box.height) of the preview tall, its export box is \(natural.height / canvas.height)")
        #expect(box.height > 0.5 * natural.height / canvas.height, "text drawn too small: \(box.height)")
        #expect(abs(box.midX - 0.5) < 0.03, "centred, got \(box.midX)")
    }
    #endif
}
