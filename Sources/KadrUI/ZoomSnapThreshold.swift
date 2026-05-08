import Foundation

/// A perceptible zoom-density breakpoint on ``TimelineView``'s pinch-zoom
/// gesture. Used by ``TimelineView/onZoomSnap(_:)`` to fire callbacks when
/// the user crosses a meaningful boundary — frame / second / 5s / 30s
/// alignments — so consumers can wire haptics or label the current zoom
/// bracket.
///
/// Ships with a fixed list (``standard``) at v0.9.0. kadr-ui owns the
/// thresholds because it owns the zoom math; consumers can read the list to
/// label their UI but can't yet pass a custom list (deferred to v0.9.x if
/// community demand surfaces).
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct ZoomSnapThreshold: Sendable, Hashable {

    /// Pixels-per-second density at which the threshold sits. Compared against
    /// `TimelineZoom.pixelsPerSecond`.
    public let pixelsPerSecond: Double

    /// Human-readable label — e.g. `"1f"`, `"1s"`, `"5s"`, `"30s"`. Consumers
    /// can use this in a label ("Snap: 5s") or pick a haptic strength based
    /// on the bracket.
    public let label: String

    public init(pixelsPerSecond: Double, label: String) {
        self.pixelsPerSecond = pixelsPerSecond
        self.label = label
    }

    /// The fixed list shipped at v0.9.0. Sorted ascending by
    /// `pixelsPerSecond` — densest (most zoomed-out) first. Picked from
    /// CapCut / VN feel-tuning: every entry sits at a perceptible alignment
    /// boundary (one timeline frame at 30fps, one second, five seconds,
    /// thirty seconds).
    public static let standard: [ZoomSnapThreshold] = [
        ZoomSnapThreshold(pixelsPerSecond: 30.0 / 30.0, label: "30s"),  // ~1 px / 30s
        ZoomSnapThreshold(pixelsPerSecond: 10.0,        label: "5s"),
        ZoomSnapThreshold(pixelsPerSecond: 50.0,        label: "1s"),
        ZoomSnapThreshold(pixelsPerSecond: 30.0 * 30.0, label: "1f"),   // 30fps frame width
    ]

    // MARK: - Crossing detection

    /// Returns the subset of `thresholds` that `[prev, current]` crosses,
    /// preserving the input order. A threshold *t* is considered crossed when
    /// it sits strictly between `prev` and `current` (either order). Endpoint
    /// equality doesn't count — the user has to *cross* the line, not land
    /// on it. No emission when `prev == current`.
    ///
    /// `nonisolated` so it's callable from any context — drives both the
    /// gesture-side emission and the unit tests.
    public nonisolated static func crossings(
        prev: Double,
        current: Double,
        in thresholds: [ZoomSnapThreshold] = standard
    ) -> [ZoomSnapThreshold] {
        guard prev != current else { return [] }
        let lo = min(prev, current)
        let hi = max(prev, current)
        return thresholds.filter { $0.pixelsPerSecond > lo && $0.pixelsPerSecond < hi }
    }
}
