import Testing
import SwiftUI
@testable import KadrUI

/// v0.13 — contract tests for ``KadrAppearance``.
///
/// The load-bearing claim of this feature is that **defaults reproduce the
/// pre-0.13 rendering verbatim**, so existing consumers see no change. The
/// package's snapshot baselines are the visual proof — they were not
/// re-recorded when the appearance surface landed. These tests are the
/// numeric proof, and they exist so a later "tidy-up" of the defaults fails
/// loudly instead of silently restyling every consumer.
struct KadrAppearanceTests {

    // MARK: - Defaults are the pre-0.13 values

    @Test func geometryDefaultsMatchPre013() {
        let a = KadrAppearance.system
        #expect(a.cornerRadius == 4)
        #expect(a.laneCornerRadius == 2)
        #expect(a.strokeWidth == 2)
        #expect(a.elevation == 6)
    }

    @Test func colourDefaultsMatchPre013() {
        let a = KadrAppearance.system
        #expect(a.playhead == .red)
        #expect(a.selectionRing == .white)
        #expect(a.keyframeMark == .white)
        #expect(a.trackBackground == .gray.opacity(0.2))
        #expect(a.laneBackground == .gray.opacity(0.08))
        #expect(a.placeholder == .gray.opacity(0.2))
        #expect(a.waveform == .purple)
        #expect(a.trackPlayhead == .white.opacity(0.4))
    }

    @Test func renderingAndShapeDefaultToThePre013Behaviour() {
        #expect(KadrAppearance.system.clipContentRendering == .color)
        #expect(KadrAppearance.system.keyframeMarkShape == .circle)
    }

    @Test func overlayLaneFillDefaultsToNilSoLanesTintByKind() {
        // nil is not "no colour" — it means "keep tinting each cell by its
        // kind", which is what the timeline did before this type existed.
        #expect(KadrAppearance.system.overlayLaneFill == nil)
    }

    @Test func clipColourDefaultsMatchPre013() {
        let c = KadrAppearance.ClipColors.system
        #expect(c.video == .blue)
        #expect(c.image == .green)
        #expect(c.title == .orange)
        #expect(c.transition == .gray)
        #expect(c.audio == .purple)
    }

    // MARK: - Environment

    @Test func environmentDefaultsToSystem() {
        #expect(EnvironmentValues().kadrAppearance == .system)
    }

    @Test func environmentCarriesACustomAppearance() {
        var env = EnvironmentValues()
        var custom = KadrAppearance.system
        custom.cornerRadius = 0
        custom.playhead = .white
        env.kadrAppearance = custom

        #expect(env.kadrAppearance.cornerRadius == 0)
        #expect(env.kadrAppearance.playhead == .white)
        #expect(env.kadrAppearance != .system)
    }

    // MARK: - ClipColors

    @Test func uniformSetsEveryKindToOneColour() {
        let c = KadrAppearance.ClipColors.uniform(.black)
        #expect(c.video == .black)
        #expect(c.image == .black)
        #expect(c.title == .black)
        #expect(c.transition == .black)
        #expect(c.audio == .black)
    }

    @Test func colourForKindReadsTheMatchingField() {
        var appearance = KadrAppearance.system
        appearance.clipColors = KadrAppearance.ClipColors(
            video: .red,
            image: .green,
            title: .blue,
            transition: .yellow,
            audio: .pink
        )

        #expect(appearance.color(for: .video) == .red)
        #expect(appearance.color(for: .image) == .green)
        #expect(appearance.color(for: .title) == .blue)
        #expect(appearance.color(for: .transition) == .yellow)
        #expect(appearance.color(for: .audio) == .pink)
    }

    // MARK: - The consuming case

    @Test func aMonoSquareAppearanceIsExpressible() {
        // What a mono design system actually configures — the case this whole
        // feature exists to serve. If any of these stop being reachable, the
        // API has regressed regardless of what the defaults still do.
        var appearance = KadrAppearance.system
        appearance.cornerRadius = 0
        appearance.laneCornerRadius = 0
        appearance.elevation = 0
        appearance.playhead = .white
        appearance.trackPlayhead = .white
        appearance.clipColors = .uniform(.gray)
        appearance.clipContentRendering = .grayscale
        appearance.keyframeMarkShape = .diamond
        appearance.keyframeMark = .orange
        appearance.overlayLaneFill = .orange.opacity(0.18)

        #expect(appearance.cornerRadius == 0)
        #expect(appearance.elevation == 0)
        #expect(appearance.clipContentRendering == .grayscale)
        #expect(appearance.keyframeMarkShape == .diamond)
        #expect(appearance.overlayLaneFill != nil)
        #expect(appearance != .system)
    }

    @Test @MainActor func keyframeMarkBuildsInBothShapes() {
        _ = KeyframeMark(shape: .circle, color: .white, size: 10).body
        _ = KeyframeMark(shape: .diamond, color: .orange, size: 10).body
    }
}
