import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Tests for v0.10.0 Tier 1 — `Sendable` callback event structs.
///
/// Pre-v0.10 `TimelineView`'s reorder / trim callbacks took positional
/// closures `(Int, Int, [any Clip])` / `(Int, Int, Int, [any Clip])` /
/// `(Int, CMTime, CMTime)` / `(Int, Int, CMTime, CMTime)` — every same-
/// type-positional pair was a swap landmine the type system couldn't
/// catch. v0.10.0 names every field with a `*Event` struct payload.
struct CallbackEventStructsTests {

    private func sampleVideo() -> Video {
        let img = PlatformImage()
        return Video {
            ImageClip(img, duration: 2.0)
            ImageClip(img, duration: 3.0)
        }
    }

    // MARK: - Event-struct round-trip

    @Test func clipReorderEventCarriesFromToAndNewClips() {
        let img = PlatformImage()
        let event = ClipReorderEvent(
            from: 0,
            to: 2,
            newClips: [ImageClip(img, duration: 1.0), ImageClip(img, duration: 2.0)]
        )
        #expect(event.from == 0)
        #expect(event.to == 2)
        #expect(event.newClips.count == 2)
    }

    @Test func clipTrimEventCarriesIndexAndDeltas() {
        let event = ClipTrimEvent(
            clipIndex: 1,
            leadingTrim: CMTime(seconds: 0.5, preferredTimescale: 600),
            trailingTrim: CMTime(seconds: -0.25, preferredTimescale: 600)
        )
        #expect(event.clipIndex == 1)
        #expect(event.leadingTrim.seconds == 0.5)
        #expect(event.trailingTrim.seconds == -0.25)
    }

    @Test func trackReorderEventCarriesTrackQualifier() {
        let img = PlatformImage()
        let event = TrackReorderEvent(
            trackIndex: 1,
            from: 0,
            to: 2,
            newClips: [ImageClip(img, duration: 1.0)]
        )
        #expect(event.trackIndex == 1)
        #expect(event.from == 0)
        #expect(event.to == 2)
    }

    @Test func trackTrimEventCarriesTrackQualifier() {
        let event = TrackTrimEvent(
            trackIndex: 2,
            clipIndex: 0,
            leadingTrim: .zero,
            trailingTrim: CMTime(seconds: 1.0, preferredTimescale: 600)
        )
        #expect(event.trackIndex == 2)
        #expect(event.clipIndex == 0)
        #expect(event.trailingTrim.seconds == 1.0)
    }

    // MARK: - Sendable conformance

    /// Every event struct is `Sendable` so it can cross actor boundaries
    /// inside the consumer's mutation pipeline.
    @Test func eventsAreSendable() async {
        let img = PlatformImage()
        let event = ClipReorderEvent(from: 0, to: 1, newClips: [ImageClip(img, duration: 1.0)])
        async let mirrored: Int = {
            return event.from
        }()
        let result = await mirrored
        #expect(result == 0)
    }

    // MARK: - TimelineView init dispatch

    @Test @MainActor func newInitDispatchesEventStructs() {
        var capturedFrom: Int?
        var capturedTo: Int?
        let view = TimelineView(
            sampleVideo(),
            onReorder: { event in
                capturedFrom = event.from
                capturedTo = event.to
            }
        )
        _ = view.body
        // The closure is stored but only fires from gesture code. The
        // smoke is that the new init compiled + body constructs.
        #expect(capturedFrom == nil)
        #expect(capturedTo == nil)
    }

    @Test @MainActor func newInitAcceptsAllFourEventCallbacks() {
        _ = TimelineView(
            sampleVideo(),
            onReorder: { _ in },
            onTrim: { _ in },
            onTrackReorder: { _ in },
            onTrackTrim: { _ in }
        ).body
    }

    @Test @MainActor func newInitWithNoCallbacksConstructs() {
        // Disambiguation: this call site has no callbacks. The deprecated
        // positional-arg init has a non-default-nil `onReorder` parameter,
        // so the new event-struct init is the only match.
        _ = TimelineView(sampleVideo()).body
    }

    // MARK: - Deprecated init still compiles + dispatches

    /// The deprecated positional-arg init wraps each closure into an
    /// event-emitting one. v0.5 consumers' call sites compile unchanged
    /// (with a deprecation warning), and internal state stores the
    /// wrapped event closures.
    @Test @MainActor func deprecatedInitWrapsPositionalClosuresIntoEventClosures() {
        // Calling the deprecated init produces a warning but compiles.
        // We can't observe the wrapping directly, but we verify body
        // construction succeeds — same surface as the new init from the
        // consumer's perspective.
        _ = TimelineView(
            sampleVideo(),
            onReorder: { (from: Int, to: Int, _) in
                // Old shape — receives positional args. The wrapper
                // hands these out from the event the gesture emits.
                _ = (from, to)
            }
        ).body
    }
}
