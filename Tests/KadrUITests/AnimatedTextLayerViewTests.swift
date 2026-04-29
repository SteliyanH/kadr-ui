import Testing
import QuartzCore
import AVFoundation
import Foundation
import SwiftUI
import Kadr
@testable import KadrUI

/// Tests for `AnimatedTextLayerView` — pure helpers (begin-time remap, layer
/// configuration) and smoke tests via OverlayHost.
struct AnimatedTextLayerViewTests {

    // MARK: - Begin-time remap

    @Test func remapShiftsAVCoreAnimationBeginTimeAtZeroToNow() {
        let now: CFTimeInterval = 100.0
        let mapped = AnimatedTextLayerView.remappedBeginTime(AVCoreAnimationBeginTimeAtZero, now: now)
        #expect(abs(mapped - now) < 0.0001)
    }

    @Test func remapPreservesPositiveOffsetsRelativeToZero() {
        let now: CFTimeInterval = 100.0
        let begin = AVCoreAnimationBeginTimeAtZero + 2.5
        let mapped = AnimatedTextLayerView.remappedBeginTime(begin, now: now)
        #expect(abs(mapped - (now + 2.5)) < 0.0001)
    }

    // MARK: - Layer configuration

    @Test func configureSetsTextAndStyleOnLayer() {
        let layer = CATextLayer()
        let overlay = TextOverlay("Hello", style: TextStyle(fontSize: 32))
        AnimatedTextLayerView.configure(layer: layer, with: overlay)
        #expect(layer.string as? String == "Hello")
        #expect(layer.fontSize == 32)
    }

    @Test func configurePicksAlignmentMode() {
        let layer = CATextLayer()
        let overlay = TextOverlay(
            "X",
            style: TextStyle(fontSize: 20, alignment: .trailing)
        )
        AnimatedTextLayerView.configure(layer: layer, with: overlay)
        #expect(layer.alignmentMode == .right)
    }

    @Test func configureCopiesOpacity() {
        let layer = CATextLayer()
        let overlay = TextOverlay("X").opacity(0.5)
        AnimatedTextLayerView.configure(layer: layer, with: overlay)
        #expect(abs(layer.opacity - 0.5) < 0.0001)
    }

    // MARK: - OverlayHost integration smoke

    @MainActor
    @Test func overlayHostRendersTextOverlayWithAnimation() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        .overlay(TextOverlay("Reveal").animation(.fadeIn(duration: 1.0)))
        let host = OverlayHost(video)
        _ = host.body
    }

    @MainActor
    @Test func overlayHostRendersTextOverlayWithoutAnimationViaTextPath() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 1.0)
        }
        .overlay(TextOverlay("Static"))
        let host = OverlayHost(video)
        _ = host.body
    }
}
