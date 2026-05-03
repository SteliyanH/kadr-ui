import Testing
import SwiftUI
import CoreMedia
import Foundation
import Kadr
@testable import KadrUI

/// Pure-helper tests for `CaptionEditor`. Sort / validation / default-window
/// math are `nonisolated public static` on the editor type so they're testable
/// without driving SwiftUI focus / text-field commits.
struct CaptionEditorTests {

    // MARK: - Fixtures

    private func cmt(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func cue(_ start: Double, _ end: Double, _ text: String = "") -> Caption {
        Caption(
            text: text,
            timeRange: CMTimeRange(
                start: cmt(start),
                duration: cmt(end - start)
            )
        )
    }

    // MARK: - sortedByStart

    @Test func sortedByStartReordersOutOfOrderCues() {
        let cues = [cue(3.0, 4.0, "c"), cue(1.0, 2.0, "a"), cue(2.0, 3.0, "b")]
        let sorted = CaptionEditor.sortedByStart(cues)
        #expect(sorted.map(\.text) == ["a", "b", "c"])
    }

    @Test func sortedByStartIsStableForTies() {
        // Two cues with identical start — declaration order preserved.
        let cues = [cue(1.0, 2.0, "first"), cue(1.0, 3.0, "second")]
        let sorted = CaptionEditor.sortedByStart(cues)
        #expect(sorted.map(\.text) == ["first", "second"])
    }

    @Test func sortedByStartEmpty() {
        #expect(CaptionEditor.sortedByStart([]).isEmpty)
    }

    // MARK: - isValidCueRange

    @Test func validCueInsideCompositionPasses() {
        let range = CMTimeRange(start: cmt(1.0), duration: cmt(2.0))
        #expect(CaptionEditor.isValidCueRange(range, in: cmt(10.0)))
    }

    @Test func cueWithNegativeStartFails() {
        let range = CMTimeRange(start: cmt(-0.5), duration: cmt(1.0))
        #expect(!CaptionEditor.isValidCueRange(range, in: cmt(10.0)))
    }

    @Test func cueEndingPastCompositionFails() {
        let range = CMTimeRange(start: cmt(8.0), duration: cmt(5.0))
        #expect(!CaptionEditor.isValidCueRange(range, in: cmt(10.0)))
    }

    @Test func cueAtExactCompositionEndPasses() {
        let range = CMTimeRange(start: cmt(8.0), duration: cmt(2.0))
        #expect(CaptionEditor.isValidCueRange(range, in: cmt(10.0)))
    }

    @Test func zeroDurationCueIsValid() {
        // Allowed mid-edit so the editor doesn't fight the user.
        let range = CMTimeRange(start: cmt(2.0), duration: .zero)
        #expect(CaptionEditor.isValidCueRange(range, in: cmt(10.0)))
    }

    // MARK: - defaultNewCueStart

    @Test func defaultStartUsesPlayheadWhenSet() {
        let start = CaptionEditor.defaultNewCueStart(
            currentTime: cmt(3.5),
            compositionDuration: cmt(10.0)
        )
        #expect(abs(CMTimeGetSeconds(start) - 3.5) < 0.0001)
    }

    @Test func defaultStartUsesMidpointWhenPlayheadNil() {
        let start = CaptionEditor.defaultNewCueStart(
            currentTime: nil,
            compositionDuration: cmt(10.0)
        )
        #expect(abs(CMTimeGetSeconds(start) - 5.0) < 0.0001)
    }

    @Test func defaultStartClampsSoCueFitsInComposition() {
        // Playhead at 9.5 with 2-second cue + 10-second composition →
        // start clamps to 8 (so end lands at 10, the composition boundary).
        let start = CaptionEditor.defaultNewCueStart(
            currentTime: cmt(9.5),
            compositionDuration: cmt(10.0)
        )
        #expect(abs(CMTimeGetSeconds(start) - 8.0) < 0.0001)
    }

    @Test func defaultStartHandlesShortCompositions() {
        // 1-second composition, 2-second default cue → cap is 0 (negative
        // clamped), so start is 0 even though the cue can't fully fit.
        let start = CaptionEditor.defaultNewCueStart(
            currentTime: cmt(0.5),
            compositionDuration: cmt(1.0)
        )
        #expect(CMTimeGetSeconds(start) == 0)
    }

    // MARK: - cueRange

    @Test func cueRangeBuildsExpectedDuration() {
        let range = CaptionEditor.cueRange(
            startingAt: cmt(1.0),
            keepingEnd: cmt(3.5)
        )
        #expect(abs(CMTimeGetSeconds(range.start) - 1.0) < 0.0001)
        #expect(abs(CMTimeGetSeconds(range.duration) - 2.5) < 0.0001)
    }

    @Test func cueRangeWithEndAtStartIsZeroDuration() {
        let range = CaptionEditor.cueRange(startingAt: cmt(2.0), keepingEnd: cmt(2.0))
        #expect(range.duration == .zero)
    }

    @Test func cueRangeWithEndBeforeStartIsZeroDuration() {
        // Setting end behind start (e.g., user drags past start) collapses to
        // zero — the editor warns via the validity flag instead of throwing.
        let range = CaptionEditor.cueRange(startingAt: cmt(3.0), keepingEnd: cmt(1.0))
        #expect(range.start == cmt(3.0))
        #expect(range.duration == .zero)
    }

    // MARK: - Body smoke

    @MainActor
    @Test func bodyConstructsWithEmptyCaptions() {
        let view = CaptionEditor(
            captions: [],
            compositionDuration: cmt(10.0),
            onUpdate: { _ in }
        )
        _ = view.body
    }

    @MainActor
    @Test func bodyConstructsWithCuesAndPlayhead() {
        let cues = [cue(0.5, 1.5, "Hello"), cue(2.0, 3.5, "World")]
        let time = Binding<CMTime>.constant(cmt(1.0))
        let view = CaptionEditor(
            captions: cues,
            compositionDuration: cmt(10.0),
            currentTime: time,
            onUpdate: { _ in }
        )
        _ = view.body
    }

    @MainActor
    @Test func bodyConstructsWithInvalidCue() {
        // Cue past comp end — render should still succeed (just shows red).
        let cues = [cue(8.0, 12.0, "overflow")]
        let view = CaptionEditor(
            captions: cues,
            compositionDuration: cmt(10.0),
            onUpdate: { _ in }
        )
        _ = view.body
    }
}
