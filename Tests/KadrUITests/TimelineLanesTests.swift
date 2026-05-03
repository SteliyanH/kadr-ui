import Testing
import CoreMedia
import Foundation
import Kadr
@testable import KadrUI

/// Pure unit tests for `assignLanes` and `packFreeFloaters`. No SwiftUI involvement.
/// Each case constructs a `Video` (real Kadr DSL), calls the helper, and asserts on
/// the returned lane structure. Helpers are package-internal — this file imports
/// `@testable`.
struct TimelineLanesTests {

    // MARK: - Fixtures

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func image(_ duration: Double, id: String? = nil) -> ImageClip {
        var clip = ImageClip(PlatformImage(), duration: duration)
        if let id { clip = clip.id(ClipID(id)) }
        return clip
    }

    // MARK: - assignLanes — basic shapes

    @Test func emptyVideoEmitsOnlyImplicitChainLane() {
        let video = Video {
            ImageClip(PlatformImage(), duration: 0.0)  // builder requires at least one clip
        }
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        #expect(lanes.count == 1)
        #expect(lanes[0].0 == .implicitChain)
    }

    @Test func chainOnlyVideoEmitsSingleLane() {
        let video = Video {
            image(1.0, id: "a")
            image(2.0, id: "b")
            image(3.0, id: "c")
        }
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        #expect(lanes.count == 1)
        guard case .implicitChain = lanes[0].0 else {
            Issue.record("expected implicitChain")
            return
        }
        let items = lanes[0].1
        #expect(items.count == 3)
        #expect(items[0].clipID == ClipID("a"))
        #expect(items[0].startTime == .zero)
        #expect(items[1].startTime == cmt(1.0))
        #expect(items[2].startTime == cmt(3.0))
    }

    @Test func videoWithSingleTrackAddsOneTrackLane() {
        let video = Video {
            image(5.0, id: "main")
            Track(at: 1.0) {
                image(2.0, id: "t1a")
                image(2.0, id: "t1b")
            }
        }
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        #expect(lanes.count == 2)
        guard case .implicitChain = lanes[0].0,
              case let .track(idx, start, _) = lanes[1].0 else {
            Issue.record("expected implicitChain then track")
            return
        }
        #expect(idx == 0)
        #expect(start == cmt(1.0))
        let trackItems = lanes[1].1
        #expect(trackItems.count == 2)
        #expect(trackItems[0].startTime == cmt(1.0))
        #expect(trackItems[1].startTime == cmt(3.0))
    }

