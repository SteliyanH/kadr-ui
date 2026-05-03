import SwiftUI
import CoreMedia
import Kadr

/// A list-style cue editor for ``Kadr/Video/captions(_:)``. Each row exposes the
/// cue's text plus its start / end timestamps, with quick "set to playhead"
/// shortcuts and a delete button. A trailing **+ Add cue** button appends a new
/// cue starting at the current playhead (or composition mid when no playhead is
/// bound).
///
/// **Read-only model.** The editor never mutates `Video` or any cue array
/// directly. Every commit fires ``init(captions:compositionDuration:currentTime:onUpdate:)``'s
/// `onUpdate` callback with the new sorted-by-start-time array; the consumer
/// rebuilds the composition via `video.captions(newCues)`.
///
/// **Validation.** Cues whose `timeRange` falls outside `[0, compositionDuration]`
/// are flagged with a red border and a warning glyph but are not silently
/// dropped — the consumer decides whether to allow them.
///
/// ```swift
/// CaptionEditor(
///     captions: video.captions,
///     compositionDuration: video.duration,
///     currentTime: $playheadTime,
///     onUpdate: { newCues in
///         self.video = video.captions(newCues)
///     }
/// )
/// ```
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct CaptionEditor: View {

    private let captions: [Caption]
    private let compositionDuration: CMTime
    private let currentTime: Binding<CMTime>?
    private let onUpdate: ([Caption]) -> Void

    /// Default duration for a freshly-added cue. Two seconds is roughly the
    /// dwell time used by SRT / VTT auto-generators and matches a comfortable
    /// reading window for short phrases.
    nonisolated public static let defaultNewCueDuration: TimeInterval = 2.0

    /// Create a caption editor.
    /// - Parameters:
    ///   - captions: Current cue list. Read-only.
    ///   - compositionDuration: Upper bound for end-time validation. Cues outside
    ///     `[0, compositionDuration]` render with a red border but aren't dropped.
    ///   - currentTime: Optional binding to a composition-relative playhead.
    ///     When non-`nil`, "Set start to playhead" / "Set end to playhead" rows
    ///     appear and **+ Add cue** seeds the new cue's start at the playhead.
    ///   - onUpdate: Fires on every committed edit (text-field commit, timestamp
    ///     change, +/- tap). Receives the new cue list, already sorted by
    ///     `timeRange.start` (sort-on-emit, no in-place reorder).
    public init(
        captions: [Caption],
        compositionDuration: CMTime,
        currentTime: Binding<CMTime>? = nil,
        onUpdate: @escaping ([Caption]) -> Void
    ) {
        self.captions = captions
        self.compositionDuration = compositionDuration
        self.currentTime = currentTime
        self.onUpdate = onUpdate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(captions.enumerated()), id: \.offset) { (index, cue) in
                cueRow(index: index, cue: cue)
            }
            Button {
                addCue()
            } label: {
                Label("Add cue", systemImage: "plus.circle.fill")
                    .font(.callout)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func cueRow(index: Int, cue: Caption) -> some View {
        let isValid = CaptionEditor.isValidCueRange(cue.timeRange, in: compositionDuration)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                CueTextField(text: cue.text) { newText in
                    var updated = captions
                    updated[index] = Caption(
                        text: newText,
                        timeRange: cue.timeRange
                    )
                    onUpdate(CaptionEditor.sortedByStart(updated))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    var updated = captions
                    updated.remove(at: index)
                    onUpdate(CaptionEditor.sortedByStart(updated))
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 8) {
                timestampField(
                    label: "Start",
                    seconds: CMTimeGetSeconds(cue.timeRange.start)
                ) { newStart in
                    let newRange = CMTimeRange(
                        start: CMTime(seconds: newStart, preferredTimescale: 600),
                        duration: cue.timeRange.duration
                    )
                    var updated = captions
                    updated[index] = Caption(text: cue.text, timeRange: newRange)
                    onUpdate(CaptionEditor.sortedByStart(updated))
                }
                if currentTime != nil {
                    Button("→") { setStartToPlayhead(at: index, cue: cue) }
                        .buttonStyle(.borderless)
                        .help("Set start to playhead")
                }
                timestampField(
                    label: "End",
                    seconds: CMTimeGetSeconds(cue.timeRange.end)
                ) { newEnd in
                    let start = cue.timeRange.start
                    let endTime = CMTime(seconds: newEnd, preferredTimescale: 600)
                    let newRange = CMTimeRange(
                        start: start,
                        duration: CMTimeSubtract(endTime, start)
                    )
                    var updated = captions
                    updated[index] = Caption(text: cue.text, timeRange: newRange)
                    onUpdate(CaptionEditor.sortedByStart(updated))
                }
                if currentTime != nil {
                    Button("→") { setEndToPlayhead(at: index, cue: cue) }
                        .buttonStyle(.borderless)
                        .help("Set end to playhead")
                }
                if !isValid {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .help("Cue is outside the composition's time range.")
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isValid ? Color.gray.opacity(0.3) : Color.red, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func timestampField(
        label: String,
        seconds: Double,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            TimestampField(seconds: seconds, onCommit: onCommit)
                .frame(width: 80)
        }
    }

    // MARK: - Edit operations

    private func addCue() {
        let start = CaptionEditor.defaultNewCueStart(
            currentTime: currentTime?.wrappedValue,
            compositionDuration: compositionDuration
        )
        let duration = CMTime(
            seconds: CaptionEditor.defaultNewCueDuration,
            preferredTimescale: 600
        )
        let cue = Caption(
            text: "",
            timeRange: CMTimeRange(start: start, duration: duration)
        )
        let updated = captions + [cue]
        onUpdate(CaptionEditor.sortedByStart(updated))
    }

    private func setStartToPlayhead(at index: Int, cue: Caption) {
        guard let currentTime else { return }
        let newStart = currentTime.wrappedValue
        let newRange = CaptionEditor.cueRange(
            startingAt: newStart,
            keepingEnd: cue.timeRange.end
        )
        var updated = captions
        updated[index] = Caption(text: cue.text, timeRange: newRange)
        onUpdate(CaptionEditor.sortedByStart(updated))
    }

    private func setEndToPlayhead(at index: Int, cue: Caption) {
        guard let currentTime else { return }
        let newEnd = currentTime.wrappedValue
        let newRange = CaptionEditor.cueRange(
            startingAt: cue.timeRange.start,
            keepingEnd: newEnd
        )
        var updated = captions
        updated[index] = Caption(text: cue.text, timeRange: newRange)
        onUpdate(CaptionEditor.sortedByStart(updated))
    }
}

// MARK: - Pure helpers

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
extension CaptionEditor {

    /// Sort cues by `timeRange.start`. Stable for cues with identical starts —
    /// declaration order is preserved within a tie.
    nonisolated public static func sortedByStart(_ captions: [Caption]) -> [Caption] {
        captions.enumerated()
            .sorted { lhs, rhs in
                let cmp = CMTimeCompare(lhs.element.timeRange.start, rhs.element.timeRange.start)
                if cmp != 0 { return cmp < 0 }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Whether `range` lies fully within `[0, compositionDuration]`. Used by the
    /// editor's row to render a red-border warning. Pure, testable.
    nonisolated public static func isValidCueRange(
        _ range: CMTimeRange,
        in compositionDuration: CMTime
    ) -> Bool {
        // Allow zero-duration cues (degenerate) so the editor doesn't fight a
        // user mid-edit; flag only when start < 0 or end > comp duration.
        if CMTimeCompare(range.start, .zero) < 0 { return false }
        if CMTimeCompare(range.end, compositionDuration) > 0 { return false }
        if CMTimeCompare(range.duration, .zero) < 0 { return false }
        return true
    }

    /// Default `start` for a freshly-added cue. Prefers `currentTime` when set;
    /// otherwise falls back to the composition's midpoint. Clamped to a valid
    /// region so the appended cue's default 2-second window stays inside the
    /// composition (when possible).
    nonisolated public static func defaultNewCueStart(
        currentTime: CMTime?,
        compositionDuration: CMTime
    ) -> CMTime {
        let durSec = CMTimeGetSeconds(compositionDuration)
        let cap = max(0, durSec - defaultNewCueDuration)
        let raw: Double
        if let currentTime {
            raw = CMTimeGetSeconds(currentTime)
        } else {
            raw = max(0, durSec / 2)
        }
        let clamped = max(0, min(cap, raw))
        return CMTime(seconds: clamped, preferredTimescale: 600)
    }

    /// Build a `CMTimeRange` from a `start` and a (kept) `end`. Returns a
    /// zero-duration range when `end <= start`.
    nonisolated public static func cueRange(
        startingAt start: CMTime,
        keepingEnd end: CMTime
    ) -> CMTimeRange {
        let cmp = CMTimeCompare(end, start)
        if cmp <= 0 {
            return CMTimeRange(start: start, duration: .zero)
        }
        return CMTimeRange(start: start, duration: CMTimeSubtract(end, start))
    }
}

// MARK: - Internal subviews

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
private struct CueTextField: View {
    let text: String
    let onCommit: (String) -> Void

    @State private var draft: String

    init(text: String, onCommit: @escaping (String) -> Void) {
        self.text = text
        self.onCommit = onCommit
        self._draft = State(initialValue: text)
    }

    var body: some View {
        TextField("Cue text", text: $draft, axis: .vertical)
            .font(.body)
            .lineLimit(1...3)
            .onChange(of: text) { newValue in
                if draft != newValue { draft = newValue }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        if draft != text { onCommit(draft) }
    }
}

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
private struct TimestampField: View {
    let seconds: Double
    let onCommit: (Double) -> Void

    @State private var draft: String

    init(seconds: Double, onCommit: @escaping (Double) -> Void) {
        self.seconds = seconds
        self.onCommit = onCommit
        self._draft = State(initialValue: String(format: "%.2f", seconds))
    }

    var body: some View {
        TextField("0.00", text: $draft)
            .font(.caption.monospacedDigit())
            .multilineTextAlignment(.trailing)
            .onChange(of: seconds) { newValue in
                let formatted = String(format: "%.2f", newValue)
                if draft != formatted { draft = formatted }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        guard let parsed = Double(draft) else {
            draft = String(format: "%.2f", seconds)
            return
        }
        if parsed != seconds { onCommit(parsed) }
    }
}
