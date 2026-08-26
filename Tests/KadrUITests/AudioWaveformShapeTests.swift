import Testing
import Foundation
import SwiftUI
@testable import KadrUI

/// The waveform *value* and its math moved into kadr core in 0.18/0.19. What stays
/// here is the drawing, and that is what this covers.
///
/// The move left this Shape briefly unable to compile — it called an internal
/// helper that went with the type — so these tests exist to make the rendering path
/// something the suite actually exercises rather than something only the compiler
/// checks.
struct AudioWaveformShapeTests {

    @Test func emptyPeaksDrawNothing() {
        let shape = AudioWaveformShape(peaks: [])
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(path.isEmpty)
    }

    @Test func zeroSizedRectDrawsNothing() {
        let shape = AudioWaveformShape(peaks: [0.2, 0.8])
        #expect(shape.path(in: CGRect(x: 0, y: 0, width: 0, height: 40)).isEmpty)
        #expect(shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 0)).isEmpty)
    }

    @Test func peaksProduceBarsWithinTheRect() {
        let rect = CGRect(x: 0, y: 0, width: 50, height: 40)
        let shape = AudioWaveformShape(peaks: [0.1, 0.5, 1.0, 0.3])
        let path = shape.path(in: rect)

        #expect(!path.isEmpty)
        // Bars are symmetric about the midline, so the drawing never exceeds the rect.
        #expect(path.boundingRect.minY >= rect.minY - 0.5)
        #expect(path.boundingRect.maxY <= rect.maxY + 0.5)
    }

    /// The Shape resamples to one bar per pixel column. Fewer peaks than columns must
    /// stretch rather than leave the tail of the rect blank — the case that broke
    /// when the resampling helper moved packages.
    @Test func fewerPeaksThanColumnsStillSpanTheWidth() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 20)
        let path = AudioWaveformShape(peaks: [1.0, 1.0, 1.0]).path(in: rect)
        #expect(path.boundingRect.width > rect.width * 0.5)
    }
}