    @Test func multipleTracksGetSequentialIndices() {
        let video = Video {
            image(10.0, id: "main")
            Track(at: 1.0) { image(2.0, id: "ta") }
            Track(at: 5.0) { image(2.0, id: "tb") }
        }
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        #expect(lanes.count == 3)
        if case let .track(i0, _, _) = lanes[1].0 { #expect(i0 == 0) } else { Issue.record("lane 1 not track") }
        if case let .track(i1, _, _) = lanes[2].0 { #expect(i1 == 1) } else { Issue.record("lane 2 not track") }
    }

    @Test func freeFloatersPackOntoOneLaneWhenNonOverlapping() {
        let video = Video {
            image(10.0, id: "main")
            image(2.0, id: "f1").at(time: 1.0)
            image(2.0, id: "f2").at(time: 4.0)
        }
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        #expect(lanes.count == 2)  // chain + 1 floater row
        guard case .freeFloaters(let pack) = lanes[1].0 else {
            Issue.record("expected freeFloaters lane")
            return
        }
        #expect(pack == 0)
        #expect(lanes[1].1.count == 2)
    }

    @Test func freeFloatersSplitWhenOverlapping() {
        let video = Video {
            image(10.0, id: "main")
            image(3.0, id: "f1").at(time: 1.0)  // 1.0…4.0
            image(3.0, id: "f2").at(time: 2.0)  // 2.0…5.0  — overlaps f1
        }
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        #expect(lanes.count == 3)  // chain + 2 floater rows
        guard case .freeFloaters(let p1) = lanes[1].0,
              case .freeFloaters(let p2) = lanes[2].0 else {
            Issue.record("expected two freeFloaters lanes")
            return
        }
        #expect(p1 == 0)
        #expect(p2 == 1)
    }

    @Test func mixedShapesProduceExpectedLaneOrder() {
        let video = Video {
            image(20.0, id: "main")
            image(2.0, id: "f1").at(time: 1.0)
            Track(at: 5.0) { image(2.0, id: "ta") }
            image(2.0, id: "f2").at(time: 10.0)
        }
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        // Order spec: chain → tracks → floaters → audio.
        #expect(lanes.count == 3)
        guard case .implicitChain = lanes[0].0,
              case .track = lanes[1].0,
              case .freeFloaters = lanes[2].0 else {
            Issue.record("expected chain, track, floaters in that order")
            return
        }
        #expect(lanes[2].1.count == 2)  // both floaters non-overlapping → one row
    }

    @Test func includeAudioAddsAudioLanesAtEnd() {
        let musicURL = URL(fileURLWithPath: "/tmp/music.mp3")
        let video = Video {
            image(10.0, id: "main")
        }
        .audio { AudioTrack(url: musicURL) }

        let withAudio = TimelineView.assignLanes(for: video, includeAudio: true)
        let withoutAudio = TimelineView.assignLanes(for: video, includeAudio: false)
        #expect(withAudio.count == withoutAudio.count + 1)
        guard case let .audio(idx, label) = withAudio.last!.0 else {
            Issue.record("expected last lane to be audio")
            return
        }
        #expect(idx == 0)
        #expect(label == "music.mp3")
    }

    // MARK: - kadr 0.7 surface (v0.5.2)

    @Test func trackNameSurfacesInLaneLabel() {
        let video = Video {
            image(10.0, id: "main")
            Track(at: 1.0, name: "B-Roll") {
                image(2.0, id: "ta")
            }
        }
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        guard case let .track(_, _, label) = lanes[1].0 else {
            Issue.record("expected track lane at index 1")
            return
        }
        #expect(label == "B-Roll")
    }

    @Test func unnamedTrackProducesNilLabel() {
        let video = Video {
            image(10.0, id: "main")
            Track(at: 1.0) { image(2.0, id: "ta") }
        }
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        guard case let .track(_, _, label) = lanes[1].0 else {
            Issue.record("expected track lane at index 1")
            return
        }
        #expect(label == nil)
    }

    @Test func audioLaneRespectsExplicitStartAndDuration() {
        let url = URL(fileURLWithPath: "/tmp/sfx.m4a")
        let video = Video {
            image(10.0, id: "main")
        }
        .audio { AudioTrack(url: url).at(time: 2.0).duration(1.5) }

        let lanes = TimelineView.assignLanes(for: video, includeAudio: true)
        let audioLane = try? #require(lanes.last)
        let item = try? #require(audioLane?.1.first)
        #expect(CMTimeGetSeconds(item!.startTime) == 2.0)
        #expect(CMTimeGetSeconds(item!.duration) == 1.5)
    }

    @Test func audioLaneCapsExplicitDurationToCompositionEnd() {
        // Composition is 10s, audio pinned to t=8s with .duration(5.0) — only 2s
        // of the cap is reachable before the composition ends.
        let url = URL(fileURLWithPath: "/tmp/sfx.m4a")
        let video = Video {
            image(10.0, id: "main")
        }
        .audio { AudioTrack(url: url).at(time: 8.0).duration(5.0) }

        let lanes = TimelineView.assignLanes(for: video, includeAudio: true)
        let item = try? #require(lanes.last?.1.first)
        #expect(CMTimeGetSeconds(item!.startTime) == 8.0)
        #expect(CMTimeGetSeconds(item!.duration) == 2.0)
    }

    @Test func audioLaneStartingPastCompositionEndIsZeroDuration() {
        let url = URL(fileURLWithPath: "/tmp/sfx.m4a")
        let video = Video {
            image(5.0, id: "main")
        }
        .audio { AudioTrack(url: url).at(time: 10.0) }

        let lanes = TimelineView.assignLanes(for: video, includeAudio: true)
        let item = try? #require(lanes.last?.1.first)
        // Engine would skip this track at export; the lane still surfaces it for
        // introspection consumers, with duration clamped to zero.
        #expect(CMTimeGetSeconds(item!.duration) == 0)
    }

    @Test func audioLaneWithoutExplicitTimingDefaultsToFullComposition() {
        let url = URL(fileURLWithPath: "/tmp/music.m4a")
        let video = Video {
            image(8.0, id: "main")
        }
        .audio(url: url)

        let lanes = TimelineView.assignLanes(for: video, includeAudio: true)
        let item = try? #require(lanes.last?.1.first)
        #expect(CMTimeGetSeconds(item!.startTime) == 0)
        #expect(CMTimeGetSeconds(item!.duration) == 8.0)
    }

    @Test func transitionsStayInChainAndDoNotAdvanceCursor() {
        let video = Video {
            image(2.0, id: "a")
            Transition.fade(duration: 0.5)
            image(2.0, id: "b")
        }
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        let items = lanes[0].1
        #expect(items.count == 3)
        #expect(items[0].startTime == .zero)
        #expect(items[1].kind == .transition)
        // Transition does NOT advance the cursor — clip "b" starts at 2.0 (after "a").
        #expect(items[2].startTime == cmt(2.0))
    }

    // MARK: - packFreeFloaters — focused unit tests

    @Test func packEmptyReturnsEmpty() {
        #expect(TimelineView.packFreeFloaters([]).isEmpty)
    }

    @Test func packSingleFloaterReturnsOneRow() {
        let item = LaneItem(clipID: nil, startTime: cmt(1), duration: cmt(2), kind: .video)
        let rows = TimelineView.packFreeFloaters([item])
        #expect(rows.count == 1)
        #expect(rows[0].count == 1)
    }

    @Test func packTwoNonOverlappingPlacesOnSameRow() {
        let a = LaneItem(clipID: nil, startTime: cmt(0), duration: cmt(2), kind: .video)
        let b = LaneItem(clipID: nil, startTime: cmt(2), duration: cmt(2), kind: .video)
        let rows = TimelineView.packFreeFloaters([a, b])
        #expect(rows.count == 1)
        #expect(rows[0].count == 2)
    }

    @Test func packTwoOverlappingSplitsToTwoRows() {
        let a = LaneItem(clipID: nil, startTime: cmt(0), duration: cmt(3), kind: .video)
        let b = LaneItem(clipID: nil, startTime: cmt(1), duration: cmt(2), kind: .video)
        let rows = TimelineView.packFreeFloaters([a, b])
        #expect(rows.count == 2)
        #expect(rows[0].count == 1)
        #expect(rows[1].count == 1)
    }

    @Test func packEdgeTouchingPlacesOnSameRow() {
        // a ends at exactly 2.0; b starts at exactly 2.0 — counted as non-overlapping.
        let a = LaneItem(clipID: nil, startTime: cmt(0), duration: cmt(2), kind: .video)
        let b = LaneItem(clipID: nil, startTime: cmt(2), duration: cmt(1), kind: .video)
        let rows = TimelineView.packFreeFloaters([a, b])
        #expect(rows.count == 1)
    }

    @Test func packMixedThreeFloatersPacksGreedily() {
        // a: 0…3, b: 1…2, c: 3…5
        // Greedy: a → row 0; b overlaps a → row 1; c starts at 3, row 0 ended at 3 → row 0.
        let a = LaneItem(clipID: nil, startTime: cmt(0), duration: cmt(3), kind: .video)
        let b = LaneItem(clipID: nil, startTime: cmt(1), duration: cmt(1), kind: .video)
        let c = LaneItem(clipID: nil, startTime: cmt(3), duration: cmt(2), kind: .video)
        let rows = TimelineView.packFreeFloaters([a, b, c])
        #expect(rows.count == 2)
        #expect(rows[0].count == 2)  // a, c
        #expect(rows[1].count == 1)  // b
    }

    @Test func packUnsortedInputProducesSameResult() {
        let a = LaneItem(clipID: nil, startTime: cmt(3), duration: cmt(2), kind: .video)
        let b = LaneItem(clipID: nil, startTime: cmt(0), duration: cmt(2), kind: .video)
        let rows = TimelineView.packFreeFloaters([a, b])
        #expect(rows.count == 1)  // sorted: 0…2 then 3…5 — non-overlapping
        #expect(rows[0].count == 2)
        // First placed should be the earliest (b), then a.
        #expect(rows[0][0].startTime == .zero)
        #expect(rows[0][1].startTime == cmt(3))
    }

    // MARK: - Integration on a v0.6-shaped Video

    // MARK: - laneLabel

    @Test func implicitChainLaneHasNoLabel() {
        #expect(TimelineView.laneLabel(for: .implicitChain) == nil)
    }

    @Test func trackLaneLabelDefaultsToIndexed() {
        let label = TimelineView.laneLabel(for: .track(index: 0, startTime: cmt(1), label: nil))
        #expect(label == "Track 1")
    }

    @Test func trackLaneLabelHonorsExplicit() {
        let label = TimelineView.laneLabel(for: .track(index: 1, startTime: cmt(1), label: "B-Roll"))
        #expect(label == "B-Roll")
    }

    @Test func freeFloaterLaneLabel() {
        #expect(TimelineView.laneLabel(for: .freeFloaters(packIndex: 0)) == "Floaters")
        #expect(TimelineView.laneLabel(for: .freeFloaters(packIndex: 2)) == "Floaters 3")
    }

    @Test func audioLaneLabelDefaultsToIndexedAndHonorsExplicit() {
        #expect(TimelineView.laneLabel(for: .audio(index: 0, label: nil)) == "Audio 1")
        #expect(TimelineView.laneLabel(for: .audio(index: 0, label: "music.mp3")) == "music.mp3")
    }

    // MARK: - chainIndices (v0.5.1)

    @Test func chainIndicesForChainOnlyReturnsAllIndices() {
        let img = PlatformImage()
        let clips: [any Clip] = [
            ImageClip(img, duration: 1.0),
            Kadr.Transition.fade(duration: 0.3),
            ImageClip(img, duration: 2.0),
        ]
        #expect(TimelineView.chainIndices(in: clips) == [0, 1, 2])
    }

    @Test func chainIndicesSkipsTracksAndFloaters() {
        let img = PlatformImage()
        let clips: [any Clip] = [
            ImageClip(img, duration: 1.0),                       // 0 — chain
            Track(at: 0.5) { ImageClip(img, duration: 1.0) },    // 1 — Track
            ImageClip(img, duration: 2.0),                       // 2 — chain
            ImageClip(img, duration: 1.0).at(time: 3.0),         // 3 — floater
            ImageClip(img, duration: 1.0),                       // 4 — chain
        ]
        #expect(TimelineView.chainIndices(in: clips) == [0, 2, 4])
    }

    // MARK: - applyChainReorder (v0.5.1)

    @Test func applyChainReorderInChainOnlyMatchesPlainReorder() {
        let img = PlatformImage()
        let clips: [any Clip] = [
            ImageClip(img, duration: 1.0).id("a"),
            ImageClip(img, duration: 2.0).id("b"),
            ImageClip(img, duration: 3.0).id("c"),
        ]
        // Move "a" → end (chain position 0 → 2). Equivalent to plain applyReorder.
        let chainResult = TimelineView.applyChainReorder(clips: clips, from: 0, to: 2)
        let plainResult = TimelineView.applyReorder(clips: clips, from: 0, to: 2)
        #expect(chainResult?.newClips.count == plainResult?.newClips.count)
        #expect(chainResult?.newClips[0].clipID == ClipID("b"))
        #expect(chainResult?.newClips[1].clipID == ClipID("c"))
        #expect(chainResult?.newClips[2].clipID == ClipID("a"))
    }

    @Test func applyChainReorderPreservesTracksAndFloaters() {
        let img = PlatformImage()
        let clips: [any Clip] = [
            ImageClip(img, duration: 1.0).id("a"),                                    // 0 — chain pos 0
            Track(at: 0.5) { ImageClip(img, duration: 1.0).id("ta") },                // 1 — Track stays at idx 1
            ImageClip(img, duration: 2.0).id("b"),                                    // 2 — chain pos 1
            ImageClip(img, duration: 1.0).at(time: 4.0).id("pip"),                    // 3 — floater stays at idx 3
            ImageClip(img, duration: 3.0).id("c"),                                    // 4 — chain pos 2
        ]
        // Reorder chain: move "a" (pos 0) to end (pos 2). New chain order: b, c, a.
        let result = TimelineView.applyChainReorder(clips: clips, from: 0, to: 2)
        #expect(result != nil)
        let merged = result!.newClips
        // Non-chain items retain their original positions.
        #expect(merged[1] is Track)
        #expect(merged[3].clipID == ClipID("pip"))
        // Chain slots filled with the reordered items in declaration order.
        #expect(merged[0].clipID == ClipID("b"))
        #expect(merged[2].clipID == ClipID("c"))
        #expect(merged[4].clipID == ClipID("a"))
    }

    @Test func applyChainReorderNoOpReturnsNil() {
        let img = PlatformImage()
        let clips: [any Clip] = [
            ImageClip(img, duration: 1.0).id("a"),
            ImageClip(img, duration: 2.0).id("b"),
        ]
        // Drop "a" on its own slot — no-op.
        let result = TimelineView.applyChainReorder(clips: clips, from: 0, to: 0)
        #expect(result == nil)
    }

    @Test func applyChainReorderTransitionTravelsWithSource() {
        let img = PlatformImage()
        let clips: [any Clip] = [
            ImageClip(img, duration: 1.0).id("a"),
            Kadr.Transition.fade(duration: 0.3),
            ImageClip(img, duration: 2.0).id("b"),
            Track(at: 5.0) { ImageClip(img, duration: 1.0) },                         // non-chain — stays at idx 3
            ImageClip(img, duration: 3.0).id("c"),
        ]
        // Chain order: a, fade, b, c. Move "a" group (pos 0, with its trailing
        // transition) to chain-pos 2 (after "b"). New chain order: b, a, fade, c.
        let result = TimelineView.applyChainReorder(clips: clips, from: 0, to: 2)
        #expect(result != nil)
        let merged = result!.newClips
        #expect(merged[3] is Track)  // non-chain preserved at original index
        // Chain slots: idx 0 = b, idx 1 = a, idx 2 = fade, idx 4 = c
        #expect(merged[0].clipID == ClipID("b"))
        #expect(merged[1].clipID == ClipID("a"))
        #expect(merged[2] is Kadr.Transition)
        #expect(merged[4].clipID == ClipID("c"))
    }

    // MARK: - applyTrackReorder (v0.7)

    @Test func applyTrackReorderReordersInnerClips() {
        let img = PlatformImage()
        let track = Track(at: 1.0, name: "B-roll") {
            ImageClip(img, duration: 1.0).id("a")
            ImageClip(img, duration: 2.0).id("b")
            ImageClip(img, duration: 3.0).id("c")
        }
        // Move "a" → end (pos 0 → 2). New order: b, c, a.
        let result = TimelineView.applyTrackReorder(track: track, from: 0, to: 2)
        #expect(result != nil)
        #expect(result?.clips.count == 3)
        #expect(result?.clips[0].clipID == ClipID("b"))
        #expect(result?.clips[1].clipID == ClipID("c"))
        #expect(result?.clips[2].clipID == ClipID("a"))
    }

    @Test func applyTrackReorderPreservesStartTimeAndName() {
        let img = PlatformImage()
        let track = Track(at: 2.5, name: "Cutaways") {
            ImageClip(img, duration: 1.0).id("a")
            ImageClip(img, duration: 2.0).id("b")
        }
        let result = TimelineView.applyTrackReorder(track: track, from: 0, to: 1)
        #expect(result != nil)
        #expect(result?.startTime == CMTime(seconds: 2.5, preferredTimescale: 600))
        #expect(result?.name == "Cutaways")
    }

    @Test func applyTrackReorderPreservesOpacityFactor() {
        let img = PlatformImage()
        let track = Track(at: 0.0) {
            ImageClip(img, duration: 1.0).id("a")
            ImageClip(img, duration: 2.0).id("b")
        }
        .opacity(0.5)
        let result = TimelineView.applyTrackReorder(track: track, from: 0, to: 1)
        #expect(result != nil)
        #expect(result?.opacityFactor == 0.5)
    }

    @Test func applyTrackReorderNoOpReturnsNil() {
        let img = PlatformImage()
        let track = Track {
            ImageClip(img, duration: 1.0).id("a")
            ImageClip(img, duration: 2.0).id("b")
        }
        // Drop on self.
        let result = TimelineView.applyTrackReorder(track: track, from: 0, to: 0)
        #expect(result == nil)
    }

    @Test func applyTrackReorderTransitionTravelsWithSource() {
        let img = PlatformImage()
        let track = Track(at: 0.0) {
            ImageClip(img, duration: 1.0).id("a")
            Transition.fade(duration: 0.3)
            ImageClip(img, duration: 2.0).id("b")
            ImageClip(img, duration: 3.0).id("c")
        }
        // Move "a" group (with its trailing fade) to position 2 (after "b").
        // New order: b, a, fade, c.
        let result = TimelineView.applyTrackReorder(track: track, from: 0, to: 2)
        #expect(result != nil)
        #expect(result?.clips.count == 4)
        #expect(result?.clips[0].clipID == ClipID("b"))
        #expect(result?.clips[1].clipID == ClipID("a"))
        #expect(result?.clips[2] is Kadr.Transition)
        #expect(result?.clips[3].clipID == ClipID("c"))
    }

    @Test func applyTrackReorderOutOfRangeSourceReturnsNil() {
        let img = PlatformImage()
        let track = Track {
            ImageClip(img, duration: 1.0).id("a")
        }
        // Single-clip track, dropping on self → nil per applyReorder semantics.
        let result = TimelineView.applyTrackReorder(track: track, from: 0, to: 0)
        #expect(result == nil)
    }

    // MARK: - End-to-end multi-track integration

    @Test func endToEndMultiTrackVideoMatchesExpectation() {
        let musicURL = URL(fileURLWithPath: "/tmp/m.mp3")
        let video = Video {
            image(20.0, id: "main")
            image(3.0, id: "pip1").at(time: 1.0)
            image(2.0, id: "pip2").at(time: 2.0)  // overlaps pip1 → forces 2 floater rows
            Track(at: 5.0) {
                image(2.0, id: "ta")
                Transition.fade(duration: 0.5)
                image(2.0, id: "tb")
            }
        }
        .audio { AudioTrack(url: musicURL) }

        let lanes = TimelineView.assignLanes(for: video, includeAudio: true)

        // chain (1) + track (1) + floater rows (2) + audio (1) = 5
        #expect(lanes.count == 5)

        // Order check.
        guard case .implicitChain = lanes[0].0,
              case .track = lanes[1].0,
              case .freeFloaters = lanes[2].0,
              case .freeFloaters = lanes[3].0,
              case .audio = lanes[4].0 else {
            Issue.record("lane order does not match spec")
            return
        }
    }
}
