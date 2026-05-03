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
///
/// **Multi-lane (v0.5+).** When the composition has Kadr 0.6 multi-track content
/// (``Kadr/Track`` blocks or clips pinned with `.at(time:)`), the timeline switches to
/// a stacked-lane render: lane 0 is the implicit chain, then one lane per `Track` in
/// declaration order, then greedy-packed rows of free-floaters, then optional audio
/// lanes. Chain-only compositions render unchanged from v0.4.x. Edit gestures (reorder
/// and trim) apply on the implicit-chain lane in both modes — reorder is chain-aware,
/// so dragging a chain clip never disturbs Track or free-floater positions in the full
/// `video.clips` array (added in v0.5.1). Other lanes remain read-only.
@available(iOS 16, macOS 13, tvOS 16, visionOS 1, *)
public struct TimelineView: View {

    private let video: Video
    private let currentTime: Binding<CMTime>?
    private let selectedClipID: Binding<ClipID?>?
    private let zoom: Binding<TimelineZoom>?
    private let laneHeight: CGFloat
    private let laneSpacing: CGFloat
    private let showAudioLanes: Bool
    private let showAudioWaveforms: Bool
    private let showLaneLabels: Bool
    private let onReorder: ((_ from: Int, _ to: Int, _ newClips: [any Clip]) -> Void)?
    private let onTrim: ((_ clipIndex: Int, _ leadingTrim: CMTime, _ trailingTrim: CMTime) -> Void)?
    private let onTrackReorder: ((_ trackIndex: Int, _ from: Int, _ to: Int, _ newClips: [any Clip]) -> Void)?
    private let onTrackTrim: ((_ trackIndex: Int, _ clipIndex: Int, _ leadingTrim: CMTime, _ trailingTrim: CMTime) -> Void)?

    /// In-flight pinch baseline. `nil` outside the gesture; captures the
    /// pre-gesture density on first `onChanged` so subsequent updates multiply
    /// from a stable base instead of compounding.
    @State private var pinchBaseline: Double?

    /// Resolved durations for clips whose `Clip.duration` is synchronously `.zero`
    /// (currently only untrimmed `VideoClip`s). Keyed by index in `video.clips`.
    @State private var resolvedDurations: [Int: CMTime] = [:]

    /// Index of the media clip currently being dragged, if any.
    @State private var draggingIndex: Int?
    /// Horizontal pixel offset of the dragged clip from its resting position.
    @State private var dragOffset: CGFloat = 0

    /// Identity of the in-flight Track-lane reorder drag, if any. `trackIndex` is
    /// the lane's Track-only index (matching `LaneKind.track(index:...)`); `clipIndex`
    /// is the clip position within that Track's `clips` array.
    @State private var draggingTrackInfo: TrackDragKey?
    @State private var trackDragOffset: CGFloat = 0

    /// Identity of the in-flight Track-lane trim drag, if any.
    @State private var trimmingTrackInfo: TrackDragKey?
    @State private var trimmingTrackEdge: TrimEdge?
    @State private var trimmingTrackPixelDelta: CGFloat = 0

    internal struct TrackDragKey: Equatable {
        let trackIndex: Int
        let clipIndex: Int
    }

    /// Index of the clip whose trim handle is currently being dragged, if any.
    @State private var trimmingIndex: Int?
    /// Whether the trim drag is on the leading (left) or trailing (right) handle.
    @State private var trimmingEdge: TrimEdge?
    /// Current pixel delta of the in-flight trim drag. Drives the live width/offset
    /// preview on the dragged clip; applied to the callback in seconds on release.
    @State private var trimPixelDelta: CGFloat = 0

