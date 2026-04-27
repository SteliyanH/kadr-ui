import SwiftUI
import CoreMedia
import Kadr

/// A read-only horizontal timeline visualizing a Kadr ``Kadr/Video`` composition's
/// clip layout, transitions, and audio tracks.
///
/// Each clip occupies a width proportional to its duration; transitions render as
/// small glyphs in the gaps between adjacent clip blocks; audio tracks appear in a
/// lane below the clip strip. A `currentTime` binding (optional) surfaces a vertical
/// playhead synchronized with playback time — pair it with ``VideoPreview``'s
/// `AVPlayer` if you want a scrubber that moves with playback.
///
/// ```swift
/// VStack(spacing: 8) {
///     VideoPreview(video)
///     TimelineView(video, currentTime: $playheadTime)
///         .frame(height: 72)
/// }
/// ```
///
/// **Async duration loading.** Kadr's `VideoClip.duration` returns `.zero` synchronously
/// for an untrimmed clip (the source asset's duration isn't known without an async load).
/// On first appear, `TimelineView` walks the composition and asynchronously loads
/// ``Kadr/VideoClip/metadata`` for any untrimmed `VideoClip`s, then re-lays out using
/// the resolved durations. Until each load completes the corresponding clip renders at
/// zero width.
///
/// **Read-only.** This v0.4.1 PR ships the read-only timeline. Selection, drag-to-reorder,
/// and trim handles arrive in subsequent PRs as pure callbacks (Kadr's `Video` is
/// immutable; the timeline surfaces user intent — consumers rebuild the `Video`).
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct TimelineView: View {

    private let video: Video
    private let currentTime: Binding<CMTime>?
    private let selectedClipID: Binding<ClipID?>?

    /// Resolved durations for clips whose `Clip.duration` is synchronously `.zero`
    /// (currently only untrimmed `VideoClip`s). Keyed by index in `video.clips`.
    @State private var resolvedDurations: [Int: CMTime] = [:]

    /// Create a timeline for `video`.
    /// - Parameters:
    ///   - video: The composition to visualize.
    ///   - currentTime: Optional binding to a playhead time. When non-`nil`, a vertical
    ///     line is drawn at the corresponding x position; the timeline does not write
    ///     back to the binding (scrubbing-by-tap is reserved for a future PR).
    ///   - selectedClipID: Optional binding to a ``Kadr/ClipID`` for tap-to-select.
    ///     Tapping a media clip with a non-`nil` ``Kadr/Clip/clipID`` writes its ID
    ///     into the binding; tapping the already-selected clip clears it. Tapping
    ///     transitions or unidentified clips does nothing. The selected clip is
    ///     highlighted with a thicker, brighter border.
    public init(
        _ video: Video,
        currentTime: Binding<CMTime>? = nil,
        selectedClipID: Binding<ClipID?>? = nil
    ) {
        self.video = video
        self.currentTime = currentTime
        self.selectedClipID = selectedClipID
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalSeconds = compositionDuration()
            let pxPerSecond = totalSeconds > 0 ? geometry.size.width / totalSeconds : 0

            ZStack(alignment: .topLeading) {
                clipStrip(pxPerSecond: pxPerSecond, totalSeconds: totalSeconds)
                if let currentTime, totalSeconds > 0 {
                    playhead(
                        at: CMTimeGetSeconds(currentTime.wrappedValue),
                        pxPerSecond: pxPerSecond,
                        height: geometry.size.height
                    )
                }
            }
        }
        .task {
            await resolveDurations()
        }
    }

    // MARK: - Strip layout

    @ViewBuilder
    private func clipStrip(pxPerSecond: Double, totalSeconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(video.clips.indices, id: \.self) { index in
                    clipBlock(at: index, pxPerSecond: pxPerSecond)
                }
            }
            .frame(height: 40)

            if !video.audioTracks.isEmpty {
                audioLane(totalSeconds: totalSeconds, pxPerSecond: pxPerSecond)
                    .frame(height: 12)
            }
        }
    }

    @ViewBuilder
    private func clipBlock(at index: Int, pxPerSecond: Double) -> some View {
        let clip = video.clips[index]
        let seconds = CMTimeGetSeconds(durationForClip(at: index))
        let width = max(0, seconds * pxPerSecond)

        if clip is Kadr.Transition {
            transitionGlyph()
                .frame(width: width)
        } else {
            let isSelected = clip.clipID != nil && clip.clipID == selectedClipID?.wrappedValue
            RoundedRectangle(cornerRadius: 4)
                .fill(clipColor(for: clip).opacity(isSelected ? 0.85 : 0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isSelected ? Color.white : clipColor(for: clip),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .overlay(
                    Text(clipLabel(for: clip, seconds: seconds))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4),
                    alignment: .leading
                )
                .frame(width: width)
                .padding(.horizontal, 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    handleTap(on: clip)
                }
        }
    }

    private func handleTap(on clip: any Clip) {
        guard let binding = selectedClipID, let id = clip.clipID else { return }
        // Tapping the already-selected clip clears the selection.
        binding.wrappedValue = (binding.wrappedValue == id) ? nil : id
    }

    @ViewBuilder
    private func transitionGlyph() -> some View {
        ZStack {
            Rectangle().fill(.gray.opacity(0.2))
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func audioLane(totalSeconds: Double, pxPerSecond: Double) -> some View {
        VStack(spacing: 2) {
            ForEach(video.audioTracks.indices, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.purple.opacity(0.5))
                    .frame(width: max(0, totalSeconds * pxPerSecond))
            }
        }
    }

    @ViewBuilder
    private func playhead(at seconds: Double, pxPerSecond: Double, height: CGFloat) -> some View {
        let x = max(0, seconds * pxPerSecond)
        Rectangle()
            .fill(.red)
            .frame(width: 2, height: height)
            .offset(x: x)
            .allowsHitTesting(false)
    }

    // MARK: - Clip styling

    private func clipColor(for clip: any Clip) -> Color {
        if clip is VideoClip { return .blue }
        if clip is ImageClip { return .green }
        if clip is TitleSequence { return .orange }
        return .gray
    }

    private func clipLabel(for clip: any Clip, seconds: Double) -> String {
        let prefix: String
        if clip is VideoClip { prefix = "Video" }
        else if clip is ImageClip { prefix = "Image" }
        else if clip is TitleSequence { prefix = "Title" }
        else { prefix = "Clip" }
        return String(format: "%@ %.1fs", prefix, seconds)
    }

    // MARK: - Durations

    private func compositionDuration() -> Double {
        var total: CMTime = .zero
        for index in video.clips.indices {
            total = CMTimeAdd(total, durationForClip(at: index))
        }
        return CMTimeGetSeconds(total)
    }

    private func durationForClip(at index: Int) -> CMTime {
        let clip = video.clips[index]
        let synchronous = clip.duration
        // VideoClip without a trim returns .zero; substitute the resolved value if loaded.
        if CMTimeCompare(synchronous, .zero) > 0 {
            return synchronous
        }
        return resolvedDurations[index] ?? .zero
    }

    private func resolveDurations() async {
        for index in video.clips.indices {
            guard let videoClip = video.clips[index] as? VideoClip else { continue }
            // Already has a synchronous duration (trimmed) — skip.
            if CMTimeCompare(videoClip.duration, .zero) > 0 { continue }
            // Already resolved — skip.
            if resolvedDurations[index] != nil { continue }

            if let metadata = try? await videoClip.metadata {
                resolvedDurations[index] = metadata.duration
            }
        }
    }
}
