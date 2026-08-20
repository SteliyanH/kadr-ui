import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Two things a host could not reach: where the content has scrolled to, and
/// what a clip is called.
struct TimelineScrollAndClipA11yTests {

    private func video(clips: Int) -> Video {
        let img = PlatformImage()
        return Video {
            for _ in 0..<clips { ImageClip(img, duration: 2.0) }
        }
    }

    // MARK: - Spoken labels

    @Test func defaultLabelNamesPositionKindAndDuration() {
        let label = TimelineView.defaultClipAccessibilityLabel(
            index: 0, total: 4, kind: "Clip", seconds: 2.4
        )
        #expect(label == "Clip 1 of 4, 2.4 seconds")
    }

    @Test func positionIsOneBasedBecauseItIsSpokenAloud() {
        let label = TimelineView.defaultClipAccessibilityLabel(
            index: 2, total: 3, kind: "Image", seconds: 1.0
        )
        #expect(label.contains("3 of 3"), "A screen reader saying 'clip 2 of 3' for the last clip would be wrong.")
    }

    @Test func negativeDurationsDoNotLeakIntoSpeech() {
        let label = TimelineView.defaultClipAccessibilityLabel(
            index: 0, total: 1, kind: "Clip", seconds: -3
        )
        #expect(label.contains("0.0 seconds"))
        #expect(!label.contains("-"))
    }

    @Test @MainActor func kindIsDistinguishedPerClipType() {
        let img = PlatformImage()
        #expect(TimelineView.describeKind(ImageClip(img, duration: 1)) == "Image")
    }

    @Test @MainActor func hostSuppliedLabelWins() {
        let view = TimelineView(
            video(clips: 2),
            clipAccessibilityLabel: { index, _ in "shot \(index)" }
        )
        #expect(view.accessibilityLabel(forClipAt: 1) == "shot 1")
    }

    @Test @MainActor func defaultLabelIsUsedWhenNoneSupplied() {
        let view = TimelineView(video(clips: 2))
        let label = view.accessibilityLabel(forClipAt: 0)
        #expect(label.contains("1 of 2"))
        #expect(label.contains("seconds"))
    }

    @Test @MainActor func labellingIsSafeAtTheEdgeOfTheClipList() {
        // Indices can momentarily outrun the model during an edit; speech must
        // not be the thing that crashes.
        let view = TimelineView(video(clips: 1))
        _ = view.accessibilityLabel(forClipAt: 99)
    }

    // MARK: - Scroll offset

    @Test @MainActor func scrollOffsetCallbackIsOptional() {
        _ = TimelineView(video(clips: 2))
    }

    @Test @MainActor func scrollOffsetCallbackIsAccepted() {
        var seen: CGFloat?
        _ = TimelineView(video(clips: 2), onScrollOffsetChange: { seen = $0 })
        #expect(seen == nil, "Nothing has scrolled yet; the callback fires from layout, not construction.")
    }
}
