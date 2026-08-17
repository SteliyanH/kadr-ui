import Testing
import CoreGraphics
import CoreVideo
@testable import KadrUI

/// v0.14 — the eyedropper's geometry, tested without a player or a frame.
///
/// Mapping a tap to a pixel through aspect-fit letterboxing is the part of
/// tap-to-sample that is easy to get subtly wrong and impossible to notice by
/// eye: an off-by-a-bar error still returns *a* colour, just the wrong one.
/// `VideoSampling` is free functions precisely so this can be checked on CI,
/// which cannot decode media.
struct VideoSamplingTests {

    // MARK: - videoRect

    @Test func matchingAspectFillsTheBounds() {
        let rect = VideoSampling.videoRect(
            in: CGSize(width: 100, height: 200),
            presentation: CGSize(width: 50, height: 100)
        )
        #expect(rect == CGRect(x: 0, y: 0, width: 100, height: 200))
    }

    @Test func tallVideoInWideBoundsGetsSideBars() {
        // 9:16 inside a square: full height, bars left and right.
        let rect = VideoSampling.videoRect(
            in: CGSize(width: 200, height: 200),
            presentation: CGSize(width: 90, height: 160)
        )
        #expect(rect.height == 200)
        #expect(rect.width == 112.5)
        #expect(rect.minX == 43.75)   // centred
    }

    @Test func wideVideoInTallBoundsGetsTopAndBottomBars() {
        let rect = VideoSampling.videoRect(
            in: CGSize(width: 200, height: 200),
            presentation: CGSize(width: 160, height: 90)
        )
        #expect(rect.width == 200)
        #expect(rect.height == 112.5)
        #expect(rect.minY == 43.75)
    }

    @Test func degenerateSizesGiveNull() {
        #expect(VideoSampling.videoRect(in: .zero, presentation: CGSize(width: 9, height: 16)).isNull)
        #expect(VideoSampling.videoRect(in: CGSize(width: 10, height: 10), presentation: .zero).isNull)
    }

    // MARK: - normalizedPoint

    @Test func centreTapMapsToCentre() {
        let p = VideoSampling.normalizedPoint(
            forTapAt: CGPoint(x: 100, y: 100),
            in: CGSize(width: 200, height: 200),
            presentation: CGSize(width: 90, height: 160)
        )
        #expect(p?.x == 0.5)
        #expect(p?.y == 0.5)
    }

    @Test func tapInASideBarSamplesNothing() {
        // x = 10 is inside the view but left of the picture. Must be nil, not
        // black: a caller cannot distinguish "the surround" from "dark footage".
        let p = VideoSampling.normalizedPoint(
            forTapAt: CGPoint(x: 10, y: 100),
            in: CGSize(width: 200, height: 200),
            presentation: CGSize(width: 90, height: 160)
        )
        #expect(p == nil)
    }

    @Test func tapInATopBarSamplesNothing() {
        let p = VideoSampling.normalizedPoint(
            forTapAt: CGPoint(x: 100, y: 5),
            in: CGSize(width: 200, height: 200),
            presentation: CGSize(width: 160, height: 90)
        )
        #expect(p == nil)
    }

    @Test func topLeftOfThePictureIsTheOrigin() {
        // Origin is top-left in both SwiftUI and CVPixelBuffer row order, so no
        // caller should ever need to flip y.
        let p = VideoSampling.normalizedPoint(
            forTapAt: CGPoint(x: 43.75, y: 0),
            in: CGSize(width: 200, height: 200),
            presentation: CGSize(width: 90, height: 160)
        )
        #expect(p?.x == 0)
        #expect(p?.y == 0)
    }

    @Test func unresolvedPresentationSizeSamplesNothing() {
        // presentationSize is .zero for the first frames after load; a tap then
        // must not resolve to a bogus point.
        let p = VideoSampling.normalizedPoint(
            forTapAt: CGPoint(x: 50, y: 50),
            in: CGSize(width: 200, height: 200),
            presentation: .zero
        )
        #expect(p == nil)
    }

    // MARK: - rgb

    private func makeBGRA(width: Int, height: Int, fill: (b: UInt8, g: UInt8, r: UInt8)) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pb = buffer!
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        for y in 0..<height {
            for x in 0..<width {
                let p = base.advanced(by: y * rowBytes + x * 4)
                p[0] = fill.b; p[1] = fill.g; p[2] = fill.r; p[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    @Test func readsTheChannelsInBGRAOrder() {
        // Pure red written as BGRA must come back as red, not blue. Getting the
        // byte order backwards is the classic failure and looks plausible.
        let pb = makeBGRA(width: 4, height: 4, fill: (b: 0, g: 0, r: 255))
        let rgb = VideoSampling.rgb(at: CGPoint(x: 0.5, y: 0.5), in: pb)
        #expect(rgb?.red == 1.0)
        #expect(rgb?.green == 0.0)
        #expect(rgb?.blue == 0.0)
    }

    @Test func normalisedOneClampsInsideTheBuffer() {
        // 1.0 * width would index one past the last pixel.
        let pb = makeBGRA(width: 4, height: 4, fill: (b: 10, g: 20, r: 30))
        let rgb = VideoSampling.rgb(at: CGPoint(x: 1.0, y: 1.0), in: pb)
        #expect(rgb != nil)
    }

    @Test func outOfRangePointsAreClampedRatherThanCrashing() {
        let pb = makeBGRA(width: 4, height: 4, fill: (b: 0, g: 255, r: 0))
        #expect(VideoSampling.rgb(at: CGPoint(x: -3, y: -3), in: pb)?.green == 1.0)
        #expect(VideoSampling.rgb(at: CGPoint(x: 9, y: 9), in: pb)?.green == 1.0)
    }
}
