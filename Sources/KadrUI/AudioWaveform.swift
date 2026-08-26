import Foundation
import SwiftUI
import CoreGraphics
import Kadr

// MARK: - Re-exports
//
// `AudioWaveform` and `AudioWaveformLoader` moved into kadr core in 0.18.0.
// Reading an audio file's peaks should not require importing a view package —
// core already ships `ThumbnailGenerator` for the visual equivalent, and this is
// its audio twin.
//
// These aliases keep every existing `KadrUI.AudioWaveform` reference compiling.
// Drawing the peaks stays here: producing the values is core's job, deciding what
// they look like is not.

public typealias AudioWaveform = Kadr.AudioWaveform
public typealias AudioWaveformLoader = Kadr.AudioWaveformLoader

// MARK: - Rendering

/// SwiftUI `Shape` that draws an ``AudioWaveform`` as symmetric vertical bars
/// centered on the rect's vertical midline. Each peak `p` produces a bar of height
/// `p * rect.height` (clamped to the rect's height).
///
/// Internal so kadr-ui owns the visual style. Custom waveform rendering is one of
/// the things the next minor version may expose more directly; for now `TimelineView`
/// uses this shape with a fixed white-on-block fill.
struct AudioWaveformShape: Shape {

    let peaks: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !peaks.isEmpty, rect.width > 0, rect.height > 0 else { return path }

        // Decimate or stretch peaks to span the rect's pixel width. Use one bar per
        // pixel column when peaks.count >= rect.width, else stretch each peak to a
        // multi-pixel bar. Bar width never drops below 1 pixel.
        let columnCount = max(1, Int(rect.width.rounded(.down)))
        let resampled = AudioWaveform(peaks: peaks).resampled(to: columnCount).peaks
        let columnWidth = rect.width / CGFloat(columnCount)
        let midY = rect.midY
        let halfHeight = rect.height / 2

        for (i, peak) in resampled.enumerated() {
            let h = max(0, CGFloat(peak)) * halfHeight
            let x = rect.minX + CGFloat(i) * columnWidth
            // Each bar is a thin rect spanning columnWidth × (2 * h), centered on midY.
            let bar = CGRect(x: x, y: midY - h, width: max(1, columnWidth), height: max(0.5, 2 * h))
            path.addRect(bar)
        }
        return path
    }
}