    /// Cached waveforms keyed by audio asset URL. Populated lazily when
    /// `showAudioWaveforms` is enabled. Survives clip-state changes; cleared only
    /// when the host view re-mounts. Added in v0.5.3.
    @State private var audioWaveforms: [URL: AudioWaveform] = [:]
    /// URLs whose load has already been scheduled. Prevents the re-load loop when
    /// `Video.audioTracks` is recomputed by the parent on every body invalidation.
    @State private var waveformLoadScheduled: Set<URL> = []

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
    ///   - onTrackReorder: Optional callback fired when the user drags a clip *inside*
    ///     a ``Kadr/Track`` block to a new position within that track. Receives the
    ///     Track-only ordinal `trackIndex`, the source/target positions inside
    ///     `track.clips`, and the **new full `video.clips` array** with the rebuilt
    ///     `Track` substituted in place. Inner ``Kadr/Transition``s travel with their
    ///     preceding clip — same rule as the implicit chain. The Track's `startTime`,
    ///     `name`, and `opacityFactor` are preserved by ``TimelineView/applyTrackReorder(track:from:to:)``.
    ///     Added in v0.7.
    ///   - onTrackTrim: Optional callback for trim drags on a Track-lane clip. Same
    ///     delta semantics as ``onTrim``, with an extra `trackIndex` qualifier
    ///     identifying which Track the clip lives in. When non-`nil`, thin grab
    ///     handles render on the leading and trailing edges of every non-transition
    ///     Track-lane block (added in v0.7.1).
    public init(
        _ video: Video,
        currentTime: Binding<CMTime>? = nil,
        selectedClipID: Binding<ClipID?>? = nil,
        zoom: Binding<TimelineZoom>? = nil,
        laneHeight: CGFloat = 40,
        laneSpacing: CGFloat = 4,
        showAudioLanes: Bool = true,
        showAudioWaveforms: Bool = false,
        showLaneLabels: Bool = false,
        onReorder: ((_ from: Int, _ to: Int, _ newClips: [any Clip]) -> Void)? = nil,
        onTrim: ((_ clipIndex: Int, _ leadingTrim: CMTime, _ trailingTrim: CMTime) -> Void)? = nil,
        onTrackReorder: ((_ trackIndex: Int, _ from: Int, _ to: Int, _ newClips: [any Clip]) -> Void)? = nil,
        onTrackTrim: ((_ trackIndex: Int, _ clipIndex: Int, _ leadingTrim: CMTime, _ trailingTrim: CMTime) -> Void)? = nil
    ) {
        self.video = video
        self.currentTime = currentTime
        self.selectedClipID = selectedClipID
        self.zoom = zoom
        self.laneHeight = laneHeight
        self.laneSpacing = laneSpacing
        self.showAudioLanes = showAudioLanes
        self.showAudioWaveforms = showAudioWaveforms
        self.showLaneLabels = showLaneLabels
        self.onReorder = onReorder
        self.onTrim = onTrim
        self.onTrackReorder = onTrackReorder
        self.onTrackTrim = onTrackTrim
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalSeconds = compositionDuration()
            // v0.7: when zoom is bound, derive pxPerSecond from the binding;
            // otherwise stick with the v0.4–v0.6 fit-to-width math.
            let pxPerSecond: Double = {
                if let zoom = zoom?.wrappedValue {
                    return zoom.pixelsPerSecond
                }
                return totalSeconds > 0 ? Double(geometry.size.width) / totalSeconds : 0
            }()
            let lanes = TimelineView.assignLanes(for: video, includeAudio: showAudioLanes)
            let nonAudioLaneCount = lanes.reduce(into: 0) { acc, lane in
                if case .audio = lane.0 {} else { acc += 1 }
            }

            laneContent(
                lanes: lanes,
                pxPerSecond: pxPerSecond,
                totalSeconds: totalSeconds,
                nonAudioLaneCount: nonAudioLaneCount,
                viewportSize: geometry.size
            )
        }
        .task {
            await resolveDurations()
        }
        .task(id: waveformLoadKey) {
            await loadWaveformsIfNeeded()
        }
    }

    /// Renders the lane stack. When `zoom` is non-nil the content is wrapped in a
    /// horizontal `ScrollView` and a `MagnifyGesture` mutates the bound zoom; when
    /// `zoom` is nil the layout fills the geometry width pixel-identically to
    /// v0.4–v0.6.
    @ViewBuilder
    private func laneContent(
        lanes: [(LaneKind, [LaneItem])],
        pxPerSecond: Double,
        totalSeconds: Double,
        nonAudioLaneCount: Int,
        viewportSize: CGSize
    ) -> some View {
        let totalWidth = max(viewportSize.width, CGFloat(totalSeconds * pxPerSecond))
        let stack = ZStack(alignment: .topLeading) {
            if nonAudioLaneCount <= 1 {
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
                    height: viewportSize.height
                )
            }
        }
        .frame(width: totalWidth, alignment: .topLeading)

        if zoom != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                stack
            }
            .gesture(zoomGesture(totalSeconds: totalSeconds))
        } else {
            stack
        }
    }

    /// Pinch-to-zoom that mutates the bound `TimelineZoom`. Captures the
    /// pre-gesture density on first `onChanged` so subsequent updates multiply
    /// from a stable base; clears on `onEnded`. Uses `MagnificationGesture` for
    /// iOS 16 / macOS 13 deployment-floor compatibility (the iOS-17
    /// `MagnifyGesture` raises the floor).
    private func zoomGesture(totalSeconds: Double) -> some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.01)
            .onChanged { magnification in
                guard let binding = zoom else { return }
                let baseline: Double
                if let captured = pinchBaseline {
                    baseline = captured
                } else {
                    baseline = binding.wrappedValue.pixelsPerSecond
                    pinchBaseline = baseline
                }
                let scaled = baseline * Double(magnification)
                binding.wrappedValue.pixelsPerSecond = TimelineZoom.clamp(scaled)
            }
            .onEnded { _ in
                pinchBaseline = nil
            }
    }

    /// Identity for `.task(id:)` driving waveform loading — re-fires when the audio
    /// track list shape changes, but not on every body re-eval.
    private var waveformLoadKey: WaveformLoadKey {
        WaveformLoadKey(enabled: showAudioWaveforms, urls: video.audioTracks.map(\.url))
    }

    private struct WaveformLoadKey: Hashable {
        let enabled: Bool
        let urls: [URL]
    }

    private func loadWaveformsIfNeeded() async {
        guard showAudioWaveforms else { return }
        for audio in video.audioTracks {
            let url = audio.url
            if waveformLoadScheduled.contains(url) { continue }
            waveformLoadScheduled.insert(url)
            // Render at a generous resolution; the lane block decimates further if
            // it's narrower than the peak count.
            let waveform = (try? await AudioWaveformLoader.load(url: url, sampleCount: 240)) ?? .empty
            audioWaveforms[url] = waveform
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
                Group {
                    if case .implicitChain = lanes[i].0 {
                        // Lane 0 — full editable chain HStack. Reorder/trim gestures
                        // work just like in v0.4.x; the underlying math is chain-aware
                        // so Tracks and free-floaters stay put when the user reorders.
                        editableChainLane(pxPerSecond: pxPerSecond)
                    } else {
                        laneRow(
                            lane: lanes[i],
                            pxPerSecond: pxPerSecond,
                            totalSeconds: totalSeconds
                        )
                    }
                }
                .frame(height: laneHeight)
            }
        }
    }

    /// Editable chain lane for the multi-track render — same `clipBlock` HStack the
    /// chain-only path uses, but iterating only chain indices so Tracks and floaters
    /// don't appear in this row. Reorder/trim gestures route through the chain-aware
    /// helpers (``applyChainReorder``).
    @ViewBuilder
    private func editableChainLane(pxPerSecond: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(chainIndicesArray, id: \.self) { index in
                clipBlock(at: index, pxPerSecond: pxPerSecond)
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
        // For audio lanes, look up the source URL via the lane's index so we can
        // overlay the cached waveform when available.
        let audioURL: URL? = {
            if case let .audio(index, _) = lane.0,
               video.audioTracks.indices.contains(index) {
                return video.audioTracks[index].url
            }
            return nil
        }()
        ZStack(alignment: .topLeading) {
            // Lane background — subtle, distinguishes adjacent lanes.
            RoundedRectangle(cornerRadius: 2)
                .fill(.gray.opacity(0.08))
                .frame(width: totalWidth, height: laneHeight)
            ForEach(lane.1.indices, id: \.self) { i in
                let item = lane.1[i]
                let waveform: AudioWaveform? = {
                    guard showAudioWaveforms, item.kind == .audio, let url = audioURL else { return nil }
                    return audioWaveforms[url]
                }()
                if case let .track(trackIndex, _, _) = lane.0,
                   onTrackReorder != nil || onTrackTrim != nil {
                    trackItemBlock(
                        trackIndex: trackIndex,
                        clipIndex: i,
                        item: item,
                        items: lane.1,
                        pxPerSecond: pxPerSecond
                    )
                } else {
                    laneItemBlock(item: item, pxPerSecond: pxPerSecond, waveform: waveform)
                }
            }
            if case .audio = lane.0 {
                ForEach(TimelineView.crossfadeBoundaries(in: video), id: \.value) { boundary in
                    let x = max(0, CMTimeGetSeconds(boundary) * pxPerSecond)
                    CrossfadeGlyph()
                        .frame(width: 10, height: 10)
                        .foregroundStyle(.white.opacity(0.85))
                        .position(x: x, y: laneHeight / 2)
                        .allowsHitTesting(false)
                }
            }
            if showLaneLabels, let label = TimelineView.laneLabel(for: lane.0) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Pure: derives a short display label for a lane kind. Returns `nil` for the
    /// implicit chain (the chain has no label since it's the timeline's spine).
    /// Internal so label semantics are unit-testable without driving SwiftUI.
    nonisolated internal static func laneLabel(for kind: LaneKind) -> String? {
        switch kind {
        case .implicitChain:
            return nil
        case .track(let index, _, let label):
            return label ?? "Track \(index + 1)"
        case .freeFloaters(let pack):
            return pack == 0 ? "Floaters" : "Floaters \(pack + 1)"
        case .audio(let index, let label):
            return label ?? "Audio \(index + 1)"
        }
    }

    @ViewBuilder
    private func laneItemBlock(item: LaneItem, pxPerSecond: Double, waveform: AudioWaveform? = nil) -> some View {
        let x = max(0, CMTimeGetSeconds(item.startTime) * pxPerSecond)
        let w = max(0, CMTimeGetSeconds(item.duration) * pxPerSecond)
        let isSelected = selectedClipID != nil && item.clipID != nil && selectedClipID?.wrappedValue == item.clipID
        let block = RoundedRectangle(cornerRadius: 4)
            .fill(laneItemColor(item.kind))
            .frame(width: w, height: laneHeight)

        let view = ZStack {
            block
            if let waveform, !waveform.peaks.isEmpty {
                AudioWaveformShape(peaks: waveform.peaks)
                    .fill(Color.white.opacity(0.7))
                    .frame(width: w, height: laneHeight)
                    .allowsHitTesting(false)
            }
        }
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

    /// Editable Track-lane item block. Mirrors ``laneItemBlock`` visually but adds
    /// a drag-to-reorder gesture (when ``onTrackReorder`` is set), trim handles on
    /// leading / trailing edges (when ``onTrackTrim`` is set), and tap-to-select.
    /// Inner ``Kadr/Transition``s render statically and don't host their own
    /// drag — they travel with the preceding clip via ``applyTrackReorder``.
    @ViewBuilder
    private func trackItemBlock(
        trackIndex: Int,
        clipIndex: Int,
        item: LaneItem,
        items: [LaneItem],
        pxPerSecond: Double
    ) -> some View {
        let baseX = max(0, CMTimeGetSeconds(item.startTime) * pxPerSecond)
        let w = max(0, CMTimeGetSeconds(item.duration) * pxPerSecond)
        let key = TrackDragKey(trackIndex: trackIndex, clipIndex: clipIndex)
        let isDragging = draggingTrackInfo == key
        let isTrimming = trimmingTrackInfo == key
        let dragOffsetX = isDragging ? trackDragOffset : 0
        let (liveWidth, liveTrimOffset) = trackLiveTrimMetrics(for: key, baseWidth: w)
        let isSelected = selectedClipID != nil && item.clipID != nil && selectedClipID?.wrappedValue == item.clipID
        let canTrim = item.kind != .transition && onTrackTrim != nil

        let inner = RoundedRectangle(cornerRadius: 4)
            .fill(laneItemColor(item.kind))
            .frame(width: max(0, liveWidth), height: laneHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.white : .clear, lineWidth: 2)
            )
            .overlay(alignment: .leading) {
                if canTrim {
                    trackTrimHandle(key: key, edge: .leading, pxPerSecond: pxPerSecond)
                }
            }
            .overlay(alignment: .trailing) {
                if canTrim {
                    trackTrimHandle(key: key, edge: .trailing, pxPerSecond: pxPerSecond)
                }
            }
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .shadow(color: .black.opacity(isDragging ? 0.3 : 0), radius: isDragging ? 6 : 0)
            .offset(x: liveTrimOffset)

        // Outer slot keeps reserved width fixed (so neighbors don't reflow during
        // a trim drag); the colored inner block morphs to `liveWidth + liveTrimOffset`.
        let block = inner
            .frame(width: max(0, w), height: laneHeight, alignment: .topLeading)
            .offset(x: baseX + dragOffsetX)
            .zIndex(isDragging || isTrimming ? 1 : 0)
            .contentShape(Rectangle())

        // Transitions don't host their own reorder gesture — they travel with the
        // preceding clip in `applyTrackReorder`. Tap-to-select still works on
        // identified clips.
        let canDrag = item.kind != .transition && onTrackReorder != nil
        let withGesture = block.modifier(
            OptionalGestureModifier(
                gesture: canDrag
                    ? trackReorderGesture(
                        trackIndex: trackIndex,
                        clipIndex: clipIndex,
                        items: items,
                        pxPerSecond: pxPerSecond
                      )
                    : nil
            )
        )
        if let id = item.clipID, let binding = selectedClipID {
            withGesture.onTapGesture {
                binding.wrappedValue = (binding.wrappedValue == id) ? nil : id
            }
        } else {
            withGesture
        }
    }

    /// Live-width and leading-offset for a Track-lane clip during a trim drag. Reuses
    /// the same pure helper the chain path uses, so morph semantics match.
    private func trackLiveTrimMetrics(for key: TrackDragKey, baseWidth: CGFloat) -> (width: CGFloat, offset: CGFloat) {
        guard trimmingTrackInfo == key, let edge = trimmingTrackEdge else {
            return (baseWidth, 0)
        }
        return TimelineView.liveTrimMetrics(edge: edge, baseWidth: baseWidth, pixelDelta: trimmingTrackPixelDelta)
    }

    @ViewBuilder
    private func trackTrimHandle(key: TrackDragKey, edge: TrimEdge, pxPerSecond: Double) -> some View {
        let isActive = trimmingTrackInfo == key && trimmingTrackEdge == edge
        Rectangle()
            .fill(isActive ? Color.white : Color.white.opacity(0.5))
            .frame(width: 4)
            .contentShape(Rectangle().inset(by: -6))   // wider hit target than visual
            .gesture(trackTrimGesture(key: key, edge: edge, pxPerSecond: pxPerSecond))
    }

    private func trackTrimGesture(key: TrackDragKey, edge: TrimEdge, pxPerSecond: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if onTrackTrim == nil { return }
                if trimmingTrackInfo == nil {
                    trimmingTrackInfo = key
                    trimmingTrackEdge = edge
                }
                trimmingTrackPixelDelta = value.translation.width
            }
            .onEnded { value in
                defer {
                    trimmingTrackInfo = nil
                    trimmingTrackEdge = nil
                    trimmingTrackPixelDelta = 0
                }
                guard onTrackTrim != nil, pxPerSecond > 0 else { return }
                let (leading, trailing) = TimelineView.computeTrimDeltas(
                    edge: edge,
                    pixelDelta: value.translation.width,
                    pxPerSecond: pxPerSecond
                )
                onTrackTrim?(key.trackIndex, key.clipIndex, leading, trailing)
            }
    }

    private struct OptionalGestureModifier<G: Gesture>: ViewModifier {
        let gesture: G?
        func body(content: Content) -> some View {
            if let gesture {
                content.gesture(gesture)
            } else {
                content
            }
        }
    }

    /// Drag-to-reorder gesture for a Track-lane clip. On release, computes the new
    /// position via ``computeTargetIndex(source:dragX:slotWidths:)`` over the
    /// Track's inner clip slot widths, rebuilds the Track via ``applyTrackReorder``,
    /// and fires ``onTrackReorder`` with the substituted full ``Video/clips`` array.
    private func trackReorderGesture(
        trackIndex: Int,
        clipIndex: Int,
        items: [LaneItem],
        pxPerSecond: Double
    ) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if onTrackReorder == nil { return }
                if draggingTrackInfo == nil {
                    draggingTrackInfo = TrackDragKey(trackIndex: trackIndex, clipIndex: clipIndex)
                }
                trackDragOffset = value.translation.width
            }
            .onEnded { value in
                defer {
                    draggingTrackInfo = nil
                    trackDragOffset = 0
                }
                guard onTrackReorder != nil else { return }
                let widths: [CGFloat] = items.map {
                    CGFloat(CMTimeGetSeconds($0.duration) * pxPerSecond)
                }
                let target = TimelineView.computeTargetIndex(
                    source: clipIndex,
                    dragX: value.translation.width,
                    slotWidths: widths
                )
                handleTrackReorder(trackIndex: trackIndex, from: clipIndex, to: target)
            }
    }

    /// Apply a Track-lane reorder: rebuild the Track via ``applyTrackReorder`` and
    /// substitute it back into a fresh `video.clips` array, then fire the callback.
    private func handleTrackReorder(trackIndex: Int, from sourceIndex: Int, to rawTarget: Int) {
        let originalIdx = originalIndexForTrack(trackIndex: trackIndex)
        guard let originalIdx,
              let track = video.clips[originalIdx] as? Track,
              let rebuilt = TimelineView.applyTrackReorder(
                track: track,
                from: sourceIndex,
                to: rawTarget
              )
        else { return }
        var newClips = Array(video.clips)
        newClips[originalIdx] = rebuilt
        // Translate the chain-result-style targetIndex back. `applyTrackReorder`
        // delegates to `applyReorder`, so the source media clip lands at the same
        // post-insertion position the chain helper would compute.
        guard let result = TimelineView.applyReorder(
            clips: track.clips,
            from: sourceIndex,
            to: rawTarget
        ) else { return }
        onTrackReorder?(trackIndex, sourceIndex, result.targetIndex, newClips)
    }

    /// Original index in `video.clips` of the Track at Track-only ordinal `trackIndex`.
    private func originalIndexForTrack(trackIndex: Int) -> Int? {
        var seen = 0
        for (i, clip) in video.clips.enumerated() {
            if clip is Track {
                if seen == trackIndex { return i }
                seen += 1
            }
        }
        return nil
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

            if showAudioLanes && !video.audioTracks.isEmpty {
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
    nonisolated internal static func scrubTime(x: CGFloat, pxPerSecond: Double, totalSeconds: Double) -> Double {
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

    /// Original-array indices of clips that participate in the implicit chain. In
    /// chain-only compositions, this equals every index in `video.clips`. In multi-
    /// track compositions, it skips Tracks and free-floaters so reorder/trim math
    /// operates on chain items only.
    private var chainIndicesArray: [Int] {
        TimelineView.chainIndices(in: Array(video.clips))
    }

    /// Slot widths in chain order. Used as `slotWidths` for `computeTargetIndex` /
    /// `reorderShiftOffset`. Source/target indices passed to those helpers must be
    /// **chain-positions**, not original-array indices.
    private func chainSlotWidths(pxPerSecond: Double) -> [CGFloat] {
        chainIndicesArray.map {
            CGFloat(CMTimeGetSeconds(durationForClip(at: $0))) * pxPerSecond
        }
    }

    /// True if `index` is the source media clip OR its trailing transition during an
    /// in-flight reorder drag. Both travel together visually.
    private func isPartOfSourceGroup(_ index: Int) -> Bool {
        guard let src = draggingIndex else { return false }
        let chain = chainIndicesArray
        guard let srcPos = chain.firstIndex(of: src),
              let idxPos = chain.firstIndex(of: index) else { return false }
        let groupSize = sourceGroupSize(for: src)
        return idxPos >= srcPos && idxPos < srcPos + groupSize
    }

    /// Group size in chain-position units — 2 if the next chain item is a Transition
    /// (which travels with the source), else 1.
    private func sourceGroupSize(for src: Int) -> Int {
        let chain = chainIndicesArray
        guard let srcPos = chain.firstIndex(of: src),
              srcPos + 1 < chain.count else { return 1 }
        return video.clips[chain[srcPos + 1]] is Kadr.Transition ? 2 : 1
    }

    /// Horizontal offset to apply to clip `index` for live reorder feedback. The source
    /// group rides the finger; clips between source and projected target shift left or
    /// right by the source-group width to visually open the drop slot.
    private func clipReorderOffset(for index: Int, pxPerSecond: Double) -> CGFloat {
        guard let src = draggingIndex else { return 0 }
        let chain = chainIndicesArray
        guard let srcPos = chain.firstIndex(of: src),
              let idxPos = chain.firstIndex(of: index) else { return 0 }
        let groupSize = sourceGroupSize(for: src)
        if idxPos >= srcPos && idxPos < srcPos + groupSize {
            return dragOffset   // source group rides the finger
        }
        let widths = chainSlotWidths(pxPerSecond: pxPerSecond)
        let targetPos = TimelineView.computeTargetIndex(
            source: srcPos, dragX: dragOffset, slotWidths: widths
        )
        return TimelineView.reorderShiftOffset(
            index: idxPos,
            source: srcPos,
            groupSize: groupSize,
            target: targetPos,
            slotWidths: widths
        )
    }

    /// Drives `.animation(value:)` so SwiftUI re-runs the snappy transition only on
    /// state changes that should animate (a slot crossing), not on every drag pixel.
    private func reorderAnimationKey(for index: Int, pxPerSecond: Double) -> Int {
        guard let src = draggingIndex, src != index else { return 0 }
        let chain = chainIndicesArray
        guard let srcPos = chain.firstIndex(of: src) else { return 0 }
        let widths = chainSlotWidths(pxPerSecond: pxPerSecond)
        return TimelineView.computeTargetIndex(source: srcPos, dragX: dragOffset, slotWidths: widths)
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
    nonisolated internal static func reorderShiftOffset(
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
    nonisolated internal static func liveTrimMetrics(
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

    /// Resolve a drop slot for a reorder drag. `source` is the **original-array** index
    /// of the dragged chain item; `dragX` is the cumulative horizontal pixel translation.
    /// Returns the **original-array** index of the slot the drop lands on.
    private func computeTargetIndex(source: Int, dragX: CGFloat, pxPerSecond: Double) -> Int {
        let chain = chainIndicesArray
        guard let srcPos = chain.firstIndex(of: source) else { return source }
        let widths = chainSlotWidths(pxPerSecond: pxPerSecond)
        let targetPos = TimelineView.computeTargetIndex(
            source: srcPos, dragX: dragX, slotWidths: widths
        )
        // Translate the chain-position back to an original-array index.
        guard chain.indices.contains(targetPos) else { return source }
        return chain[targetPos]
    }

    /// Apply a reorder gesture. Operates on chain-only indices and uses
    /// `applyChainReorder` to keep Tracks and free-floaters in their original slots.
    private func handleReorder(from sourceIndex: Int, to rawTarget: Int) {
        let chain = chainIndicesArray
        guard let srcPos = chain.firstIndex(of: sourceIndex),
              let targetPos = chain.firstIndex(of: rawTarget) else { return }
        guard let result = TimelineView.applyChainReorder(
            clips: Array(video.clips),
            from: srcPos,
            to: targetPos
        ) else { return }
        // Translate the new chain-position the source landed at back to an
        // original-array index for the consumer's callback.
        let newChain = TimelineView.chainIndices(in: result.newClips)
        let newSourceOriginalIdx = newChain.indices.contains(result.chainTargetIndex)
            ? newChain[result.chainTargetIndex]
            : sourceIndex
        onReorder?(sourceIndex, newSourceOriginalIdx, result.newClips)
    }

    /// Pure: which slot does the dragged clip's center lie over after `dragX` pixels of
    /// horizontal translation? Walks slot widths and returns the first slot whose
    /// midpoint exceeds the projected finger x.
    ///
    /// Internal so `TimelineView`'s reorder math can be unit-tested without driving
    /// SwiftUI gestures.
    nonisolated internal static func computeTargetIndex(
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
    nonisolated internal static func computeTrimDeltas(
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
    nonisolated internal static func applyReorder(
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

/// Two opposing triangles meeting at the centerline — the audio crossfade marker. The
/// left triangle points right, the right triangle points left, evoking the cross of
/// two fading audio tracks. Visual-only; non-interactive.
private struct CrossfadeGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                // Left triangle pointing right.
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: w / 2, y: h / 2))
                path.closeSubpath()
                // Right triangle pointing left.
                path.move(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w / 2, y: h / 2))
                path.closeSubpath()
            }
            .fill(.foreground)
        }
    }
}
