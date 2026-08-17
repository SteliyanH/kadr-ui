import CoreGraphics
import SwiftUI
import CoreVideo
import Foundation

/// Geometry and pixel reading for ``VideoPreview``'s tap-to-sample.
///
/// Split out as free functions with no AVFoundation or SwiftUI state so the
/// fiddly part — mapping a tap in view space to a pixel in frame space through
/// aspect-fit letterboxing — is unit-testable without a player, a window, or a
/// decodable asset. That matters here: this package's CI runs on virtualised
/// runners that cannot decode media, so anything requiring a real frame is
/// untestable there. The maths is not.
enum VideoSampling {

    /// The rect the video actually occupies inside `bounds`, under aspect-fit.
    ///
    /// `VideoPlayer` letterboxes: a 9:16 composition in a 4:3 view leaves bars
    /// top and bottom, and a tap in a bar is not a tap on the picture. Callers
    /// need the real rect to tell those apart.
    ///
    /// Returns `.null` when either size is degenerate — a zero-sized view or a
    /// player item whose `presentationSize` has not resolved yet, which is the
    /// state during the first frames after load.
    static func videoRect(in bounds: CGSize, presentation: CGSize) -> CGRect {
        guard bounds.width > 0, bounds.height > 0,
              presentation.width > 0, presentation.height > 0
        else { return .null }

        let scale = min(bounds.width / presentation.width, bounds.height / presentation.height)
        let size = CGSize(width: presentation.width * scale, height: presentation.height * scale)
        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Maps a tap in view coordinates to a normalised point in frame space.
    ///
    /// Returns `nil` for a tap outside the picture — in a letterbox bar, or
    /// beyond the view. `nil` means "no sample", never "black": reporting the
    /// surround's colour as if it came from the footage would be a lie the
    /// caller cannot detect.
    ///
    /// Origin is top-left, matching both SwiftUI's coordinate space and
    /// `CVPixelBuffer` row order, so callers never flip it themselves.
    static func normalizedPoint(
        forTapAt tap: CGPoint,
        in bounds: CGSize,
        presentation: CGSize
    ) -> CGPoint? {
        let rect = videoRect(in: bounds, presentation: presentation)
        guard !rect.isNull, rect.contains(tap) else { return nil }

        return CGPoint(
            x: (tap.x - rect.minX) / rect.width,
            y: (tap.y - rect.minY) / rect.height
        )
    }

    /// Reads one pixel from a buffer at a normalised point, as 0...1 RGB.
    ///
    /// Returns `nil` if the buffer is not 32-bit BGRA (what
    /// `AVPlayerItemVideoOutput` is asked for here) or cannot be locked.
    /// Silently reinterpreting another layout would hand back plausible,
    /// wrong colours.
    static func rgb(
        at normalized: CGPoint,
        in buffer: CVPixelBuffer
    ) -> (red: Double, green: Double, blue: Double)? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }

        // Clamp rather than trust: a normalised 1.0 would index one past the
        // last pixel, and a caller could pass a point this type did not produce.
        let x = min(max(Int(normalized.x * Double(width)), 0), width - 1)
        let y = min(max(Int(normalized.y * Double(height)), 0), height - 1)

        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixel = base.advanced(by: y * rowBytes + x * 4).assumingMemoryBound(to: UInt8.self)

        // BGRA byte order.
        return (
            red: Double(pixel[2]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[0]) / 255
        )
    }
}

/// One eyedropper result: the colour under the tap, and where it came from.
///
/// The point travels with the colour so a caller can draw a reticle without
/// tracking the tap itself. Normalised (0...1, top-left origin) rather than in
/// view coordinates, so it stays correct as the preview resizes.
public struct KadrSampledColor: Equatable, Sendable {
    public let color: Color
    public let point: CGPoint

    public init(color: Color, point: CGPoint) {
        self.color = color
        self.point = point
    }
}
