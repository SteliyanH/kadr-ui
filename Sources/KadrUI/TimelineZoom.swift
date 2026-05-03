import Foundation
import CoreGraphics

/// Horizontal zoom level for ``TimelineView``. Pass via the optional
/// `zoom: Binding<TimelineZoom>?` init parameter to enable pinch-to-zoom and
/// horizontal scrolling.
///
/// ```swift
/// @State private var zoom = TimelineZoom.fitToWidth(360, totalSeconds: 30)
///
/// TimelineView(video, currentTime: $time, zoom: $zoom)
///     .frame(height: 96)
/// ```
///
/// When zoom is bound, the timeline body wraps lanes in a horizontal `ScrollView`
/// and binds a `MagnifyGesture` to mutate `pixelsPerSecond`. When the binding is
/// `nil` (the v0.4–v0.6 default), the timeline keeps the fit-to-width render.
public struct TimelineZoom: Sendable, Equatable {

    /// Density floor — at this scale, a 1-second clip is 8 pixels wide. Anything
    /// below makes selection / drag handles unusable.
    public static let minPixelsPerSecond: Double = 8

    /// Density ceiling — at this scale, a 1-second clip is 400 pixels wide.
    /// Beyond this, scroll widths balloon without visual benefit.
    public static let maxPixelsPerSecond: Double = 400

    /// Current zoom density. Always within `[minPixelsPerSecond, maxPixelsPerSecond]`.
    public var pixelsPerSecond: Double

    public init(pixelsPerSecond: Double) {
        self.pixelsPerSecond = Self.clamp(pixelsPerSecond)
    }

    /// Build a zoom level that fits a composition of `totalSeconds` into the given
    /// pixel `width`. Useful as the initial zoom state — the timeline appears
    /// fully laid out without horizontal scrolling, and the user can pinch to zoom
    /// in from there.
    ///
    /// Clamps to the density bounds; for very long compositions the result floors
    /// to ``minPixelsPerSecond`` and the view scrolls.
    public static func fitToWidth(_ width: Double, totalSeconds: Double) -> TimelineZoom {
        guard totalSeconds > 0, width > 0 else {
            return TimelineZoom(pixelsPerSecond: minPixelsPerSecond)
        }
        return TimelineZoom(pixelsPerSecond: width / totalSeconds)
    }

    /// Multiply the current density by `factor`, clamped. Used by the built-in
    /// pinch gesture; consumers can call directly to drive zoom buttons.
    public func zoomed(by factor: Double) -> TimelineZoom {
        TimelineZoom(pixelsPerSecond: pixelsPerSecond * factor)
    }

    nonisolated internal static func clamp(_ value: Double) -> Double {
        max(minPixelsPerSecond, min(maxPixelsPerSecond, value))
    }
}
