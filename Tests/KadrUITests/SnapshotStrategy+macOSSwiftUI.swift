// v0.10.1 — Custom SwiftUI → NSImage snapshot helper for macOS.
//
// Background: swift-snapshot-testing 1.18 ships
// `Snapshotting<SwiftUI.View, UIImage>.image(layout:)` only for iOS / tvOS.
// macOS has no SwiftUI-View → image strategy out of the box. Our `swift test`
// workflow runs on macOS, so the iOS strategy is unavailable.
//
// Approach: skip the `Snapshotting<some View>` abstraction (which fights
// Swift 6 strict concurrency on the View → NSImage boundary) and use a
// straight `@MainActor` helper that renders the view to NSImage via
// `NSHostingController`. Tests then snapshot the resulting NSImage using
// the battle-tested `Snapshotting<NSImage, NSImage>.image` strategy.

#if os(macOS)
import AppKit
import SwiftUI

/// Render a SwiftUI view to an `NSImage` for use with swift-snapshot-testing's
/// `Snapshotting<NSImage, NSImage>.image` strategy.
///
/// Sized via the `size` parameter; pass `nil` to use `sizeThatFits` on the
/// hosting controller. Must be called from the main actor (NSHostingController
/// is a UIKit/AppKit thing).
@MainActor
func renderForSnapshot<V: View>(_ view: V, size: CGSize? = nil) -> NSImage {
    let controller = NSHostingController(rootView: view)
    let targetSize: NSSize
    if let size {
        targetSize = NSSize(width: size.width, height: size.height)
    } else {
        targetSize = controller.sizeThatFits(in: NSSize(width: 1000, height: 1000))
    }
    controller.view.frame = NSRect(origin: .zero, size: targetSize)
    controller.view.layoutSubtreeIfNeeded()

    // Render via the same bitmap-image-rep caching path that
    // `Snapshotting<NSView, NSImage>.image` uses internally.
    guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(
        in: controller.view.bounds
    ) else {
        // 1×1 placeholder if the renderer fails; snapshot diff will fail
        // loudly rather than silently passing.
        return NSImage(size: .zero)
    }
    controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
    let image = NSImage(size: controller.view.bounds.size)
    image.addRepresentation(bitmap)
    return image
}
#endif
