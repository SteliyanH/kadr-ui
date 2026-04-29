import Testing
import SwiftUI
import CoreMedia
import Foundation
import Kadr
@testable import KadrUI

/// Tests for `KeyframeEditor` — pure helpers (`propertyOptions`,
/// `keyframesForProperty`, `clipStartTime`) and smoke tests on the View body.
struct KeyframeEditorTests {

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func image(_ duration: Double, id: String? = nil) -> ImageClip {
        var clip = ImageClip(PlatformImage(), duration: duration)
        if let id { clip = clip.id(ClipID(id)) }
        return clip
    }

    // MARK: - propertyOptions

    @Test func propertyOptionsForImageClipEmitsTransformAndOpacity() {
        let clip: any Clip = image(1.0)
        let props = KeyframeEditor.propertyOptions(for: clip)
        #expect(props == [.transform, .opacity])
    }

    @Test func propertyOptionsForVideoClipWithoutFiltersOmitsFilterRows() {
        let clip: any Clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
        let props = KeyframeEditor.propertyOptions(for: clip)
        #expect(props == [.transform, .opacity])
    }

    @Test func propertyOptionsAddsAFilterRowPerScalarFilter() {
        let clip: any Clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .filter(.brightness(0.1), .contrast(1.2))
        let props = KeyframeEditor.propertyOptions(for: clip)
        #expect(props == [.transform, .opacity, .filter(index: 0), .filter(index: 1)])
    }

    @Test func propertyOptionsSkipsNonScalarFilters() {
        // .mono has no scalar parameter — should not produce a row.
        let clip: any Clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .filter(.brightness(0.1), .mono, .contrast(1.2))
        let props = KeyframeEditor.propertyOptions(for: clip)
        #expect(props == [.transform, .opacity, .filter(index: 0), .filter(index: 2)])
    }

    // MARK: - keyframesForProperty

    @Test func keyframesForTransformReturnsAnimationTimes() {
        let anim = Animation<Transform>.keyframes([
            .at(0.0, value: .identity),
            .at(2.0, value: .identity),
        ])
        let clip: any Clip = ImageClip(PlatformImage(), duration: 3.0)
            .transform(.identity, animation: anim)
        let times = KeyframeEditor.keyframesForProperty(.transform, on: clip)
        #expect(times.count == 2)
        #expect(CMTimeGetSeconds(times[0]) == 0.0)
        #expect(CMTimeGetSeconds(times[1]) == 2.0)
    }

    @Test func keyframesForOpacityReturnsAnimationTimes() {
        let anim = Animation<Double>.keyframes([
            .at(0.0, value: 0.0),
            .at(1.0, value: 1.0),
        ])
        let clip: any Clip = ImageClip(PlatformImage(), duration: 2.0)
            .opacity(0.0, animation: anim)
        let times = KeyframeEditor.keyframesForProperty(.opacity, on: clip)
        #expect(times.count == 2)
    }

    @Test func keyframesForFilterReturnsMatchingAnimationTimes() {
        let anim = Animation<Double>.keyframes([
            .at(0.0, value: 0.0),
            .at(1.5, value: 0.5),
        ])
        let clip: any Clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .filter(.brightness(0), animation: anim)
        let times = KeyframeEditor.keyframesForProperty(.filter(index: 0), on: clip)
        #expect(times.count == 2)
    }

    @Test func keyframesForMissingAnimationReturnsEmpty() {
        let clip: any Clip = image(1.0)
        #expect(KeyframeEditor.keyframesForProperty(.transform, on: clip).isEmpty)
        #expect(KeyframeEditor.keyframesForProperty(.opacity, on: clip).isEmpty)
        #expect(KeyframeEditor.keyframesForProperty(.filter(index: 0), on: clip).isEmpty)
    }

    @Test func keyframesForOutOfRangeFilterIndexReturnsEmpty() {
        let clip: any Clip = VideoClip(url: URL(fileURLWithPath: "/dev/null"))
            .filter(.brightness(0))
        let times = KeyframeEditor.keyframesForProperty(.filter(index: 99), on: clip)
        #expect(times.isEmpty)
    }

    // MARK: - clipStartTime

    @Test func clipStartTimeForFirstChainClipIsZero() {
        let video = Video {
            image(1.0, id: "a")
            image(2.0, id: "b")
        }
        let t = KeyframeEditor.clipStartTime(for: ClipID("a"), in: video)
        #expect(t == .zero)
    }

    @Test func clipStartTimeForLaterChainClipAccumulates() {
        let video = Video {
            image(1.0, id: "a")
            image(2.0, id: "b")
            image(3.0, id: "c")
        }
        let t = KeyframeEditor.clipStartTime(for: ClipID("c"), in: video)
        #expect(t.map { CMTimeGetSeconds($0) } == 3.0)
    }

    @Test func clipStartTimeForFreeFloaterReturnsPinnedTime() {
        let video = Video {
            image(2.0, id: "chain")
            image(1.0, id: "pip").at(time: 5.0)
        }
        let t = KeyframeEditor.clipStartTime(for: ClipID("pip"), in: video)
        #expect(t.map { CMTimeGetSeconds($0) } == 5.0)
    }

    @Test func clipStartTimeReturnsNilForUnknownID() {
        let video = Video {
            image(1.0, id: "a")
        }
        #expect(KeyframeEditor.clipStartTime(for: ClipID("missing"), in: video) == nil)
    }

    // MARK: - View body smoke tests

    @MainActor
    @Test func bodyRendersForSelectedClipWithAnimations() {
        let id = ClipID("a")
        let anim = Animation<Double>.keyframes([
            .at(0.0, value: 0.0),
            .at(1.0, value: 1.0),
        ])
        let video = Video {
            ImageClip(PlatformImage(), duration: 2.0).id(id).opacity(0.0, animation: anim)
        }
        let editor = KeyframeEditor(
            video,
            selectedClipID: .constant(id),
            currentTime: .constant(.zero)
        )
        _ = editor.body
    }

    @MainActor
    @Test func bodyRendersPlaceholderWithoutSelection() {
        let video = Video { image(1.0, id: "a") }
        let editor = KeyframeEditor(
            video,
            selectedClipID: .constant(nil),
            currentTime: .constant(.zero)
        )
        _ = editor.body
    }
}
