import SwiftUI
import Kadr
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Cross-platform SwiftUI bridges for Kadr's `PlatformImage` (UIImage / NSImage) and
// `PlatformColor` (UIColor / NSColor). Internal — these are package-internal helpers,
// not part of the public API.

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension Color {
    init(platformColor: PlatformColor) {
        #if canImport(UIKit)
        self.init(uiColor: platformColor)
        #elseif canImport(AppKit)
        self.init(nsColor: platformColor)
        #endif
    }
}
