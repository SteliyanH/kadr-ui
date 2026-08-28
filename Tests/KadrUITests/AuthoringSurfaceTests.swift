import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Tests for the v0.19 authoring surface — filter add/remove/reorder on
/// `InspectorPanel`, and `TransitionPicker`.
struct AuthoringSurfaceTests {

    // MARK: - Filter labels come from kadr, not from a second list

    @Test("Filter labels delegate to the upstream catalogue")
    func labelsComeFromFilterKind() {
        // Before v0.19 KadrUI kept its own switch over every Filter case, which
        // is one more place a new filter can be missed. Now there is one list.
        for kind in FilterKind.allCases {
            guard let filter = kind.defaultFilter else { continue }
            #expect(InspectorPanel.label(for: filter) == kind.displayName)
        }
    }

    @Test("Every insertable kind produces a filter the panel can label")
    func everyInsertableKindIsRenderable() {
        for kind in FilterKind.insertable {
            guard let filter = kind.defaultFilter else { continue }
            #expect(!InspectorPanel.label(for: filter).isEmpty)
        }
    }

    @Test("The panel offers a slider exactly for the kinds that have an intensity")
    func sliderAvailabilityMatchesTheCatalogue() {
        for kind in FilterKind.allCases {
            guard let filter = kind.defaultFilter else { continue }
            let hasSlider = InspectorPanel.scalar(of: filter) != nil
                && InspectorPanel.range(of: filter) != nil
            #expect(hasSlider == kind.hasIntensity,
                    "\(kind): catalogue says hasIntensity=\(kind.hasIntensity), panel says \(hasSlider)")
        }
    }

    // MARK: - Callback wiring

    @MainActor
    @Test("The panel builds with the authoring callbacks attached")
    func panelAcceptsAuthoringCallbacks() {
        let video = Video {
            VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov")).trimmed(to: 0...5).id(ClipID("a"))
                .filter(.sepia(intensity: 0.4))
                .filter(.mono)
        }
        let selected: Binding<ClipID?> = .constant(ClipID("a"))
        let panel = InspectorPanel(
            video,
            selectedClipID: selected,
            onFilterAdd: { _, _ in },
            onFilterRemove: { _, _ in },
            onFilterMove: { _, _, _ in }
        )
        _ = panel.body  // Should not crash.
    }

    @MainActor
    @Test("The panel still builds with no callbacks — authoring is opt-in")
    func authoringIsOptional() {
        let video = Video { ImageClip(PlatformImage(), duration: 1.0).id(ClipID("a")) }
        let selected: Binding<ClipID?> = .constant(ClipID("a"))
        let panel = InspectorPanel(video, selectedClipID: selected)
        _ = panel.body  // Should not crash.
    }

    // MARK: - TransitionKind

    @Test("Every transition kind round-trips through its own value")
    func transitionKindsRoundTrip() {
        let duration = CMTime(seconds: 0.5, preferredTimescale: 600)
        for kind in TransitionKind.allCases {
            let transition = kind.transition(duration: duration)
            #expect(TransitionKind.kind(of: transition) == kind)
            #expect(transition.duration == duration)
        }
    }

    @Test("Only slide needs a direction, and slide keeps the one it was given")
    func slideKeepsItsDirection() {
        #expect(TransitionKind.slide.needsDirection)
        #expect(!TransitionKind.fade.needsDirection)
        #expect(!TransitionKind.dissolve.needsDirection)

        for option in SlideDirectionOption.allCases {
            let transition = TransitionKind.slide.transition(
                duration: CMTime(seconds: 1, preferredTimescale: 600),
                direction: option.direction
            )
            #expect(TransitionPicker.direction(of: transition).map(SlideDirectionOption.init) == option)
        }
    }

    @Test("A non-slide transition reports no direction")
    func nonSlideHasNoDirection() {
        let fade = TransitionKind.fade.transition(duration: CMTime(seconds: 1, preferredTimescale: 600))
        #expect(TransitionPicker.direction(of: fade) == nil)
        #expect(TransitionPicker.direction(of: nil) == nil)
    }

    @Test("Every kind and direction has a distinct, non-empty display name")
    func displayNamesAreUsable() {
        let kindNames = TransitionKind.allCases.map(\.displayName)
        #expect(Set(kindNames).count == kindNames.count)
        #expect(kindNames.allSatisfy { !$0.isEmpty })

        let directionNames = SlideDirectionOption.allCases.map(\.displayName)
        #expect(Set(directionNames).count == directionNames.count)
        #expect(directionNames.allSatisfy { !$0.isEmpty })
    }

    @Test("SlideDirectionOption maps both ways without loss")
    func directionMirrorIsFaithful() {
        for option in SlideDirectionOption.allCases {
            #expect(SlideDirectionOption(option.direction) == option)
        }
    }

    @MainActor
    @Test("The picker builds, seeded from an existing transition")
    func pickerSeedsFromExisting() {
        let existing = Kadr.Transition.slide(
            direction: .fromBottom,
            duration: CMTime(seconds: 1.25, preferredTimescale: 600)
        )
        let picker = TransitionPicker(initial: existing) { _ in }
        _ = picker.body  // Should not crash.
    }

    @MainActor
    @Test("The picker builds with no seed")
    func pickerBuildsEmpty() {
        _ = TransitionPicker { _ in }.body  // Should not crash.
    }
}
