import Testing
import SwiftUI
import CoreMedia
import Kadr
@testable import KadrUI

/// Tests for `TransportBand`.
///
/// The band's judgements are static functions on purpose, so almost everything
/// here runs without a rendering host. The two tolerances get the most
/// attention, because they are the part that looks arbitrary and is not.
struct TransportBandTests {

    private func t(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    // MARK: - Timecode

    @Test("Elapsed time truncates, so the readout never runs ahead of the playhead")
    func elapsedTruncates() {
        // 0.9s is still second zero. Rounding here would show "0:01" while the
        // playhead has not reached one second, which reads as a bug.
        #expect(TransportControls.timecode(t(0.9)) == "0:00")
        #expect(TransportControls.timecode(t(1.0)) == "0:01")
        #expect(TransportControls.timecode(t(65)) == "1:05")
        #expect(TransportControls.timecode(t(600)) == "10:00")
    }

    @Test("Duration rounds, because the nearest second is the honest answer")
    func durationRounds() {
        #expect(TransportControls.durationTimecode(t(5.6)) == "0:06")
        #expect(TransportControls.durationTimecode(t(5.4)) == "0:05")
    }

    @Test("Indefinite and negative times clamp to zero rather than printing nonsense")
    func degenerateTimesClamp() {
        #expect(TransportControls.timecode(.indefinite) == "0:00")
        #expect(TransportControls.timecode(t(-4)) == "0:00")
        #expect(TransportControls.durationTimecode(.indefinite) == "0:00")
    }

    // MARK: - Skipping

    @Test("A skip clamps to both ends of the composition")
    func skipClamps() {
        #expect(TransportControls.skipTarget(from: t(0.2), by: -1, duration: t(10)).seconds == 0)
        #expect(TransportControls.skipTarget(from: t(9.5), by: 1, duration: t(10)).seconds == 10)
    }

    @Test("A skip in the middle lands exactly where asked")
    func skipIsExact() {
        #expect(TransportControls.skipTarget(from: t(4), by: 1, duration: t(10)).seconds == 5)
        #expect(TransportControls.skipTarget(from: t(4), by: -1, duration: t(10)).seconds == 3)
    }

    @Test("A composition with no duration has nowhere to skip to")
    func skipWithNoDuration() {
        #expect(TransportControls.skipTarget(from: .zero, by: 1, duration: .zero).seconds == 0)
    }

    // MARK: - Bounds

    @Test("A scrub just off zero still leaves skip-back live")
    func boundEpsilonIsTight() {
        // The point of the tight tolerance: 0.02s has real work to do.
        #expect(!TransportControls.isAtStart(t(0.02)))
        #expect(TransportControls.isAtStart(t(0.0005)))
        #expect(TransportControls.isAtStart(.zero))
    }

    @Test("The end bound is tight too")
    func endBoundIsTight() {
        #expect(!TransportControls.isAtEnd(t(9.9), duration: t(10)))
        #expect(TransportControls.isAtEnd(t(10), duration: t(10)))
    }

    @Test("An empty composition is at both bounds, and cannot play")
    func emptyCompositionIsInert() {
        #expect(TransportControls.isAtStart(.zero))
        #expect(TransportControls.isAtEnd(.zero, duration: .zero))
        #expect(!TransportControls.canPlay(duration: .zero))
        #expect(!TransportControls.canPlay(duration: .indefinite))
        #expect(TransportControls.canPlay(duration: t(1)))
    }

    // MARK: - The two tolerances are different on purpose

    @Test("End-of-playback is looser than the bound check, and that gap matters")
    func tolerancesDiffer() {
        let duration = t(10)
        let nearlyEnd = t(9.9)

        // A time observer ticking every 0.1s against the player item's duration
        // can publish a last position slightly short of the composition's.
        #expect(TransportControls.reachedEndOfPlayback(nearlyEnd, duration: duration))
        // But the playhead is not *on* the bound, so skip-forward stays live.
        #expect(!TransportControls.isAtEnd(nearlyEnd, duration: duration))
    }

    @Test("A pause in the middle is not an ending")
    func midCompositionIsNotAnEnding() {
        #expect(!TransportControls.reachedEndOfPlayback(t(5), duration: t(10)))
    }

    // MARK: - Loop restart

    @Test("Loop restarts only on a fall, only when looping, only at the end")
    func loopRestartRequiresEveryClause() {
        let end = t(10), duration = t(10)

        #expect(TransportControls.shouldRestartForLoop(
            wasPlaying: true, isPlaying: false, isLooping: true, current: end, duration: duration))

