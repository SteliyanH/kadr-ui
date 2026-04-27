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
    private let laneHeight: CGFloat
    private let laneSpacing: CGFloat
    private let onReorder: ((_ from: Int, _ to: Int, _ newClips: [any Clip]) -> Void)?
    private let onTrim: ((_ clipIndex: Int, _ leadingTrim: CMTime, _ trailingTrim: CMTime) -> Void)?

    /// Resolved durations for clips whose `Clip.duration` is synchronously `.zero`
    /// (currently only untrimmed `VideoClip`s). Keyed by index in `video.clips`.
    @State private var resolvedDurations: [Int: CMTime] = [:]

    /// Index of the media clip currently being dragged, if any.
    @State private var draggingIndex: Int?
    /// Horizontal pixel offset of the dragged clip from its resting position.
    @State private var dragOffset: CGFloat = 0

    /// Index of the clip whose trim handle is currently being dragged, if any.
    @State private var trimmingIndex: Int?
    /// Whether the trim drag is on the leading (left) or trailing (right) handle.
    @State private var trimmingEdge: TrimEdge?
    /// Current pixel delta of the in-flight trim drag. Drives the live width/offset
    /// preview on the dragged clip; applied to the callback in seconds on release.
    @State private var trimPixelDelta: CGFloat = 0

    internal enum TrimEdge { case leading, trailing }

    /// Create a timeline for `video`.
    /// - Parameters:
    ///   - video: The composition to visualize.
    ///   - currentTime: Optional binding to a playhead time. When non-`nil`, a vertical
    ///     line is drawn at the corresponding x position. Tapping or dragging on the
    ///     thin scrub strip above the clip lane writes a new time back to this binding,
    ///     clamped to `0...video.duration` (added in v0.4.2). Consumers wire the binding's
    ///     `.onChange` to seek their `AVPlayer` if they want playback to follow.
    ///   - selectedClipID: Optional binding to a ``Kadr/ClipID`` for tap-to-select.
    ///     Tapping a media clip with a non-`nil` ``Kadr/Clip/clipID`` writes its ID
    ///     into the binding; tapping the already-selected clip clears it. Tapping
    ///     transitions or unidentified clips does nothing. The selected clip is
    ///     highlighted with a thicker, brighter border.
    ///   - onReorder: Optional callback fired when the user drags a media clip to a new
    ///     position. Receives the **source** index, the **target** index, and the
    ///     **new clips array** ready to be passed back into a fresh ``Kadr/Video``
    ///     composition. Kadr's `Video` is immutable — `TimelineView` does not mutate;
    ///     the consumer rebuilds. Transitions automatically travel with their preceding
    ///     media clip during the reorder, so consumers never see a freestanding
    ///     ``Kadr/Transition`` mid-reorder. Drag uses a 10-pt minimum distance so it
    ///     does not conflict with `selectedClipID` taps.
    ///   - onTrim: Optional callback fired when the user drags a clip's leading or
    ///     trailing trim handle. Receives the clip index plus two `CMTime` deltas:
    ///     `leadingTrim` (positive = trimmed from the front; negative = extended forward),
    ///     `trailingTrim` (positive = trimmed from the back; negative = extended backward).
    ///     The consumer applies the deltas to its own `Video` — for ``Kadr/VideoClip``,
    ///     shift `trimRange` by the deltas; for ``Kadr/ImageClip`` / ``Kadr/TitleSequence``
    ///     adjust `duration` by `-(leadingTrim + trailingTrim)` (only the back handle
    ///     normally moves, since they have no source-asset front to retrieve). When
    ///     `onTrim` is non-`nil`, thin grab handles render on the leading and trailing
    ///     edges of every media-clip block.
    public init(
        _ video: Video,
        currentTime: Binding<CMTime>? = nil,
        selectedClipID: Binding<ClipID?>? = nil,
        laneHeight: CGFloat = 40,
        laneSpacing: CGFloat = 4,
        onReorder: ((_ from: Int, _ to: Int, _ newClips: [any Clip]) -> Void)? = nil,
        onTrim: ((_ clipIndex: Int, _ leadingTrim: CMTime, _ trailingTrim: CMTime) -> Void)? = nil
    ) {
        self.video = video
        self.currentTime = currentTime
        self.selectedClipID = selectedClipID
        self.laneHeight = laneHeight
        self.laneSpacing = laneSpacing
        self.onReorder = onReorder
        self.onTrim = onTrim
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalSeconds = compositionDuration()
            let pxPerSecond = totalSeconds > 0 ? geometry.size.width / totalSeconds : 0
            let lanes = TimelineView.assignLanes(for: video, includeAudio: false)

            ZStack(alignment: .topLeading) {
                if lanes.count <= 1 {
                    // Chain-only short-circuit — pixel-identical to v0.4.x.
                    clipStrip(pxPerSecond: pxPerSecond, totalSeconds: totalSeconds)
                } else {
                    multiLaneStrip(
                        lanes: lanes,
                        pxPerSecond: pxPerSecond,
                        totalSeconds: totalSeconds
                    )
                }
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

    // MARK: - Multi-lane strip (v0.5)

    /// Multi-lane render — engaged when the composition has Tracks or `.at(time:)`
    /// clips. Each lane renders read-only blocks positioned absolutely on the
    /// shared time axis. Edit gestures (reorder/trim) are NOT preserved on lane 0
    /// in this path — they only apply to the chain-only short-circuit. Lane-0
    /// editing in multi-track compositions is deferred to v0.5.x.
    @ViewBuilder
    private func multiLaneStrip(
        lanes: [(LaneKind, [LaneItem])],
        pxPerSecond: Double,
        totalSeconds: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: laneSpacing) {
            if currentTime != nil {
                scrubStrip(pxPerSecond: pxPerSecond, totalSeconds: totalSeconds)
                    .frame(height: 14)
            }
            ForEach(lanes.indices, id: \.self) { i in
                laneRow(
                    lane: lanes[i],
                    pxPerSecond: pxPerSecond,
                    totalSeconds: totalSeconds
                )
                .frame(height: laneHeight)
            }
        }
    }

    @ViewBuilder
    private func laneRow(
        lane: (LaneKind, [LaneItem]),
        pxPerSecond: Double,
        totalSeconds: Double
    ) -> some View {
        let totalWidth = max(0, totalSeconds * pxPerSecond)
        ZStack(alignment: .topLeading) {
            // Lane background — subtle, distinguishes adjacent lanes.
            RoundedRectangle(cornerRadius: 2)
                .fill(.gray.opacity(0.08))
                .frame(width: totalWidth, height: laneHeight)
            ForEach(lane.1.indices, id: \.self) { i in
                let item = lane.1[i]
                laneItemBlock(item: item, pxPerSecond: pxPerSecond)
            }
        }
    }

    @ViewBuilder
    private func laneItemBlock(item: LaneItem, pxPerSecond: Double) -> some View {
        let x = max(0, CMTimeGetSeconds(item.startTime) * pxPerSecond)
        let w = max(0, CMTimeGetSeconds(item.duration) * pxPerSecond)
        let isSelected = selectedClipID != nil && item.clipID != nil && selectedClipID?.wrappedValue == item.clipID
        let view = RoundedRectangle(cornerRadius: 4)
            .fill(laneItemColor(item.kind))
            .frame(width: w, height: laneHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.white : .clear, lineWidth: 2)
            )
            .offset(x: x)

        if let id = item.clipID, let binding = selectedClipID {
            view.onTapGesture { binding.wrappedValue = id }
        } else {
            view
        }
    }

    private func laneItemColor(_ kind: ItemKind) -> Color {
        switch kind {
        case .video: return .blue.opacity(0.85)
        case .image: return .green.opacity(0.85)
        case .title: return .orange.opacity(0.85)
        case .transition: return .gray.opacity(0.5)
        case .audio: return .purple.opacity(0.6)
        }
    }

    // MARK: - Strip layout

    @ViewBuilder
    private func clipStrip(pxPerSecond: Double, totalSeconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if currentTime != nil {
                scrubStrip(pxPerSecond: pxPerSecond, totalSeconds: totalSeconds)
                    .frame(height: 14)
            }

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

    /// Thin tap-and-drag scrubber strip above the clip lane. Renders only when the
    /// caller passed a `currentTime` binding. Any pointer interaction inside it writes
    /// `x / pxPerSecond` (clamped to `0...totalSeconds`) back to the binding.
    @ViewBuilder
    private func scrubStrip(pxPerSecond: Double, totalSeconds: Double) -> some View {
        Rectangle()
            .fill(.gray.opacity(0.25))
            .overlay(alignment: .topLeading) {
                if let currentTime, pxPerSecond > 0 {
                    let x = max(0, CMTimeGetSeconds(currentTime.wrappedValue)) * pxPerSecond
                    Triangle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .offset(x: x - 4, y: 0)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(pxPerSecond: pxPerSecond, totalSeconds: totalSeconds))
    }

    private func scrubGesture(pxPerSecond: Double, totalSeconds: Double) -> some Gesture {
        // minimumDistance: 0 so a tap (no drag) also seeks.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                writeScrub(at: value.location.x, pxPerSecond: pxPerSecond, totalSeconds: totalSeconds)
            }
            .onEnded { value in
                writeScrub(at: value.location.x, pxPerSecond: pxPerSecond, totalSeconds: totalSeconds)
            }
    }

    private func writeScrub(at x: CGFloat, pxPerSecond: Double, totalSeconds: Double) {
        guard let binding = currentTime, pxPerSecond > 0 else { return }
        let seconds = TimelineView.scrubTime(x: x, pxPerSecond: pxPerSecond, totalSeconds: totalSeconds)
        binding.wrappedValue = CMTime(seconds: seconds, preferredTimescale: 600)
    }

    /// Pure: convert an x-pixel position in the scrub strip to a clamped time in seconds.
    /// Defensive against zero/negative `pxPerSecond` and out-of-range x values.
    /// Internal so scrub math is unit-testable without driving SwiftUI gestures.
    internal static func scrubTime(x: CGFloat, pxPerSecond: Double, totalSeconds: Double) -> Double {
        guard pxPerSecond > 0 else { return 0 }
        let raw = Double(x) / pxPerSecond
        return min(max(raw, 0), max(0, totalSeconds))
    }

    @ViewBuilder
    private func clipBlock(at index: Int, pxPerSecond: Double) -> some View {
        let clip = video.clips[index]
        let seconds = CMTimeGetSeconds(durationForClip(at: index))
        let baseWidth = max(0, seconds * pxPerSecond)

        if clip is Kadr.Transition {
            // Transitions don't host their own gestures, but they shift visually during
            // a sibling reorder: a transition that's part of the source group travels
            // with the source; transitions between source and target shift to make space.
            let offset = clipReorderOffset(for: index, pxPerSecond: pxPerSecond)
            transitionGlyph()
                .frame(width: baseWidth)
                .offset(x: offset)
                .animation(.snappy(duration: 0.18), value: offset)
                .zIndex(isPartOfSourceGroup(index) ? 1 : 0)
        } else {
            let isSelected = clip.clipID != nil && clip.clipID == selectedClipID?.wrappedValue
            let isDragging = draggingIndex == index
            // Live trim deltas: keep the slot's reserved width fixed (so neighbors don't
            // reflow during the drag) but morph the inner content's width and offset.
            // On release the consumer rebuilds the Video with the new durations and the
            // slots recompute on the next render pass.
            let (liveWidth, liveOffset) = liveTrimMetrics(for: index, baseWidth: baseWidth)

            ZStack(alignment: .topLeading) {
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
                    .frame(width: max(0, liveWidth))
                    .offset(x: liveOffset)
                    .overlay(alignment: .leading) {
                        if onTrim != nil { trimHandle(at: index, edge: .leading, pxPerSecond: pxPerSecond) }
                    }
                    .overlay(alignment: .trailing) {
                        if onTrim != nil { trimHandle(at: index, edge: .trailing, pxPerSecond: pxPerSecond) }
                    }
                    .scaleEffect(isDragging ? 1.05 : 1.0)
                    .shadow(color: .black.opacity(isDragging ? 0.3 : 0), radius: isDragging ? 6 : 0)
                    .offset(x: clipReorderOffset(for: index, pxPerSecond: pxPerSecond))
                    .animation(.snappy(duration: 0.18), value: reorderAnimationKey(for: index, pxPerSecond: pxPerSecond))
                    .zIndex(isDragging || trimmingIndex == index ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleTap(on: clip)
                    }
                    .gesture(reorderGesture(for: index, pxPerSecond: pxPerSecond))
            }
            .frame(width: baseWidth, height: 40, alignment: .topLeading)
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Live reorder offsets

    /// True if `index` is the source media clip OR its trailing transition during an
    /// in-flight reorder drag. Both travel together visually.
    private func isPartOfSourceGroup(_ index: Int) -> Bool {
        guard let src = draggingIndex else { return false }
        let groupSize = sourceGroupSize(for: src)
        return index >= src && index < src + groupSize
    }

    private func sourceGroupSize(for src: Int) -> Int {
        (src + 1 < video.clips.count && video.clips[src + 1] is Kadr.Transition) ? 2 : 1
    }

    /// Horizontal offset to apply to clip `index` for live reorder feedback. The source
    /// group rides the finger; clips between source and projected target shift left or
    /// right by the source-group width to visually open the drop slot.
    private func clipReorderOffset(for index: Int, pxPerSecond: Double) -> CGFloat {
        guard let src = draggingIndex else { return 0 }
        let groupSize = sourceGroupSize(for: src)
        if index >= src && index < src + groupSize {
            return dragOffset   // source group rides the finger
        }
        let widths: [CGFloat] = video.clips.indices.map {
            CGFloat(CMTimeGetSeconds(durationForClip(at: $0))) * pxPerSecond
        }
        let target = TimelineView.computeTargetIndex(
            source: src, dragX: dragOffset, slotWidths: widths
        )
        return TimelineView.reorderShiftOffset(
            index: index,
            source: src,
            groupSize: groupSize,
            target: target,
            slotWidths: widths
        )
    }

    /// Drives `.animation(value:)` so SwiftUI re-runs the snappy transition only on
    /// state changes that should animate (a slot crossing), not on every drag pixel.
    private func reorderAnimationKey(for index: Int, pxPerSecond: Double) -> Int {
        guard let src = draggingIndex, src != index else { return 0 }
        let widths: [CGFloat] = video.clips.indices.map {
            CGFloat(CMTimeGetSeconds(durationForClip(at: $0))) * pxPerSecond
        }
        return TimelineView.computeTargetIndex(source: src, dragX: dragOffset, slotWidths: widths)
    }

    /// Pure: per-index horizontal shift offset for live reorder feedback. The source
    /// group itself returns 0 here (the source's offset is `dragOffset`, applied by
    /// the caller). Other clips shift only if they sit between source and target.
    ///
    /// - Returns: `-groupWidth` when the clip should slide left to fill the source's
    ///   vacated slot, `+groupWidth` when it should slide right to make room before
    ///   the target, otherwise `0`.
    ///
    /// Internal so the rule is unit-testable without driving SwiftUI gestures.
    internal static func reorderShiftOffset(
        index: Int,
        source: Int,
        groupSize: Int,
        target: Int,
        slotWidths widths: [CGFloat]
    ) -> CGFloat {
        // Skip the source group itself; caller handles its offset.
        if index >= source && index < source + groupSize { return 0 }

        var groupWidth: CGFloat = 0
        for i in source..<source + groupSize where i < widths.count {
            groupWidth += widths[i]
        }

        if target > source {
            // Source moved right. Clips originally at (source + groupSize - 1, target]
            // shift left by groupWidth to fill the vacated slot.
            if index >= source + groupSize && index <= target { return -groupWidth }
        } else if target < source {
            // Source moved left. Clips originally at [target, source) shift right by
            // groupWidth to make room before the target.
            if index >= target && index < source { return groupWidth }
        }
        return 0
    }

    /// Compute the dragged clip's live width and its leading-edge offset during a trim
    /// drag. Non-trimming clips return `(baseWidth, 0)` — no morph.
    private func liveTrimMetrics(for index: Int, baseWidth: CGFloat) -> (width: CGFloat, offset: CGFloat) {
        guard trimmingIndex == index, let edge = trimmingEdge else {
            return (baseWidth, 0)
        }
        return TimelineView.liveTrimMetrics(edge: edge, baseWidth: baseWidth, pixelDelta: trimPixelDelta)
    }

    /// Pure: live-width and leading-offset for a clip being trimmed. Surfaced as a
    /// static so the math is unit-testable without driving SwiftUI gestures.
    ///
    /// - Leading edge dragged right by `Δ` → width shrinks by `Δ`, content offsets right
    ///   by `Δ` so the visual right edge stays anchored at its slot's right edge.
    /// - Trailing edge drag → width changes by `Δ` (positive = wider, negative = narrower),
    ///   no leading-edge offset.
    internal static func liveTrimMetrics(
        edge: TrimEdge,
        baseWidth: CGFloat,
        pixelDelta: CGFloat
    ) -> (width: CGFloat, offset: CGFloat) {
        switch edge {
        case .leading:
            return (baseWidth - pixelDelta, pixelDelta)
        case .trailing:
            return (baseWidth + pixelDelta, 0)
        }
    }

    @ViewBuilder
    private func trimHandle(at index: Int, edge: TrimEdge, pxPerSecond: Double) -> some View {
        let isActive = trimmingIndex == index && trimmingEdge == edge
        Rectangle()
            .fill(isActive ? Color.white : Color.white.opacity(0.5))
            .frame(width: 4)
            .contentShape(Rectangle().inset(by: -6))   // wider hit target than visual
            .gesture(trimGesture(at: index, edge: edge, pxPerSecond: pxPerSecond))
    }

    private func trimGesture(at index: Int, edge: TrimEdge, pxPerSecond: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if onTrim == nil { return }
                if trimmingIndex == nil {
                    trimmingIndex = index
                    trimmingEdge = edge
                }
                trimPixelDelta = value.translation.width
            }
            .onEnded { value in
                defer {
                    trimmingIndex = nil
                    trimmingEdge = nil
                    trimPixelDelta = 0
                }
                guard onTrim != nil, pxPerSecond > 0 else { return }
                let (leading, trailing) = TimelineView.computeTrimDeltas(
                    edge: edge,
                    pixelDelta: value.translation.width,
                    pxPerSecond: pxPerSecond
                )
                onTrim?(index, leading, trailing)
            }
    }

    private func reorderGesture(for index: Int, pxPerSecond: Double) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if onReorder == nil { return }
                if draggingIndex == nil { draggingIndex = index }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                defer {
                    draggingIndex = nil
                    dragOffset = 0
                }
                guard onReorder != nil else { return }
                let target = computeTargetIndex(
                    source: index,
                    dragX: value.translation.width,
                    pxPerSecond: pxPerSecond
                )
                handleReorder(from: index, to: target)
            }
    }

    private func handleTap(on clip: any Clip) {
        guard let binding = selectedClipID, let id = clip.clipID else { return }
        // Tapping the already-selected clip clears the selection.
        binding.wrappedValue = (binding.wrappedValue == id) ? nil : id
    }

    // MARK: - Reorder math

    private func computeTargetIndex(source: Int, dragX: CGFloat, pxPerSecond: Double) -> Int {
        let widths: [CGFloat] = video.clips.indices.map {
            CGFloat(CMTimeGetSeconds(durationForClip(at: $0))) * pxPerSecond
        }
        return TimelineView.computeTargetIndex(source: source, dragX: dragX, slotWidths: widths)
    }

    private func handleReorder(from sourceIndex: Int, to rawTarget: Int) {
        guard let result = TimelineView.applyReorder(
            clips: Array(video.clips),
            from: sourceIndex,
            to: rawTarget
        ) else { return }
        onReorder?(sourceIndex, result.targetIndex, result.newClips)
    }

    /// Pure: which slot does the dragged clip's center lie over after `dragX` pixels of
    /// horizontal translation? Walks slot widths and returns the first slot whose
    /// midpoint exceeds the projected finger x.
    ///
    /// Internal so `TimelineView`'s reorder math can be unit-tested without driving
    /// SwiftUI gestures.
    internal static func computeTargetIndex(
        source: Int,
        dragX: CGFloat,
        slotWidths widths: [CGFloat]
    ) -> Int {
        guard !widths.isEmpty else { return 0 }
        var sourceStart: CGFloat = 0
        var cursor: CGFloat = 0
        for i in widths.indices {
            if i == source { sourceStart = cursor }
            cursor += widths[i]
        }
        let fingerX = sourceStart + widths[source] / 2 + dragX

        cursor = 0
        for i in widths.indices {
            let mid = cursor + widths[i] / 2
            // `<=` so a finger sitting exactly on the source's own midpoint (no drag,
            // or drag that returns to start) maps back to the source slot, not the next.
            if fingerX <= mid { return i }
            cursor += widths[i]
        }
        return widths.count - 1
    }

    /// Pure: convert a pixel-distance drag on a leading/trailing trim handle into the
    /// (leadingTrim, trailingTrim) `CMTime` pair surfaced by ``onTrim``.
    ///
    /// **Sign convention.** Positive means *trim* (clip got shorter on that side); negative
    /// means *extend* (clip wants more material on that side; the consumer decides whether
    /// the underlying asset / duration permits it).
    /// - Leading edge dragged right (+px) → leadingTrim positive (front trimmed).
    /// - Leading edge dragged left  (-px) → leadingTrim negative (extending front).
    /// - Trailing edge dragged right (+px) → trailingTrim negative (extending back).
    /// - Trailing edge dragged left  (-px) → trailingTrim positive (back trimmed).
    ///
    /// The non-dragged edge's delta is always `.zero`.
    ///
    /// Internal so trim math is unit-testable without driving SwiftUI gestures.
    internal static func computeTrimDeltas(
        edge: TrimEdge,
        pixelDelta: CGFloat,
        pxPerSecond: Double
    ) -> (leading: CMTime, trailing: CMTime) {
        guard pxPerSecond > 0 else { return (.zero, .zero) }
        let seconds = Double(pixelDelta) / pxPerSecond
        let cm = CMTime(seconds: seconds, preferredTimescale: 600)
        switch edge {
        case .leading:
            return (cm, .zero)
        case .trailing:
            // Dragging trailing edge right (+px) extends the clip → trailingTrim is negative.
            return (.zero, CMTime(seconds: -seconds, preferredTimescale: 600))
        }
    }

    /// Pure: produce the reordered clips array, gluing the source media clip's trailing
    /// transition (if any) so it travels along. Returns `nil` for no-op moves (dropping
    /// inside the source's own group). The returned `targetIndex` is where the source
    /// media clip lands in the new array (always pointing at a media clip, never a
    /// transition).
    ///
    /// Internal so `TimelineView`'s reorder math can be unit-tested without driving
    /// SwiftUI gestures.
    internal static func applyReorder(
        clips: [any Clip],
        from sourceIndex: Int,
        to rawTarget: Int
    ) -> (newClips: [any Clip], targetIndex: Int)? {
        let groupSize = (sourceIndex + 1 < clips.count
                         && clips[sourceIndex + 1] is Kadr.Transition) ? 2 : 1

        if rawTarget >= sourceIndex && rawTarget < sourceIndex + groupSize { return nil }

        var newClips = clips
        let group = Array(newClips[sourceIndex..<sourceIndex + groupSize])
        newClips.removeSubrange(sourceIndex..<sourceIndex + groupSize)

        // Map the original-coordinate target into a new-array insertion index. We want
        // the source's lead element to land at `rawTarget` in the FINAL array.
        // - source > target: target slots are unchanged by the removal → insert at `rawTarget`.
        // - source < target: target was past the removal; account for the (groupSize - 1)
        //   slots that collapsed leftward between source and target.
        let insertIndex = rawTarget > sourceIndex
            ? rawTarget - (groupSize - 1)
            : rawTarget
        let clamped = max(0, min(insertIndex, newClips.count))

        newClips.insert(contentsOf: group, at: clamped)
        return (newClips, clamped)
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

    /// Composition duration in seconds — used as the time-axis denominator. In v0.5
    /// this consults the lane assignment so Tracks and free-floaters are included,
    /// not just the implicit chain. Returns `0` when nothing has been resolved yet.
    /// Chain-only compositions produce the same value as v0.4.x's pure-sum walk.
    private func compositionDuration() -> Double {
        let lanes = TimelineView.assignLanes(for: video, includeAudio: false)
        var maxEnd: CMTime = .zero
        for (kind, items) in lanes {
            // Implicit chain duration uses durationForClip so async-resolved
            // VideoClip durations are honored on first appear.
            if case .implicitChain = kind {
                var cursor: CMTime = .zero
                for index in video.clips.indices {
                    let clip = video.clips[index]
                    if clip is Track { continue }
                    if clip.startTime != nil { continue }
                    if clip is Kadr.Transition { continue }  // doesn't advance the chain cursor
                    cursor = CMTimeAdd(cursor, durationForClip(at: index))
                }
                if CMTimeCompare(cursor, maxEnd) > 0 { maxEnd = cursor }
                continue
            }
            // Other lanes use the synchronous duration the assignment helper computed.
            for item in items {
                let end = CMTimeAdd(item.startTime, item.duration)
                if CMTimeCompare(end, maxEnd) > 0 { maxEnd = end }
            }
        }
        return CMTimeGetSeconds(maxEnd)
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

// MARK: - Triangle shape for the scrub-strip playhead marker

@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
