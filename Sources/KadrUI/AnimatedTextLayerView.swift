import SwiftUI
import QuartzCore
import AVFoundation
import Kadr
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// SwiftUI bridge that hosts a `CATextLayer` and runs a ``Kadr/TextAnimation``'s
/// `[CAAnimation]` live so an animated `TextOverlay` previews the same way it exports.
///
/// Internal — used by ``OverlayHost`` when a ``Kadr/TextOverlay`` carries a
/// ``Kadr/TextOverlay/textAnimation``. The default SwiftUI `Text` rendering doesn't
/// surface a `CALayer` that `TextAnimation.makeAnimations(for:)` can target, so this
/// view wraps a platform `UIView` / `NSView` whose hosting layer is a `CATextLayer`.
///
/// **Begin-time remap.** Built-in recipes set `beginTime` to
/// `AVCoreAnimationBeginTimeAtZero` (export-pipeline convention for "composition t=0").
/// In a live `CALayer`, that value reads as "started long ago" and the animation
/// finishes immediately. The bridge shifts every animation's `beginTime` by
/// `CACurrentMediaTime() - AVCoreAnimationBeginTimeAtZero` so a fresh playthrough
/// starts now and any positive offset relative to t=0 is preserved.
struct AnimatedTextLayerView: View {

    let overlay: TextOverlay

    /// v0.11 — under Reduce Motion the text renders in its resting state without
    /// running the `TextAnimation`'s `CAAnimation`s.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Bridge(overlay: overlay, reduceMotion: reduceMotion)
    }

    // MARK: - Begin-time remap (pure)

    /// Map an `AVCoreAnimationBeginTimeAtZero`-anchored `beginTime` to a `CACurrentMediaTime`-anchored value.
    /// Pure helper exposed for testing.
    nonisolated static func remappedBeginTime(_ beginTime: CFTimeInterval, now: CFTimeInterval) -> CFTimeInterval {
        beginTime + (now - AVCoreAnimationBeginTimeAtZero)
    }

    // MARK: - Layer configuration (pure)

    /// Configure `layer` to match `overlay`'s text + style. Pure-ish: no animations are
    /// added here; only static layer properties. Exposed for testing.
    nonisolated static func configure(layer: CATextLayer, with overlay: TextOverlay) {
        let style = overlay.style
        layer.string = overlay.text
        layer.fontSize = CGFloat(style.fontSize)
        layer.font = ctFont(for: style)
        layer.foregroundColor = style.color.cgColor
        layer.alignmentMode = alignmentMode(for: style.alignment)
        layer.isWrapped = true
        layer.contentsScale = 2.0
        layer.opacity = Float(overlay.opacity)
    }

    /// The font kadr's export draws `style` with (kadr's `TextMetrics.font`): the
    /// named font, or the system font at the style's weight. A descriptor with only
    /// a trait, which this used before, matched no family and gave Helvetica Regular
    /// for every weight.
    nonisolated static func ctFont(for style: TextStyle) -> CTFont {
        let size = CGFloat(style.fontSize)
        if let name = style.fontName {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        guard let system = CTFontCreateUIFontForLanguage(.system, size, nil) else {
            return CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        let weight: CGFloat
        switch style.weight {
        case .regular: weight = 0.0    // kCTFontWeightRegular
        case .medium:  weight = 0.23   // kCTFontWeightMedium
        case .bold:    weight = 0.4    // kCTFontWeightBold
        }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(system), [
            kCTFontTraitsAttribute: [kCTFontWeightTrait: weight],
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    nonisolated private static func alignmentMode(for alignment: TextStyle.Alignment) -> CATextLayerAlignmentMode {
        switch alignment {
        case .leading:  return .left
        case .center:   return .center
        case .trailing: return .right
        }
    }

}

// MARK: - Platform bridge

#if canImport(UIKit)

private struct Bridge: UIViewRepresentable {
    let overlay: TextOverlay
    let reduceMotion: Bool

    func makeUIView(context: Context) -> AnimatedTextHostView {
        let view = AnimatedTextHostView()
        view.apply(overlay: overlay, reduceMotion: reduceMotion)
        return view
    }

    func updateUIView(_ uiView: AnimatedTextHostView, context: Context) {
        uiView.apply(overlay: overlay, reduceMotion: reduceMotion)
    }
}

final class AnimatedTextHostView: UIView {
    private let textLayer = CATextLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(textLayer)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        textLayer.frame = bounds
    }

    func apply(overlay: TextOverlay, reduceMotion: Bool) {
        AnimatedTextLayerView.configure(layer: textLayer, with: overlay)
        textLayer.removeAllAnimations()
        if !reduceMotion, let animation = overlay.textAnimation {
            let now = CACurrentMediaTime()
            for anim in animation.makeAnimations(for: textLayer) {
                anim.beginTime = AnimatedTextLayerView.remappedBeginTime(anim.beginTime, now: now)
                textLayer.add(anim, forKey: nil)
            }
        }
    }
}

#elseif canImport(AppKit)

private struct Bridge: NSViewRepresentable {
    let overlay: TextOverlay
    let reduceMotion: Bool

    func makeNSView(context: Context) -> AnimatedTextHostView {
        let view = AnimatedTextHostView()
        view.apply(overlay: overlay, reduceMotion: reduceMotion)
        return view
    }

    func updateNSView(_ nsView: AnimatedTextHostView, context: Context) {
        nsView.apply(overlay: overlay, reduceMotion: reduceMotion)
    }
}

final class AnimatedTextHostView: NSView {
    private let textLayer = CATextLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(textLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        textLayer.frame = bounds
    }

    func apply(overlay: TextOverlay, reduceMotion: Bool) {
        AnimatedTextLayerView.configure(layer: textLayer, with: overlay)
        textLayer.removeAllAnimations()
        if !reduceMotion, let animation = overlay.textAnimation {
            let now = CACurrentMediaTime()
            for anim in animation.makeAnimations(for: textLayer) {
                anim.beginTime = AnimatedTextLayerView.remappedBeginTime(anim.beginTime, now: now)
                textLayer.add(anim, forKey: nil)
            }
        }
    }
}

#endif