        // A rise is the restart's own echo.
        #expect(!TransportControls.shouldRestartForLoop(
            wasPlaying: false, isPlaying: true, isLooping: true, current: end, duration: duration))
        // Loop off.
        #expect(!TransportControls.shouldRestartForLoop(
            wasPlaying: true, isPlaying: false, isLooping: false, current: end, duration: duration))
        // A fall in the middle is a pause, not an ending.
        #expect(!TransportControls.shouldRestartForLoop(
            wasPlaying: true, isPlaying: false, isLooping: true, current: t(4), duration: duration))
    }

    @Test("A stop within the observer's slack still counts as an ending")
    func loopRestartsWithinTolerance() {
        #expect(TransportControls.shouldRestartForLoop(
            wasPlaying: true, isPlaying: false, isLooping: true,
            current: t(9.9), duration: t(10)))
    }

    // MARK: - Symbols

    @Test("The skip glyphs exist in SF Symbols")
    func skipGlyphsResolve() {
        // Image(systemName:) fails silently — it logs and draws a placeholder —
        // and the compiler only sees a String. This is the only thing that
        // catches a name that does not exist.
        #if canImport(UIKit)
        #expect(UIImage(systemName: TransportControls.skipBackSymbol) != nil)
        #expect(UIImage(systemName: TransportControls.skipForwardSymbol) != nil)
        #expect(UIImage(systemName: "play.fill") != nil)
        #expect(UIImage(systemName: "pause.fill") != nil)
        #expect(UIImage(systemName: "repeat") != nil)
        #expect(UIImage(systemName: "arrow.up.left.and.arrow.down.right") != nil)
        #expect(UIImage(systemName: "arrow.down.right.and.arrow.up.left") != nil)
        #endif
    }

    // MARK: - Spoken copy

    @Test("Every control has a spoken label, and none is empty")
    func labelsAreSpoken() {
        #expect(TransportControls.playPauseLabel(isPlaying: false) == "Play")
        #expect(TransportControls.playPauseLabel(isPlaying: true) == "Pause")
        #expect(!TransportControls.skipBackLabel.isEmpty)
        #expect(!TransportControls.skipForwardLabel.isEmpty)
        #expect(!TransportControls.loopLabel.isEmpty)
        #expect(TransportControls.loopValueLabel(isLooping: true) == "On")
        #expect(TransportControls.fullscreenLabel(isFullscreen: true) == "Exit full screen")
        #expect(TransportControls.fullscreenLabel(isFullscreen: false) == "Full screen")
    }

    @Test("The readout is spoken as a sentence, not as punctuation")
    func readoutIsSpokenAsASentence() {
        // "1:05 / 2:00" read literally is not useful.
        #expect(TransportControls.timeReadoutLabel(elapsed: "1:05", total: "2:00") == "1:05 of 2:00")
    }

    // MARK: - The view

    @MainActor
    @Test("The band builds with every control")
    func bodyBuildsWithEverything() {
        let band = TransportBand(
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            currentTime: .constant(CMTime(seconds: 3, preferredTimescale: 600)),
            isPlaying: .constant(true),
            isLooping: .constant(true),
            isFullscreen: .constant(false)
        )
        _ = band.body  // Should not crash.
    }

    @MainActor
    @Test("Loop and full screen are optional — the band builds without them")
    func bodyBuildsMinimal() {
        let band = TransportBand(
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            currentTime: .constant(.zero),
            isPlaying: .constant(false)
        )
        _ = band.body
    }

    @MainActor
    @Test("An empty composition still renders, with dead controls")
    func bodyBuildsForEmptyComposition() {
        let band = TransportBand(
            duration: .zero,
            currentTime: .constant(.zero),
            isPlaying: .constant(false)
        )
        _ = band.body
    }
}
