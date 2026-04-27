import Testing
import CoreGraphics
import CoreMedia
import Kadr
@testable import KadrUI

/// Unit tests for the pure helpers introduced in v0.4.4 — visibility gating and
/// content-mode layout math.
struct OverlayHostHelpersTests {

    // MARK: - isVisible

    @Test func untimedOverlayAlwaysVisible() {
        let overlay = TextOverlay("hi")
        #expect(OverlayHost.isVisible(overlay: overlay, at: nil))
        #expect(OverlayHost.isVisible(overlay: overlay, at: CMTime(seconds: 0, preferredTimescale: 600)))
        #expect(OverlayHost.isVisible(overlay: overlay, at: CMTime(seconds: 999, preferredTimescale: 600)))
    }

    @Test func timedOverlayHiddenOutsideRange() {
        let overlay = TextOverlay("hi").visible(during: 1.0...2.0)
        #expect(!OverlayHost.isVisible(overlay: overlay, at: CMTime(seconds: 0.5, preferredTimescale: 600)))
        #expect(OverlayHost.isVisible(overlay: overlay, at: CMTime(seconds: 1.5, preferredTimescale: 600)))
        #expect(!OverlayHost.isVisible(overlay: overlay, at: CMTime(seconds: 2.5, preferredTimescale: 600)))
    }

    @Test func timedOverlayWithNilTimeAlwaysVisible() {
        let overlay = TextOverlay("hi").visible(during: 1.0...2.0)
        #expect(OverlayHost.isVisible(overlay: overlay, at: nil))
    }

    // MARK: - containerFrame: stretch (legacy)

    @Test func stretchScalesIndependently() {
        // Composition 1000×500, container 2000×500 — stretch keeps overlay at 0.5x width.
        let render = CGRect(x: 100, y: 100, width: 200, height: 100)
        let result = OverlayHost.containerFrame(
            renderFrame: render,
            renderSize: CGSize(width: 1000, height: 500),
            containerSize: CGSize(width: 2000, height: 500),
            contentMode: .stretch
        )
        #expect(result == CGRect(x: 200, y: 100, width: 400, height: 100))
    }

    // MARK: - containerFrame: fit

    @Test func fitLetterboxesShortAxis() {
        // Composition is 1080×1920 (9:16). Container 1000×1000 (1:1). Height dominates.
        // Display rect: 562.5×1000 centered horizontally — bands of (1000-562.5)/2 = 218.75 on each side.
        let render = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let result = OverlayHost.containerFrame(
            renderFrame: render,
            renderSize: CGSize(width: 1080, height: 1920),
            containerSize: CGSize(width: 1000, height: 1000),
            contentMode: .fit
        )
        let scale = 1000.0 / 1920.0
        let expectedWidth = 1080.0 * scale
        let expectedOffsetX = (1000.0 - expectedWidth) / 2
        #expect(abs(result.origin.x - expectedOffsetX) < 0.001)
        #expect(abs(result.origin.y - 0) < 0.001)
        #expect(abs(result.size.width - expectedWidth) < 0.001)
        #expect(abs(result.size.height - 1000) < 0.001)
    }

    @Test func fitMatchingAspectMatchesStretch() {
        // When container aspect == composition aspect, fit and stretch produce the same frame.
        let render = CGRect(x: 100, y: 200, width: 50, height: 80)
        let renderSize = CGSize(width: 1000, height: 500)
        let containerSize = CGSize(width: 2000, height: 1000)
        let fit = OverlayHost.containerFrame(
            renderFrame: render, renderSize: renderSize,
            containerSize: containerSize, contentMode: .fit
        )
        let stretch = OverlayHost.containerFrame(
            renderFrame: render, renderSize: renderSize,
            containerSize: containerSize, contentMode: .stretch
        )
        #expect(fit == stretch)
    }

    // MARK: - containerFrame: fill

    @Test func fillCropsLongAxis() {
        // Composition 1080×1920, container 1000×1000. Fill makes width fill (1000)
        // and crops top/bottom — display rect is 1000×(1080→ container width scale * 1920).
        let render = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let result = OverlayHost.containerFrame(
            renderFrame: render,
            renderSize: CGSize(width: 1080, height: 1920),
            containerSize: CGSize(width: 1000, height: 1000),
            contentMode: .fill
        )
        let scale = 1000.0 / 1080.0
        let expectedHeight = 1920.0 * scale
        let expectedOffsetY = (1000.0 - expectedHeight) / 2  // negative — overflows top + bottom
        #expect(abs(result.origin.x - 0) < 0.001)
        #expect(abs(result.origin.y - expectedOffsetY) < 0.001)
        #expect(abs(result.size.width - 1000) < 0.001)
        #expect(abs(result.size.height - expectedHeight) < 0.001)
    }

    // MARK: - containerFrame: degenerate

    @Test func zeroSizesReturnZero() {
        let render = CGRect(x: 10, y: 10, width: 10, height: 10)
        #expect(OverlayHost.containerFrame(
            renderFrame: render, renderSize: .zero,
            containerSize: CGSize(width: 100, height: 100), contentMode: .fit
        ) == .zero)
        #expect(OverlayHost.containerFrame(
            renderFrame: render, renderSize: CGSize(width: 100, height: 100),
            containerSize: .zero, contentMode: .fit
        ) == .zero)
    }
}
