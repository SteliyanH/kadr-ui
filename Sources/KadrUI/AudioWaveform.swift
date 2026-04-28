import Foundation
import SwiftUI
import AVFoundation
import CoreMedia

/// A pre-computed audio waveform — a fixed-length array of normalized peak values
/// suitable for rendering as a row of bars or a polyline.
///
/// Each entry is a non-negative `Float` typically in `0.0...1.0` (the loader
/// normalizes to the peak sample magnitude observed in the asset, so a near-silent
/// file still renders visibly). Index `0` is the start of the asset; `peaks.count - 1`
/// is the end.
///
/// Build via ``AudioWaveformLoader/load(url:sampleCount:)``. Treat the value as
/// expensive-to-produce and cache for reuse — kadr-ui's `TimelineView` does this
/// internally when `showAudioWaveforms` is enabled.
public struct AudioWaveform: Sendable, Equatable {

    /// Peak values, ordered start-to-end of the source asset. Always non-negative.
    public let peaks: [Float]

    public init(peaks: [Float]) {
        self.peaks = peaks
    }

    /// Empty waveform (no peaks). Useful as a fallback while loading.
    public static let empty = AudioWaveform(peaks: [])
}

/// Pure helpers for waveform sample math. Surface as nonisolated statics so they
/// can run inside an `AVAssetReader` background queue without actor hops.
extension AudioWaveform {

    /// Bucket-peaks `samples` (raw signed amplitudes in `-1.0...1.0`) into exactly
    /// `bucketCount` non-negative peak values. Each bucket's peak is the maximum
    /// absolute sample inside it.
    ///
    /// `samples.count == 0` or `bucketCount <= 0` returns an empty array. When
    /// `samples.count < bucketCount`, the result is padded with zeros for missing
    /// buckets so consumers always receive `bucketCount` entries.
    nonisolated static func bucketPeaks(samples: [Float], bucketCount: Int) -> [Float] {
        guard bucketCount > 0 else { return [] }
        guard !samples.isEmpty else {
            return Array(repeating: 0, count: bucketCount)
        }
        if samples.count <= bucketCount {
            // Map each sample into one bucket; pad the remainder with zeros.
            var out = Array(repeating: Float(0), count: bucketCount)
            for i in samples.indices {
                out[i] = abs(samples[i])
            }
            return out
        }
        // Even bucketing: each bucket spans roughly samples.count / bucketCount
        // entries. Use floating-point boundaries to avoid systematic drift on
        // non-divisible counts.
        var out: [Float] = []
        out.reserveCapacity(bucketCount)
        let step = Double(samples.count) / Double(bucketCount)
        for i in 0..<bucketCount {
            let startIdx = Int((Double(i) * step).rounded(.down))
            let endIdx = min(samples.count, Int((Double(i + 1) * step).rounded(.down)))
            var peak: Float = 0
            for j in startIdx..<endIdx {
                let mag = abs(samples[j])
                if mag > peak { peak = mag }
            }
            out.append(peak)
        }
        return out
    }

    /// Scale every peak so the maximum becomes `1.0`, preserving relative shape.
    /// A waveform with all-zero peaks is returned unchanged. Pure.
    nonisolated static func normalized(_ peaks: [Float]) -> [Float] {
        guard let maxPeak = peaks.max(), maxPeak > 0 else { return peaks }
        return peaks.map { $0 / maxPeak }
    }
}

// MARK: - Rendering

/// SwiftUI `Shape` that draws an ``AudioWaveform`` as symmetric vertical bars
/// centered on the rect's vertical midline. Each peak `p` produces a bar of height
/// `p * rect.height` (clamped to the rect's height).
///
/// Internal so kadr-ui owns the visual style. Custom waveform rendering is one of
/// the things the next minor version may expose more directly; for now `TimelineView`
/// uses this shape with a fixed white-on-block fill.
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
struct AudioWaveformShape: Shape {

    let peaks: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !peaks.isEmpty, rect.width > 0, rect.height > 0 else { return path }

        // Decimate or stretch peaks to span the rect's pixel width. Use one bar per
        // pixel column when peaks.count >= rect.width, else stretch each peak to a
        // multi-pixel bar. Bar width never drops below 1 pixel.
        let columnCount = max(1, Int(rect.width.rounded(.down)))
        let resampled = AudioWaveform.bucketPeaks(samples: peaks, bucketCount: columnCount)
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
